package dev.giovannidrago.photoatlas.studio.data.security

/**
 * Small encrypted key/value store. The Android implementation keeps the AES key
 * in the Keystore and only the ciphertext on disk (same approach as the other
 * native apps in this workspace).
 */
interface SecureStorage {
	fun read(key: String): String?

	fun write(key: String, value: String)

	fun clear(key: String)
}

/** Used by tests and as a fallback when the Keystore is unavailable. */
class InMemorySecureStorage : SecureStorage {
	private val values = mutableMapOf<String, String>()

	override fun read(key: String): String? = values[key]

	override fun write(key: String, value: String) {
		values[key] = value
	}

	override fun clear(key: String) {
		values.remove(key)
	}
}
