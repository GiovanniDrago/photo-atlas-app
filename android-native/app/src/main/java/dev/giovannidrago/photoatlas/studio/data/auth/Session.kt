package dev.giovannidrago.photoatlas.studio.data.auth

import kotlinx.serialization.Serializable

/** Persisted Supabase session, encrypted at rest by [SessionStore]. */
@Serializable
data class Session(
	val accessToken: String,
	val refreshToken: String,
	val expiresAtEpochMs: Long,
	val userId: String,
	val email: String? = null,
	val displayName: String? = null,
) {
	fun isExpired(nowMs: Long = System.currentTimeMillis(), skewMs: Long = 60_000L): Boolean =
		expiresAtEpochMs - skewMs <= nowMs
}
