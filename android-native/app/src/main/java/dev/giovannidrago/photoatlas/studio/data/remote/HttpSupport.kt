package dev.giovannidrago.photoatlas.studio.data.remote

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody

/** HTTP error with the status code and the best message the server sent. */
class ApiException(val statusCode: Int, message: String) : Exception(message)

/** The account has a verified TOTP factor and the token is only aal1. */
class MfaRequiredException : Exception("mfa_required")

/** The access token is missing, expired or revoked. */
class SessionExpiredException : Exception("unauthorized")

/** Raised when the app cannot even reach the configured server. */
class ConnectionException(message: String, cause: Throwable? = null) : Exception(message, cause)

val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()

val EmptyBody: RequestBody = ByteArray(0).toRequestBody(null)

inline fun <reified T> Json.encodeBody(value: T): RequestBody =
	encodeToString(value).toRequestBody(JSON_MEDIA_TYPE)

/**
 * Supabase GoTrue errors come in a few shapes: `{"msg": …}`,
 * `{"error_description": …}`, `{"error": …}` or `{"message": …}`.
 */
fun errorMessage(body: String?, fallback: String): String {
	if (body.isNullOrBlank()) return fallback
	return runCatching {
		val obj = Json.parseToJsonElement(body).jsonObject
		listOf("msg", "error_description", "message", "error")
			.firstNotNullOfOrNull { key ->
				obj[key]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }
			}
	}.getOrNull() ?: fallback
}
