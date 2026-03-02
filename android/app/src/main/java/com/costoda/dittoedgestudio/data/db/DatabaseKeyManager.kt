package com.costoda.dittoedgestudio.data.db

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Manages the database encryption key using the Android Keystore.
 *
 * Strategy:
 * - A random 32-byte passphrase is generated on first run.
 * - It is encrypted with an AES-256-GCM key stored in the Android Keystore.
 * - The encrypted passphrase + IV are stored in regular SharedPreferences (safe: encrypted by Keystore).
 * - On subsequent runs, the passphrase is decrypted and returned for SQLCipher.
 */
class DatabaseKeyManager(private val context: Context) {

    private val keystoreAlias = "dittoedgestudio_db_key"
    private val prefsFile = "dittoedgestudio_db_prefs"
    private val prefsKey = "db_enc_passphrase"
    private val ivKey = "db_enc_iv"

    fun getOrCreateKey(): ByteArray {
        val prefs = context.getSharedPreferences(prefsFile, Context.MODE_PRIVATE)
        val storedPassphrase = prefs.getString(prefsKey, null)
        val storedIv = prefs.getString(ivKey, null)

        return if (storedPassphrase != null && storedIv != null) {
            val encrypted = Base64.decode(storedPassphrase, Base64.DEFAULT)
            val iv = Base64.decode(storedIv, Base64.DEFAULT)
            decryptPassphrase(encrypted, iv)
        } else {
            val passphrase = generatePassphrase()
            val (encrypted, iv) = encryptPassphrase(passphrase)
            prefs.edit()
                .putString(prefsKey, Base64.encodeToString(encrypted, Base64.DEFAULT))
                .putString(ivKey, Base64.encodeToString(iv, Base64.DEFAULT))
                .apply()
            passphrase
        }
    }

    private fun generatePassphrase(): ByteArray {
        val passphrase = ByteArray(32)
        SecureRandom().nextBytes(passphrase)
        return passphrase
    }

    private fun getOrCreateKeystoreKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        keyStore.getKey(keystoreAlias, null)?.let { return it as SecretKey }

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        keyGenerator.init(
            KeyGenParameterSpec.Builder(
                keystoreAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return keyGenerator.generateKey()
    }

    private fun encryptPassphrase(passphrase: ByteArray): Pair<ByteArray, ByteArray> {
        val key = getOrCreateKeystoreKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val encrypted = cipher.doFinal(passphrase)
        return Pair(encrypted, cipher.iv)
    }

    private fun decryptPassphrase(encrypted: ByteArray, iv: ByteArray): ByteArray {
        val key = getOrCreateKeystoreKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
        return cipher.doFinal(encrypted)
    }
}
