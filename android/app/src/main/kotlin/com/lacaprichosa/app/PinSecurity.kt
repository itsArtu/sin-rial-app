package com.lacaprichosa.app

import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.util.Base64
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

internal object PinSecurity {
    val fields = listOf("nativeSecurityV1", "securitySetupComplete", "pinEnabled", "pinSalt", "pinHash",
        "pinLength", "biometricEnabled", "pinKdf", "pinIterations", "pinFailures", "pinRetryWall",
        "pinRetryElapsed", "pinRetryBoot")
    private val validPin = Regex("[0-9]{4,6}")

    fun configure(context: Context, pin: String, biometrics: Boolean): Map<String, Any> {
        require(validPin.matches(pin)) { "Invalid PIN" }
        return summary(NativeJsonStore.updateMain(context) { state ->
            setVerifier(state, pin)
            state.put("securitySetupComplete", true).put("pinEnabled", true).put("biometricEnabled", biometrics)
            resetAttempts(state)
        })
    }

    fun verify(context: Context, pin: String): Map<String, Any> {
        var accepted = false
        var retry = 0L
        val updated = NativeJsonStore.updateMain(context) { state ->
            retry = retryMillis(context, state)
            if (retry > 0) return@updateMain
            if (!validPin.matches(pin)) return@updateMain
            val hash = state.optString("pinHash")
            val salt = state.optString("pinSalt")
            if (!state.optBoolean("pinEnabled") || hash.isEmpty() || salt.isEmpty()) return@updateMain
            val kdf = state.optString("pinKdf")
            val calculated = if (kdf.isEmpty()) {
                MessageDigest.getInstance("SHA-256").digest("$salt:$pin".toByteArray(Charsets.UTF_8))
                    .joinToString("") { "%02x".format(it.toInt() and 255) }
            } else {
                require(kdf == "PBKDF2WithHmacSHA256" || kdf == "PBKDF2WithHmacSHA1")
                val iterations = state.getInt("pinIterations")
                require(iterations in 600_000..1_400_000)
                derive(pin, Base64.decode(salt, Base64.NO_WRAP), kdf, iterations)
            }
            accepted = MessageDigest.isEqual(calculated.toByteArray(Charsets.UTF_8), hash.toByteArray(Charsets.UTF_8))
            if (accepted) {
                if (kdf.isEmpty() || (kdf.endsWith("SHA1") && Build.VERSION.SDK_INT >= 26)) setVerifier(state, pin)
                resetAttempts(state)
            } else {
                val failures = (state.optInt("pinFailures") + 1).coerceAtMost(20)
                retry = if (failures < 5) 0 else (30_000L shl (failures - 5).coerceAtMost(5)).coerceAtMost(900_000L)
                state.put("nativeSecurityV1", true).put("pinFailures", failures)
                    .put("pinRetryWall", System.currentTimeMillis() + retry)
                    .put("pinRetryElapsed", SystemClock.elapsedRealtime() + retry)
                    .put("pinRetryBoot", bootCount(context))
            }
        }
        return mapOf("accepted" to accepted, "retryMillis" to retry, "security" to summary(updated))
    }

    private fun setVerifier(state: JSONObject, pin: String) {
        val salt = ByteArray(32).also { SecureRandom().nextBytes(it) }
        // Android 7 lacks the platform SHA-256 factory; upgrade it on the next unlock after an OS update.
        val kdf = if (Build.VERSION.SDK_INT >= 26) "PBKDF2WithHmacSHA256" else "PBKDF2WithHmacSHA1"
        val iterations = if (Build.VERSION.SDK_INT >= 26) 600_000 else 1_400_000
        state.put("nativeSecurityV1", true).put("pinKdf", kdf).put("pinIterations", iterations)
            .put("pinSalt", Base64.encodeToString(salt, Base64.NO_WRAP))
            .put("pinHash", derive(pin, salt, kdf, iterations)).put("pinLength", pin.length)
    }

    internal fun derive(pin: String, salt: ByteArray, kdf: String, iterations: Int): String {
        val chars = pin.toCharArray()
        val spec = PBEKeySpec(chars, salt, iterations, 256)
        return try { Base64.encodeToString(SecretKeyFactory.getInstance(kdf).generateSecret(spec).encoded, Base64.NO_WRAP) }
        finally { spec.clearPassword(); chars.fill('\u0000') }
    }

    private fun resetAttempts(state: JSONObject) {
        state.put("pinFailures", 0).put("pinRetryWall", 0L).put("pinRetryElapsed", 0L).put("pinRetryBoot", -1)
    }

    private fun bootCount(context: Context) = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)

    private fun retryMillis(context: Context, state: JSONObject): Long {
        val boot = bootCount(context)
        val remaining = if (boot >= 0 && state.optInt("pinRetryBoot", -2) == boot) {
            state.optLong("pinRetryElapsed") - SystemClock.elapsedRealtime()
        } else state.optLong("pinRetryWall") - System.currentTimeMillis()
        return remaining.coerceIn(0L, 900_000L)
    }

    private fun summary(state: JSONObject): Map<String, Any> = fields.filter { state.has(it) }.associateWith { state.get(it) }
}
