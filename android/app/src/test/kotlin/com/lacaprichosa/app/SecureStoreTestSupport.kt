package com.lacaprichosa.app

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import javax.crypto.spec.SecretKeySpec

// Host tests exercise real AES/GCM with a test key; production only uses Android Keystore.
internal fun installTestCipher() {
    val key = SecretKeySpec(ByteArray(32) { (it + 1).toByte() }, "AES")
    NativeJsonStore.cipher = StateCipher { key }
}

internal fun sqlitePayloads(context: Context): Map<String, List<String>> =
    SQLiteDatabase.openDatabase(context.getDatabasePath(SqliteStateStore.DATABASE_NAME).path, null,
        SQLiteDatabase.OPEN_READONLY).use { db ->
        (listOf("store_meta") + NativeJsonStore.partNames).associateWith { table ->
            db.rawQuery("SELECT payload FROM $table ORDER BY payload", null).use { cursor ->
                buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
            }
        }
    }
