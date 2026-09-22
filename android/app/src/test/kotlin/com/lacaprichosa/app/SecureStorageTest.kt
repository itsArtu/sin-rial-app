package com.lacaprichosa.app

import android.app.Application
import android.content.Context
import android.provider.Settings
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.security.MessageDigest
import javax.crypto.spec.SecretKeySpec

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class)
class SecureStorageTest {
    private val context get() = RuntimeEnvironment.getApplication()
    private val secure get() = context.getSharedPreferences(StateVault.STORE_NAME, Context.MODE_PRIVATE)
    @Before fun setup() { installTestCipher() }
    private fun oldPin(pin: String): JSONObject = JSONObject()
        .put("pinEnabled", true).put("pinLength", pin.length).put("pinSalt", "legacy-salt")
        .put("pinHash", MessageDigest.getInstance("SHA-256").digest("legacy-salt:$pin".toByteArray())
            .joinToString("") { "%02x".format(it.toInt() and 255) })
        .put("securitySetupComplete", true).put("onboardingComplete", true)

    @Test fun migrationPreservesSplitAndInlineCollectionsAndDeletesPlaintext() {
        val legacy = NativeJsonStore.prefs(context)
        legacy.edit().putString("state", """{"userName":"Arturo","accounts":[{"id":"cash","balance":42.07}],"debts":[{"amount":12}]}""")
            .putString("state_part_movements", """[{"id":"m","description":"Private purchase"}]""")
            .putString("state_part_savingsFunds", """{"couple":[]}""")
            .putBoolean("daily_reminder_enabled", true).commit()
        val migrated = NativeJsonStore.readState(context)
        assertEquals(42.07, migrated.getJSONArray("accounts").getJSONObject(0).getDouble("balance"), 0.0)
        assertEquals("Private purchase", migrated.getJSONArray("movements").getJSONObject(0).getString("description"))
        assertEquals(12, migrated.getJSONArray("debts").getJSONObject(0).getInt("amount"))
        assertFalse(legacy.contains("state"))
        assertFalse(legacy.contains("state_part_movements"))
        assertTrue(legacy.getBoolean("daily_reminder_enabled", false))
        assertFalse(secure.all.toString().contains("Private purchase"))
        assertFalse(secure.all.toString().contains("Arturo"))
        NativeJsonStore.writeSplitState(context, """{"userName":"Changed"}""", emptyMap())
        assertEquals(42.07, NativeJsonStore.readState(context).getJSONArray("accounts").getJSONObject(0).getDouble("balance"), 0.0)
    }

    @Test fun malformedLegacyDataStopsMigrationWithoutDeletion() {
        NativeJsonStore.prefs(context).edit().putString("state", "not json").commit()
        assertThrows(Exception::class.java) { NativeJsonStore.readState(context) }
        assertEquals("not json", NativeJsonStore.prefs(context).getString("state", ""))
        assertTrue(secure.all.isEmpty())
    }

    @Test fun damagedEncryptedPreferencesCannotBecomeANewInstallation() {
        val file = java.io.File(context.applicationInfo.dataDir, "shared_prefs/${StateVault.STORE_NAME}.xml")
        file.parentFile!!.mkdirs()
        file.writeText("<map><string name=\"state\">")
        assertThrows(Exception::class.java) { NativeJsonStore.readState(context) }
        assertEquals("<map><string name=\"state\">", file.readText())
    }

    @Test fun missingKeyNeverFallsBackToEmptyDataOrOverwritesCiphertext() {
        NativeJsonStore.writeState(context, """{"userName":"Original"}""")
        val snapshot = sqlitePayloads(context)
        NativeJsonStore.cipher = StateCipher { throw IllegalStateException("key lost") }
        assertThrows(Exception::class.java) { NativeJsonStore.readState(context) }
        assertThrows(Exception::class.java) { NativeJsonStore.writeState(context, "{}") }
        assertEquals(snapshot, sqlitePayloads(context))
    }

