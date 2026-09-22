package com.lacaprichosa.app

import android.content.ContentValues
import android.content.Context
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteDatabaseCorruptException
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.io.Closeable
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.UUID

internal class SqliteStateStore(private val context: Context, private val cipher: StateCipher) : Closeable {
    private val helper = Helper(context)
    private val db: SQLiteDatabase

    init {
        try {
            check(context.getDatabasePath(DATABASE_NAME).exists() ||
                !NativeJsonStore.prefs(context).getBoolean(StateVault.SQLITE_MARKER, false)) {
                "SQLite database missing after migration"
            }
            db = helper.writableDatabase
            migrate()
        } catch (error: Exception) {
            helper.close()
            throw error
        }
    }

    override fun close() = helper.close()

    fun <T> transaction(action: () -> T): T {
        db.beginTransaction()
        try {
            val result = action()
            db.setTransactionSuccessful()
            return result
        } finally {
            db.endTransaction()
        }
    }

    fun readMain(): JSONObject = root().getJSONObject("main")
    fun uiRevision(): Long = root().optLong("uiRevision", 0L)
    fun readState(collections: Set<String> = NativeJsonStore.partNames.toSet()): JSONObject {
        require(collections.all { it in NativeJsonStore.partNames })
        return fullState(root(), collections)
    }

    fun writeMain(main: JSONObject) {
        check(db.inTransaction())
        val root = root()
        root.put("main", main)
        saveRoot(root)
    }

    fun write(main: JSONObject, parts: Map<String, Any>): Long {
        check(db.inTransaction())
        val root = root()
        for ((name, value) in parts) replaceCollection(root, name, value)
        root.put("main", main)
        val revision = root.optLong("uiRevision", 0L) + 1L
        root.put("uiRevision", revision)
        saveRoot(root)
        return revision
    }

    private fun migrate() {
        val legacy = StateVault(context, cipher)
        transaction {
            val count = scalar("SELECT COUNT(*) FROM store_meta")
            if (count == 0L) {
                check(!NativeJsonStore.prefs(context).getBoolean(StateVault.SQLITE_MARKER, false)) {
                    "Missing SQLite metadata"
                }
                check(NativeJsonStore.partNames.all { scalar("SELECT COUNT(*) FROM $it") == 0L }) {
                    "Incomplete SQLite store"
                }
                val source = legacy.snapshot()
                val main = JSONObject(source.toString())
                val root = JSONObject().put("format", 1).put("main", main)
                    .put("collections", JSONObject()).put("verified", false).put("legacyClean", false)
                for (name in NativeJsonStore.partNames) {
                    if (main.has(name)) replaceCollection(root, name, requireNotNull(main.remove(name)))
                }
                saveRoot(root)
                check(canonical(fullState(root())) == canonical(source)) { "SQLite migration mismatch" }
            }
        }
        var root = root()
        if (!root.getBoolean("verified")) {
            // Re-read after commit; the legacy source is still intact at this point.
            transaction {
                root = root()
                check(canonical(fullState(root)) == canonical(legacy.snapshot())) { "SQLite verification failed" }
                root.put("verified", true)
                saveRoot(root)
            }
        }
        if (!root.getBoolean("legacyClean")) {
            transaction { fullState(root()) }
            legacy.finishMigration()
            transaction {
                val current = root()
                current.put("legacyClean", true)
                saveRoot(current)
            }
        }
    }

    private fun root(): JSONObject {
        val raw = db.rawQuery("SELECT payload FROM store_meta WHERE id = 1", null).use {
            check(it.moveToFirst()) { "Missing SQLite metadata" }
            it.getString(0)
        }
        val root = JSONObject(cipher.decrypt(ROOT_AAD, raw))
        check(root.getInt("format") == 1) { "Unsupported SQLite format" }
        root.getJSONObject("main")
        check(root.getJSONObject("collections").keys().asSequence().all { it in NativeJsonStore.partNames }) {
            "Unknown SQLite collection"
        }
        return root
    }

    private fun saveRoot(root: JSONObject) {
        val payload = cipher.encrypt(ROOT_AAD, root.toString())
        db.insertWithOnConflict("store_meta", null, ContentValues().apply {
            put("id", 1)
            put("payload", payload)
        }, SQLiteDatabase.CONFLICT_REPLACE).also { check(it != -1L) { "Cannot write SQLite metadata" } }
    }

    private data class Row(val id: String, val position: Int, val sealed: String)
    private data class Decoded(val row: Row, val plain: String, val value: JSONObject)

    private fun rows(root: JSONObject, name: String): List<Row> {
        require(name in NativeJsonStore.partNames)
        val rows = db.rawQuery("SELECT row_id, position, payload FROM $name ORDER BY position", null).use {
            buildList {
                while (it.moveToNext()) add(Row(it.getString(0), it.getInt(1), it.getString(2)))
            }
        }
        val meta = root.getJSONObject("collections").optJSONObject(name)
        if (meta == null) check(rows.isEmpty()) { "Unexpected SQLite records" }
        else {
            check(meta.getInt("count") == rows.size && meta.getString("digest") == digest(rows)) {
                "SQLite collection integrity failure"
            }
            check(rows.withIndex().all { (index, row) -> row.position == index }) { "Invalid SQLite order" }
        }
        return rows
    }

