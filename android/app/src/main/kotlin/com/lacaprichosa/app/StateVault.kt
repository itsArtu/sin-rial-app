package com.lacaprichosa.app

import android.content.Context
import android.util.Xml
import org.json.JSONArray
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import java.io.File

// Read-only source for the two pre-SQLite formats. SQLite owns all new writes.
internal class StateVault(private val context: Context, private val cipher: StateCipher) {
    private val legacy = NativeJsonStore.prefs(context)
    private val secure = context.getSharedPreferences(STORE_NAME, Context.MODE_PRIVATE)

    fun snapshot(): JSONObject {
        val encrypted = secure.contains("state")
        if (!encrypted) {
            val file = File(context.applicationInfo.dataDir, "shared_prefs/$STORE_NAME.xml")
            check(secure.all.isEmpty() && !file.exists() && !File(file.path + ".bak").exists()) {
                "Incomplete legacy secure store"
            }
            // Android can report an empty preferences map when its XML is damaged.
            if (legacy.all.isEmpty()) {
                val plain = File(context.applicationInfo.dataDir, "shared_prefs/${NativeJsonStore.STORE_NAME}.xml")
                val backup = File(plain.path + ".bak")
                val source = if (backup.exists()) backup else plain
                if (source.exists()) source.inputStream().use { input ->
                    val parser = Xml.newPullParser()
                    parser.setInput(input, "UTF-8")
                    check(parser.nextTag() == XmlPullParser.START_TAG && parser.name == "map") {
                        "Invalid legacy preferences"
                    }
                    var closed = false
                    while (parser.next() != XmlPullParser.END_DOCUMENT) {
                        if (parser.eventType == XmlPullParser.END_TAG && parser.depth == 1 && parser.name == "map") closed = true
                    }
                    check(closed) { "Truncated legacy preferences" }
                }
            }
        }
        fun read(key: String): String? = if (encrypted) {
            secure.getString(key, null)?.let { cipher.decrypt(key, it) }
        } else legacy.getString(key, null)
        val state = JSONObject(read("state") ?: "{}")
        for (key in NativeJsonStore.partNames) {
            read("state_part_$key")?.let {
                state.put(key, if (key == "savingsFunds") JSONObject(it) else JSONArray(it))
            }
        }
        return state
    }

    fun finishMigration() {
        // Prevent a missing database from being mistaken for a new installation.
        check(legacy.edit().putBoolean(SQLITE_MARKER, true).commit()) { "Cannot mark SQLite migration" }
        val plain = legacy.edit().remove("state").remove("state_split_v1")
            .putLong("secure_cleanup", System.nanoTime())
        val sealed = secure.edit().remove("state").remove("_legacyClean")
            .putLong("sqlite_cleanup", System.nanoTime())
        NativeJsonStore.partNames.forEach {
            plain.remove("state_part_$it")
            sealed.remove("state_part_$it")
        }
        // A failed preferences commit can update its memory cache. A changing nonce
        // forces a disk write on retry before SQLite marks cleanup complete.
        check(plain.commit()) { "Cannot remove legacy plaintext" }
        check(sealed.commit()) { "Cannot remove legacy encrypted records" }
    }

    companion object {
        const val STORE_NAME = "sin_rial_secure_v1"
        const val SQLITE_MARKER = "sqlite_state_v1"
    }
}
