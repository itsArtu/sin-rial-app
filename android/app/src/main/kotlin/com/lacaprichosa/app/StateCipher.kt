package com.lacaprichosa.app

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class StateCipher(private val keyProvider: (Boolean) -> SecretKey = ::deviceKey) {
    internal var decryptions = 0
        private set
    private val plaintextCache = object : android.util.LruCache<String, String>(8 * 1024 * 1024) {
        override fun sizeOf(key: String, value: String) = (key.length + value.length) * 2
    }
    private var cachedKey: SecretKey? = null
    @Synchronized private fun key(create: Boolean): SecretKey = cachedKey ?: keyProvider(create).also { cachedKey = it }
    fun encrypt(name: String, value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(true))
        cipher.updateAAD(aad(name))
        return "v1:" + Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
    }

    fun decrypt(name: String, value: String): String {
        val cacheKey = "$name\u0000$value"
        plaintextCache.get(cacheKey)?.let { return it }
        require(value.startsWith("v1:")) { "Unknown storage format" }
        val bytes = Base64.decode(value.substring(3), Base64.NO_WRAP)
        require(bytes.size >= 28) { "Invalid encrypted record" }
        decryptions++
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        cipher.updateAAD(aad(name))
        return String(cipher.doFinal(bytes, 12, bytes.size - 12), Charsets.UTF_8)
            .also { plaintextCache.put(cacheKey, it) }
    }

    private fun aad(name: String) = "com.lacaprichosa.app:state:v1:$name".toByteArray(Charsets.UTF_8)

    companion object {
        private const val ALIAS = "sin_rial_state_aes_v1"
        @Synchronized private fun deviceKey(create: Boolean): SecretKey {
            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
            check(create) { "Storage key unavailable" }
            return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .setRandomizedEncryptionRequired(true)
                    .build())
            }.generateKey()
        }
    }
}