    private fun decode(name: String, rows: List<Row>): List<Decoded> = rows.map { row ->
        val plain = cipher.decrypt(rowAad(name, row.id), row.sealed)
        val value = JSONObject(plain)
        check(value.has("value")) { "Invalid SQLite record" }
        Decoded(row, plain, value)
    }

    private fun fullState(root: JSONObject, selected: Set<String> = NativeJsonStore.partNames.toSet()): JSONObject {
        val state = JSONObject(root.getJSONObject("main").toString())
        val collections = root.getJSONObject("collections")
        for (name in NativeJsonStore.partNames) {
            if (name !in selected) continue
            val rows = rows(root, name)
            if (!collections.has(name)) continue
            val decoded = decode(name, rows)
            if (name == "savingsFunds") {
                val values = JSONObject()
                for (entry in decoded) {
                    val key = entry.value.getString("key")
                    check(!values.has(key)) { "Duplicate savings key" }
                    values.put(key, entry.value.get("value"))
                }
                state.put(name, values)
            } else {
                state.put(name, JSONArray().apply { decoded.forEach { put(it.value.get("value")) } })
            }
        }
        return state
    }

    private fun replaceCollection(root: JSONObject, name: String, value: Any) {
        require(name in NativeJsonStore.partNames)
        val incoming = if (name == "savingsFunds") {
            require(value is JSONObject) { "Invalid savings collection" }
            value.keys().asSequence().sorted().map { key -> JSONObject().put("key", key).put("value", value.get(key)) }.toList()
        } else {
            require(value is JSONArray) { "Invalid array collection" }
            (0 until value.length()).map { JSONObject().put("value", value.get(it)) }
        }
        val previous = decode(name, rows(root, name))
        val available = mutableMapOf<String, ArrayDeque<Decoded>>()
        for (old in previous) available.getOrPut(identity(old.value)) { ArrayDeque() }.add(old)
        val retained = mutableSetOf<String>()
        val updated = incoming.mapIndexed { position, item ->
            val plain = canonical(item)
            val old = available[identity(item)]?.pollFirst()
            val id = old?.row?.id ?: UUID.randomUUID().toString()
            val sealed = if (old?.plain == plain) old.row.sealed else cipher.encrypt(rowAad(name, id), plain)
            if (old == null) {
                db.insertOrThrow(name, null, ContentValues().apply {
                    put("row_id", id)
                    put("position", position)
                    put("payload", sealed)
                })
            } else if (old.row.position != position || old.row.sealed != sealed) {
                check(db.update(name, ContentValues().apply {
                    put("position", position)
                    if (old.row.sealed != sealed) put("payload", sealed)
                }, "row_id = ?", arrayOf(id)) == 1) { "Missing SQLite record" }
            }
            retained.add(id)
            Row(id, position, sealed)
        }
        for (old in previous) if (old.row.id !in retained) db.delete(name, "row_id = ?", arrayOf(old.row.id))
        root.getJSONObject("collections").put(name, JSONObject().put("count", updated.size).put("digest", digest(updated)))
    }

    private fun identity(item: JSONObject): String {
        if (item.has("key")) return "key:" + item.getString("key")
        val id = (item.opt("value") as? JSONObject)?.opt("id")
        return if (id is String && id.isNotEmpty()) "id:$id" else "value:" + canonical(item)
    }

    private fun digest(rows: List<Row>): String {
        val digest = MessageDigest.getInstance("SHA-256")
        for (row in rows) {
            for (part in listOf(row.position.toString(), row.id, row.sealed)) {
                val bytes = part.toByteArray(Charsets.UTF_8)
                digest.update(ByteBuffer.allocate(4).putInt(bytes.size).array())
                digest.update(bytes)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }

    private fun scalar(sql: String): Long = db.rawQuery(sql, null).use { check(it.moveToFirst()); it.getLong(0) }

    private class Helper(context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, 1,
        DatabaseErrorHandler { throw SQLiteDatabaseCorruptException("Protected database is corrupt; retained for recovery") }) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onConfigure(db: SQLiteDatabase) { db.execSQL("PRAGMA synchronous=FULL") }
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE store_meta (id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL)")
            for (name in NativeJsonStore.partNames) {
                db.execSQL("CREATE TABLE $name (row_id TEXT PRIMARY KEY NOT NULL, position INTEGER NOT NULL CHECK (position >= 0), payload TEXT NOT NULL)")
                db.execSQL("CREATE INDEX ${name}_position ON $name(position)")
            }
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            error("Unsupported database upgrade: $oldVersion to $newVersion")
        }
        override fun onDowngrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            error("Database downgrade is not supported")
        }
    }

    companion object {
        const val DATABASE_NAME = "sin_rial_finance.db"
        private const val ROOT_AAD = "sqlite:v1:root"
        private fun rowAad(name: String, id: String) = "sqlite:v1:$name:$id"

        internal fun canonical(value: Any?): String = when (value) {
            is JSONObject -> value.keys().asSequence().sorted().joinToString(",", "{", "}") {
                JSONObject.quote(it) + ":" + canonical(value.get(it))
            }
            is JSONArray -> (0 until value.length()).joinToString(",", "[", "]") { canonical(value.get(it)) }
            is String -> JSONObject.quote(value)
            is Number -> JSONObject.numberToString(value)
            is Boolean -> value.toString()
            null, JSONObject.NULL -> "null"
            else -> error("Unsupported JSON value")
        }
    }
}
