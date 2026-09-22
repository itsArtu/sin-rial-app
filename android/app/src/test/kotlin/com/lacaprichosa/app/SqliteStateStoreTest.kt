package com.lacaprichosa.app

import android.app.Application
import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class)
class SqliteStateStoreTest {
    private val context get() = RuntimeEnvironment.getApplication()
    private val legacy get() = NativeJsonStore.prefs(context)
    private val secure get() = context.getSharedPreferences(StateVault.STORE_NAME, Context.MODE_PRIVATE)
    @Before fun setup() { installTestCipher() }

    private fun fixture() = JSONObject("""{
        "userName":"Private Arturo", "userBirthDate":"1995-04-21", "rate":852.4158,
        "nativeSecurityV1":true, "pinEnabled":true, "pinSalt":"private-salt", "pinHash":"private-hash",
        "pinFailures":4, "onboardingComplete":true, "unknownFutureSetting":{"keep":true},
        "accounts":[{"id":"a","balance":-2.15,"currency":"USD"},{"id":"b","balance":12345.67,"currency":"VES"}],
        "movements":[{"id":"m1","accountId":"a","amount":12.34,"description":"Private purchase"},
                     {"id":"m2","accountId":"b","amount":1200.01,"debtId":"d"}],
        "debts":[{"id":"d","amount":100,"paidAmount":5,"currency":"EUR"}],
        "budgets":[{"id":"limit","planId":"plan","amount":30,"category":"Transport"}],
        "budgetPlans":[{"id":"plan","periodType":"biweekly","startDate":"2026-09-16","salary":70}],
        "goals":[{"id":"g","target":900,"history":[{"amount":2.01}]}],
        "cards":[{"id":"c","limit":100,"balance":4.01}],
        "balanceAdjustments":[{"id":"adjust","accountId":"a","amount":-0.15}],
        "savingsFunds":{"Emergency":{"target":500,"history":[{"amount":2.5}]}},
        "sharedSavings":[{"id":"couple","members":[{"name":"Private partner"}],"history":[{"amountUsd":12}]}],
        "savingsCircles":[{"id":"san","members":[{"id":"p1"},{"id":"p2"}],"quota":5,"history":[]}]
    }""")

    private fun assertState(expected: JSONObject, actual: JSONObject) =
        assertEquals(SqliteStateStore.canonical(expected), SqliteStateStore.canonical(actual))

    private fun <T> sql(block: (SQLiteDatabase) -> T): T = SQLiteDatabase.openDatabase(
        context.getDatabasePath(SqliteStateStore.DATABASE_NAME).path, null, SQLiteDatabase.OPEN_READWRITE).use(block)

    private fun count(table: String): Int = sql { db ->
        db.rawQuery("SELECT COUNT(*) FROM $table", null).use { it.moveToFirst(); it.getInt(0) }
    }

    @Test fun plaintextMigrationKeepsEveryFieldAndCollectionAndUsesSeparateTables() {
        val source = fixture()
        legacy.edit().putString("state", source.toString()).putLong("daily_reminder_next_millis", 1234).commit()
        assertState(source, NativeJsonStore.readState(context))
        assertState(source, NativeJsonStore.readState(context))
        for (name in NativeJsonStore.partNames) {
            assertEquals(if (name == "savingsFunds") source.getJSONObject(name).length() else source.getJSONArray(name).length(), count(name))
        }
        assertFalse(legacy.contains("state"))
        assertTrue(legacy.getBoolean(StateVault.SQLITE_MARKER, false))
        assertEquals(1234L, legacy.getLong("daily_reminder_next_millis", 0))
        assertNoPlaintext()
    }

