package dev.giovannidrago.photoatlas.studio.data.auth

import dev.giovannidrago.photoatlas.studio.data.remote.GoTrueSessionDto
import dev.giovannidrago.photoatlas.studio.data.security.SecureStorage
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.json.Json

@Singleton
class SessionStore @Inject constructor(
	private val storage: SecureStorage,
	private val json: Json,
) {
	fun load(): Session? {
		val raw = storage.read(Key) ?: return null
		return runCatching { json.decodeFromString<Session>(raw) }.getOrNull()
	}

	fun save(session: Session) {
		storage.write(Key, json.encodeToString(session))
	}

	fun clear() {
		storage.clear(Key)
	}

	private companion object {
		const val Key = "session"
	}
}

fun GoTrueSessionDto.toSession(nowMs: Long = System.currentTimeMillis()): Session {
	val metadataName = user?.userMetadata?.get("display_name")?.toString()?.trim('"')
	return Session(
		accessToken = accessToken,
		refreshToken = refreshToken,
		expiresAtEpochMs = nowMs + (expiresIn ?: 3600L) * 1000L,
		userId = user?.id.orEmpty(),
		email = user?.email,
		displayName = metadataName,
	)
}
