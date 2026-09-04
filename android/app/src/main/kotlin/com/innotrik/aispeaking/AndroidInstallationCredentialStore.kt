package com.innotrik.aispeaking

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Stores the per-installation backend credential outside Dart storage.
 *
 * The ciphertext is kept in private SharedPreferences while its AES key stays
 * in Android Keystore. This mirrors the Keychain-backed iOS implementation and
 * prevents an APK build from silently falling back to an unimplemented channel
 * method when a protected backend endpoint is first called.
 */
class AndroidInstallationCredentialStore(context: Context) {
    private val preferences =
        context.applicationContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun read(): String? {
        val encoded = preferences.getString(CREDENTIAL_KEY, null) ?: return null
        return try {
            val separator = encoded.indexOf(SEPARATOR)
            if (separator <= 0 || separator == encoded.lastIndex) {
                clear()
                return null
            }
            val iv = Base64.decode(encoded.substring(0, separator), Base64.NO_WRAP)
            val ciphertext = Base64.decode(encoded.substring(separator + 1), Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                secretKey(),
                GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv),
            )
            String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8)
        } catch (_: Exception) {
            // A Keystore key can be invalidated by an OS restore or security
            // reset. Treat it as a fresh install so the auth client registers
            // again instead of surfacing a native exception to the child.
            clear()
            null
        }
    }

    fun write(value: String): Boolean =
        try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, secretKey())
            val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
            val ciphertext = Base64.encodeToString(
                cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8)),
                Base64.NO_WRAP,
            )
            preferences.edit().putString(CREDENTIAL_KEY, "$iv$SEPARATOR$ciphertext").commit()
        } catch (_: Exception) {
            false
        }

    fun clear(): Boolean = preferences.edit().remove(CREDENTIAL_KEY).commit()

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        val existing = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
        if (existing != null) {
            return existing
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEY_STORE,
        )
        keyGenerator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return keyGenerator.generateKey()
    }

    private companion object {
        const val PREFERENCES_NAME = "homi.installation-auth.v1"
        const val CREDENTIAL_KEY = "credentials"
        const val KEY_ALIAS = "com.innotrik.aispeaking.installation-auth.v1"
        const val ANDROID_KEY_STORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val GCM_TAG_LENGTH_BITS = 128
        const val SEPARATOR = "."
    }
}