    @Test fun encryptedSplitMigrationTakesPrecedenceAndPreservesSecurityFields() {
        val expected = fixture()
        val main = JSONObject(expected.toString())
        val editor = secure.edit()
        for (name in NativeJsonStore.partNames) {
            if (name in setOf("budgetPlans", "sharedSavings", "savingsCircles")) continue
            val key = "state_part_$name"
            editor.putString(key, NativeJsonStore.cipher.encrypt(key, requireNotNull(main.remove(name)).toString()))
        }
        editor.putString("state", NativeJsonStore.cipher.encrypt("state", main.toString()))
            .putString("_legacyClean", NativeJsonStore.cipher.encrypt("_legacyClean", "{}")).commit()
        legacy.edit().putString("state", """{"userName":"Obsolete"}""").commit()
        assertState(expected, NativeJsonStore.readState(context))
        assertFalse(secure.contains("state"))
        assertFalse(secure.contains("state_part_movements"))
        assertEquals(4, NativeJsonStore.readMain(context).getInt("pinFailures"))
        assertNoPlaintext()
    }

    @Test fun failedImportRollsBackAllRowsKeepsSourceAndCanRetry() {
        legacy.edit().putString("state", "invalid").commit()
        assertThrows(Exception::class.java) { NativeJsonStore.readState(context) }
        assertEquals(0, count("store_meta"))
        sql { it.execSQL("CREATE TRIGGER fail_import BEFORE INSERT ON movements BEGIN SELECT RAISE(ABORT, 'simulated disk failure'); END") }
        val source = fixture()
        legacy.edit().putString("state", source.toString()).commit()
        assertThrows(Exception::class.java) { NativeJsonStore.readState(context) }
        assertEquals(source.toString(), legacy.getString("state", null))
        assertEquals(0, count("accounts"))
        assertEquals(0, count("store_meta"))
        assertFalse(legacy.contains(StateVault.SQLITE_MARKER))
        sql { it.execSQL("DROP TRIGGER fail_import") }
        assertState(source, NativeJsonStore.readState(context))
    }