    @Test fun authenticatedEncryptionRejectsWrongKeyTamperingAndSwappedRecords() {
        val cipher = NativeJsonStore.cipher
        val a = cipher.encrypt("state", "{\"private\":42}")
        val b = cipher.encrypt("state", "{\"private\":42}")
        assertNotEquals(a, b)
        assertEquals("{\"private\":42}", cipher.decrypt("state", a))
        assertThrows(Exception::class.java) { cipher.decrypt("state_part_accounts", a) }
        val wrongKey = StateCipher { SecretKeySpec(ByteArray(32) { 9 }, "AES") }
        assertThrows(Exception::class.java) { wrongKey.decrypt("state", a) }
        val index = a.length - 8
        val damaged = a.substring(0, index) + (if (a[index] == 'A') 'B' else 'A') + a.substring(index + 1)
        assertThrows(Exception::class.java) { cipher.decrypt("state", damaged) }
    }

    @Test fun existingPinIsUpgradedOnlyAfterSuccessfulVerification() {
        NativeJsonStore.prefs(context).edit().putString("state", oldPin("1234").toString()).commit()
        assertEquals(false, PinSecurity.verify(context, "0000")["accepted"])
        assertFalse(NativeJsonStore.readState(context).has("pinKdf"))
        assertEquals(true, PinSecurity.verify(context, "1234")["accepted"])
        val state = NativeJsonStore.readState(context)
        assertEquals("PBKDF2WithHmacSHA256", state.getString("pinKdf"))
        assertEquals(600_000, state.getInt("pinIterations"))
        assertEquals(0, state.getInt("pinFailures"))
        assertEquals(true, PinSecurity.verify(context, "1234")["accepted"])
    }

    @Test fun retryLimitPersistsAndStaleWritesCannotResetItOrTheVerifier() {
        Settings.Global.putInt(context.contentResolver, Settings.Global.BOOT_COUNT, 3)
        val old = oldPin("654321")
        NativeJsonStore.writeState(context, old.toString())
        repeat(4) { assertEquals(0L, PinSecurity.verify(context, "000000")["retryMillis"]) }
        assertTrue((PinSecurity.verify(context, "000000")["retryMillis"] as Long) > 0)
        NativeJsonStore.writeState(context, old.toString())
        assertEquals(5, NativeJsonStore.readState(context).getInt("pinFailures"))
        assertEquals(false, PinSecurity.verify(context, "654321")["accepted"])
        // Advancing wall time alone cannot bypass a timeout in the same boot.
        NativeJsonStore.updateMain(context) { it.put("pinRetryWall", 0L) }
        assertTrue((PinSecurity.verify(context, "654321")["retryMillis"] as Long) > 0)
        NativeJsonStore.updateMain(context) { it.put("pinRetryElapsed", 0L) }
        assertEquals(true, PinSecurity.verify(context, "654321")["accepted"])
        NativeJsonStore.writeState(context, old.toString())
        assertEquals("PBKDF2WithHmacSHA256", NativeJsonStore.readState(context).getString("pinKdf"))
    }

    @Test fun newPinsUseIndependentSaltsAndRejectNonDigits() {
        val first = PinSecurity.configure(context, "123456", true)
        val second = PinSecurity.configure(context, "123456", true)
        assertNotEquals(first["pinSalt"], second["pinSalt"])
        assertNotEquals(first["pinHash"], second["pinHash"])
        assertEquals(true, PinSecurity.verify(context, "123456")["accepted"])
        assertThrows(Exception::class.java) { PinSecurity.configure(context, "abcd", false) }
    }

    @Test @Config(sdk = [24]) fun androidSevenUsesSupportedKdf() {
        assertEquals("PBKDF2WithHmacSHA1", PinSecurity.configure(context, "1234", false)["pinKdf"])
        assertEquals(true, PinSecurity.verify(context, "1234")["accepted"])
    }
}
