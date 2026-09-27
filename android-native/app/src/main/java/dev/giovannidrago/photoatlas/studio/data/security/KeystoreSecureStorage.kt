package dev.giovannidrago.photoatlas.studio.data.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * AES-256-GCM ciphertext in a private SharedPreferences file, with the key in
 * the Android Keystore. When the Keystore is unavailable the data stays in
 * memory for the session instead of being written in the clear.
 */
class KeystoreSecureStorage(context: Context) : SecureStorage {
	private val delegate: SecureStorage = runCatching {
		KeystoreBacked(context)
	}.getOrElse { error ->
		Log.e(TAG, "Android Keystore unavailable, keeping secure data in memory", error)
		InMemorySecureStorage()
	}

	override fun read(key: String): String? = delegate.read(key)

	override fun write(key: String, value: String) = delegate.write(key, value)

	override fun clear(key: String) = delegate.clear(key)

	private companion object {
		const val TAG = "KeystoreSecureStorage"
	}
}

private class KeystoreBacked(context: Context) : SecureStorage {
	private val preferences =
		context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
	private val secretKey = getOrCreateSecretKey()

	override fun read(key: String): String? {
		val stored = preferences.getString(key, null) ?: return null
		return runCatching {
			decrypt(stored)
		}.getOrElse {
			// A ciphertext the Keystore key can no longer unwrap is dead weight.
			clear(key)
			null
		}
	}

	override fun write(key: String, value: String) {
		preferences.edit().putString(key, encrypt(value)).apply()
	}

	override fun clear(key: String) {
		preferences.edit().remove(key).apply()
	}

	private fun encrypt(value: String): String {
		val cipher = Cipher.getInstance(TRANSFORMATION)
		cipher.init(Cipher.ENCRYPT_MODE, secretKey)
		val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
		return Base64.encodeToString(cipher.iv + ciphertext, Base64.NO_WRAP)
	}

	private fun decrypt(stored: String): String {
		val decoded = Base64.decode(stored, Base64.NO_WRAP)
		val iv = decoded.copyOfRange(0, GCM_IV_LENGTH_BYTES)
		val ciphertext = decoded.copyOfRange(GCM_IV_LENGTH_BYTES, decoded.size)
		val cipher = Cipher.getInstance(TRANSFORMATION)
		cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv))
		return String(cipher.doFinal(ciphertext), Charsets.UTF_8)
	}

	private fun getOrCreateSecretKey(): SecretKey {
		val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
		val existing = keyStore.getEntry(KEYSTORE_ALIAS, null) as? KeyStore.SecretKeyEntry
		if (existing != null) return existing.secretKey

		val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
		val specification = KeyGenParameterSpec.Builder(
			KEYSTORE_ALIAS,
			KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
		)
			.setBlockModes(KeyProperties.BLOCK_MODE_GCM)
			.setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
			.setKeySize(256)
			.build()
		generator.init(specification)
		return generator.generateKey()
	}

	private companion object {
		const val ANDROID_KEYSTORE = "AndroidKeyStore"
		const val KEYSTORE_ALIAS = "photoatlas_studio_secure"
		const val TRANSFORMATION = "AES/GCM/NoPadding"
		const val GCM_TAG_LENGTH_BITS = 128
		const val GCM_IV_LENGTH_BYTES = 12
		const val PREFERENCES_NAME = "photoatlas_studio_secure_prefs"
	}
}