    @Test fun failedCleanupIsRetriedWithoutReimportingOrDuplicatingData() {
        val source = fixture()
        legacy.edit().putString("state", source.toString()).commit()
        var fail = true
        val failingContext = object : ContextWrapper(context) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
                val prefs = super.getSharedPreferences(name, mode)
                if (name != StateVault.STORE_NAME) return prefs
                return object : SharedPreferences by prefs {
                    override fun edit(): SharedPreferences.Editor {
                        val delegate = prefs.edit()
                        return object : SharedPreferences.Editor by delegate {
                            override fun remove(key: String): SharedPreferences.Editor { delegate.remove(key); return this }
                            override fun putLong(key: String, value: Long): SharedPreferences.Editor { delegate.putLong(key, value); return this }
                            override fun commit(): Boolean {
                                if (fail) return false
                                return delegate.commit()
                            }
                        }
                    }
                }
            }
        }
        assertThrows(Exception::class.java) { NativeJsonStore.readState(failingContext) }
        assertEquals(2, count("movements"))
        // The verified SQLite transaction is authoritative even after plaintext cleanup.
        assertFalse(legacy.contains("state"))
        fail = false
        assertState(source, NativeJsonStore.readState(failingContext))
        assertState(source, NativeJsonStore.readState(context))
        assertEquals(2, count("movements"))
    }

    @Test fun interruptionAfterImportCommitResumesVerificationBeforeCleanup() {
        val source = fixture()
        legacy.edit().putString("state", source.toString()).commit()
        var reads = 0
        val interrupted = object : ContextWrapper(context) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
                val prefs = super.getSharedPreferences(name, mode)
                if (name != NativeJsonStore.STORE_NAME) return prefs
                return object : SharedPreferences by prefs {
                    override fun getString(key: String, default: String?): String? {
                        if (key == "state" && ++reads == 2) error("Simulated interruption")
                        return prefs.getString(key, default)
                    }
                }
            }
        }
        assertThrows(Exception::class.java) { NativeJsonStore.readState(interrupted) }
        assertEquals(2, count("movements"))
        assertEquals(source.toString(), legacy.getString("state", null))
        assertFalse(legacy.contains(StateVault.SQLITE_MARKER))
        assertState(source, NativeJsonStore.readState(context))
        assertEquals(2, count("movements"))
        assertFalse(legacy.contains("state"))
    }

    @Test fun malformedPlaintextXmlCannotBecomeAnEmptyDatabase() {
        val file = java.io.File(context.applicationInfo.dataDir, "shared_prefs/${NativeJsonStore.STORE_NAME}.xml")
        file.parentFile!!.mkdirs()
        val broken = "<map><string name=\"state\">"
        file.writeText(broken)
        assertThrows(Exception::class.java) { NativeJsonStore.readState(context) }
        assertEquals(broken, file.readText())
        assertEquals(0, count("store_meta"))
    }

    @Test fun freshInstallationCreatesOneEmptyDatabaseAndCanReopenIt() {
        assertEquals(0, NativeJsonStore.readState(context).length())
        assertEquals(0, NativeJsonStore.readState(context).length())
        assertEquals(1, count("store_meta"))
        assertTrue(legacy.getBoolean(StateVault.SQLITE_MARKER, false))
        assertFalse(legacy.contains("state"))
    }

    @Test fun encryptedSourceWithBadKeyIsNotDeletedOrReplaced() {
        val sealed = NativeJsonStore.cipher.encrypt("state", fixture().toString())
        secure.edit().putString("state", sealed).commit()
        NativeJsonStore.cipher = StateCipher { throw IllegalStateException("unavailable") }
        assertThrows(Exception::class.java) { NativeJsonStore.readState(context) }
        assertEquals(sealed, secure.getString("state", null))
        assertEquals(0, count("store_meta"))
        installTestCipher()
        assertState(fixture(), NativeJsonStore.readState(context))
    }

    @Test fun accountAndMovementWriteIsAtomicWhenOneSqlStatementFails() {
        NativeJsonStore.writeState(context, fixture().toString())
        val before = sqlitePayloads(context)
        val changed = fixture()
        changed.getJSONArray("accounts").getJSONObject(0).put("balance", 10)
        changed.getJSONArray("movements").getJSONObject(0).put("amount", 7)
        sql { it.execSQL("CREATE TRIGGER fail_update BEFORE UPDATE ON movements BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END") }
        assertThrows(Exception::class.java) { NativeJsonStore.writeState(context, changed.toString()) }
        assertEquals(before, sqlitePayloads(context))
        assertState(fixture(), NativeJsonStore.readState(context))
        sql { it.execSQL("DROP TRIGGER fail_update") }
        NativeJsonStore.writeState(context, changed.toString())
        assertState(changed, NativeJsonStore.readState(context))
    }

    @Test fun reorderAppendEditDeleteAndUndoOnlyRewriteChangedPayloads() {
        NativeJsonStore.writeState(context, fixture().toString())
        val before = sqlitePayloads(context).getValue("movements")
        val source = fixture().getJSONArray("movements")
        val reversed = JSONArray().put(source.get(1)).put(source.get(0))
        NativeJsonStore.writeSplitState(context, NativeJsonStore.readMain(context).toString(), mapOf("movements" to reversed.toString()))
        assertEquals(before, sqlitePayloads(context).getValue("movements"))
        assertEquals("m2", NativeJsonStore.readState(context).getJSONArray("movements").getJSONObject(0).getString("id"))
        reversed.put(JSONObject().put("id", "m3").put("amount", 10))
        NativeJsonStore.writeSplitState(context, NativeJsonStore.readMain(context).toString(), mapOf("movements" to reversed.toString()))
        assertTrue(sqlitePayloads(context).getValue("movements").containsAll(before))
        reversed.getJSONObject(0).put("amount", 11)
        NativeJsonStore.writeSplitState(context, NativeJsonStore.readMain(context).toString(), mapOf("movements" to reversed.toString()))
        assertEquals(1, before.intersect(sqlitePayloads(context).getValue("movements").toSet()).size)
        NativeJsonStore.writeSplitState(context, NativeJsonStore.readMain(context).toString(), mapOf("movements" to "[]"))
        assertEquals(0, count("movements"))
        NativeJsonStore.writeState(context, fixture().toString())
        assertState(fixture(), NativeJsonStore.readState(context))
    }

    @Test fun omittedPartsStayIntactAndInvalidOrUnknownPartsCannotEraseData() {
        NativeJsonStore.writeState(context, fixture().toString())
        val before = sqlitePayloads(context)
        assertThrows(Exception::class.java) { NativeJsonStore.writeSplitState(context, "{}", mapOf("movements" to "{}")) }
        assertThrows(Exception::class.java) { NativeJsonStore.writeState(context, """{"accounts":null}""") }
        assertThrows(Exception::class.java) { NativeJsonStore.writeSplitState(context, "{}", mapOf("unexpected" to "[]")) }
        assertEquals(before, sqlitePayloads(context))
        NativeJsonStore.writeSplitState(context, NativeJsonStore.readMain(context).put("themeColor", "blue").toString(), emptyMap())
        for (name in NativeJsonStore.partNames) assertEquals(before[name], sqlitePayloads(context)[name])
    }

    @Test fun backgroundRatesSurviveStaleFlutterSnapshotWithoutTouchingCollections() {
        val source = fixture().put("rateLastAttemptMillis", 1)
        NativeJsonStore.writeState(context, source.toString())
        val before = sqlitePayloads(context)
        NativeJsonStore.updateRateFields(context, JSONObject().put("rateLastAttemptMillis", 100).put("rate", 950.25))
        NativeJsonStore.writeState(context, source.toString())
        assertEquals(950.25, NativeJsonStore.readMain(context).getDouble("rate"), 0.0)
        for (name in NativeJsonStore.partNames) assertEquals(before[name], sqlitePayloads(context)[name])
    }

    @Test fun rowDeletionIsDetectedAndCannotBeSilentlyRepairedBySave() {
        NativeJsonStore.writeState(context, fixture().toString())
        sql { it.execSQL("DELETE FROM accounts WHERE position = 0") }
        assertThrows(Exception::class.java) { NativeJsonStore.readState(context) }
        assertThrows(Exception::class.java) { NativeJsonStore.writeState(context, fixture().toString()) }
        assertEquals(1, count("accounts"))
    }

    @Test fun alteredCiphertextFailsClosedWithoutOverwritingDatabase() {
        NativeJsonStore.writeState(context, fixture().toString())
        sql { it.execSQL("UPDATE movements SET payload = 'v1:tampered' WHERE position = 0") }
        val damaged = sqlitePayloads(context)
        assertThrows(Exception::class.java) { NativeJsonStore.readState(context) }
        assertThrows(Exception::class.java) { NativeJsonStore.writeState(context, "{}") }
        assertEquals(damaged, sqlitePayloads(context))
    }

    @Test fun missingDatabaseAfterMigrationDoesNotRestartOnboarding() {
        NativeJsonStore.writeState(context, fixture().toString())
        assertTrue(context.deleteDatabase(SqliteStateStore.DATABASE_NAME))
        assertThrows(Exception::class.java) { NativeJsonStore.readState(context) }
        assertFalse(context.getDatabasePath(SqliteStateStore.DATABASE_NAME).exists())
    }

    @Test fun corruptDatabaseIsRetainedInsteadOfAndroidDeletingAndRecreatingIt() {
        NativeJsonStore.writeState(context, fixture().toString())
        val file = context.getDatabasePath(SqliteStateStore.DATABASE_NAME)
        val damaged = ByteArray(4096) { 42 }
        file.writeBytes(damaged)
        assertThrows(Exception::class.java) { NativeJsonStore.readState(context) }
        assertArrayEquals(damaged, file.readBytes())
    }

    @Test fun futureSchemaIsNotDestructivelyDowngraded() {
        NativeJsonStore.writeState(context, fixture().toString())
        val before = sqlitePayloads(context)
        sql { it.version = 2 }
        assertThrows(Exception::class.java) { NativeJsonStore.readState(context) }
        assertEquals(before, sqlitePayloads(context))
    }

    @Test fun settingsAndReminderReadsDoNotLoadMovementHistory() {
        NativeJsonStore.writeState(context, fixture().toString())
        sql { it.execSQL("UPDATE movements SET payload = 'unreadable' WHERE position = 0") }
        val main = NativeJsonStore.readMain(context)
        assertEquals(852.4158, main.getDouble("rate"), 0.0)
        assertFalse(main.has("movements"))
        val reminder = NativeJsonStore.readState(context, setOf("debts"))
        assertTrue(reminder.has("debts"))
        assertFalse(reminder.has("accounts"))
        assertFalse(reminder.has("movements"))
        assertThrows(Exception::class.java) { NativeJsonStore.readState(context) }
    }

    @Test fun concurrentNativeUpdatesDoNotLoseChanges() {
        NativeJsonStore.writeState(context, fixture().put("counter", 0).toString())
        val pool = Executors.newFixedThreadPool(4)
        try {
            val futures = pool.invokeAll((0 until 20).map {
                Callable { NativeJsonStore.updateMain(context) { it.put("counter", it.getInt("counter") + 1) } }
            })
            futures.forEach { it.get(20, TimeUnit.SECONDS) }
        } finally { pool.shutdownNow() }
        assertEquals(20, NativeJsonStore.readMain(context).getInt("counter"))
    }

    @Test fun missingIdsDuplicateIdsNullsAndEmptyCollectionsArePreserved() {
        val source = JSONObject("""{"accounts":[],"movements":[{"id":"same","amount":1},{"id":"same","amount":2},{"amount":3},null],"savingsFunds":{}}""")
        legacy.edit().putString("state", source.toString()).commit()
        assertState(source, NativeJsonStore.readState(context))
        NativeJsonStore.writeSplitState(context, "{}", mapOf("movements" to source.getJSONArray("movements").toString()))
        assertState(source, NativeJsonStore.readState(context))
    }

    @Test fun largeLedgerSurvivesReopenAndSingleRecordChange() {
        val source = fixture()
        val movements = JSONArray()
        repeat(2500) { movements.put(JSONObject().put("id", "entry-$it").put("amount", it / 100.0).put("description", "Private purchase $it")) }
        source.put("movements", movements)
        legacy.edit().putString("state", source.toString()).commit()
        assertState(source, NativeJsonStore.readState(context))
        val before = sqlitePayloads(context).getValue("movements")
        movements.getJSONObject(1200).put("amount", 12.99)
        NativeJsonStore.writeSplitState(context, NativeJsonStore.readMain(context).toString(), mapOf("movements" to movements.toString()))
        assertState(source, NativeJsonStore.readState(context))
        assertEquals(2499, before.intersect(sqlitePayloads(context).getValue("movements").toSet()).size)
    }

    @Test @Config(sdk = [24]) fun sqliteStoreWorksOnAndroidSeven() {
        legacy.edit().putString("state", fixture().toString()).commit()
        assertState(fixture(), NativeJsonStore.readState(context))
    }

    private fun assertNoPlaintext() {
        val payloads = sqlitePayloads(context).toString()
        for (secret in listOf("Private Arturo", "Private purchase", "private-hash", "Private partner", "12345.67")) {
            assertFalse(payloads.contains(secret))
            val directory = context.getDatabasePath(SqliteStateStore.DATABASE_NAME).parentFile!!
            directory.listFiles()!!.filter { it.name.startsWith(SqliteStateStore.DATABASE_NAME) }.forEach {
                assertFalse("Plaintext in ${it.name}", it.readBytes().toString(Charsets.ISO_8859_1).contains(secret))
            }
        }
    }
}
