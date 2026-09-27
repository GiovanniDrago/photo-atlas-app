package dev.giovannidrago.photoatlas.studio.data.remote

import dev.giovannidrago.photoatlas.studio.data.local.ApiBaseUrlProvider
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response

/**
 * Typed client for photo-atlas-api. The base URL is read from the settings on
 * every call because the phone hotspot changes the VM address.
 */
@Singleton
class PhotoAtlasClient @Inject constructor(
	private val settings: ApiBaseUrlProvider,
	@Named("api") private val client: OkHttpClient,
	private val json: Json,
) {
	suspend fun health(timeoutMs: Long = 2000): Boolean = runCatching {
		val body = execute("GET", "/health", timeoutMs = timeoutMs)
		json.decodeFromString<HealthResponse>(body).status == "ok"
	}.getOrDefault(false)

	suspend fun config(): ApiConfigDto =
		json.decodeFromString(execute("GET", "/api/config"))

	suspend fun me(): AuthUserDto =
		json.decodeFromString<MeResponse>(execute("GET", "/api/auth/me")).user

	suspend fun mfaSync(): AuthUserDto =
		json.decodeFromString<MeResponse>(execute("POST", "/api/auth/mfa/sync", EmptyBody)).user

	suspend fun recoveryCodeCounts(): RecoveryCodeCountsResponse =
		json.decodeFromString(execute("GET", "/api/auth/recovery-codes"))

	suspend fun regenerateRecoveryCodes(kind: String? = null): List<String> {
		val body = execute("POST", "/api/auth/recovery-codes", json.encodeBody(RegenerateCodesBody(kind)))
		return json.decodeFromString<RecoveryCodesResponse>(body).recoveryCodes
	}

	suspend fun resetPasswordWithCode(
		identifier: String,
		recoveryCode: String,
		newPassword: String,
	) {
		execute(
			"POST",
			"/api/auth/password/reset-with-code",
			json.encodeBody(ResetPasswordBody(identifier, recoveryCode, newPassword)),
		)
	}

	suspend fun resetMfaWithCode(identifier: String, recoveryCode: String) {
		execute("POST", "/api/auth/mfa/recovery", json.encodeBody(ResetMfaBody(identifier, recoveryCode)))
	}

	private suspend fun execute(
		method: String,
		path: String,
		body: RequestBody? = null,
		timeoutMs: Long? = null,
	): String {
		val baseUrl = settings.currentApiBaseUrl()
		val request = Request.Builder()
			.url("$baseUrl$path")
			.method(method, if (method == "GET") null else (body ?: EmptyBody))
			.build()
		val http = if (timeoutMs == null) {
			client
		} else {
			client.newBuilder().callTimeout(timeoutMs, TimeUnit.MILLISECONDS).build()
		}
		val response = try {
			withContext(Dispatchers.IO) { http.newCall(request).execute() }
		} catch (error: Exception) {
			throw ConnectionException(error.message ?: "network error", error)
		}
		return response.readBody()
	}
}

private fun Response.readBody(): String {
	use { response ->
		val text = response.body?.string().orEmpty()
		val fallback = "HTTP ${response.code}"
		if (response.code == 403 && errorMessage(text, "") == "mfa_required") {
			throw MfaRequiredException()
		}
		if (response.code == 401) throw SessionExpiredException()
		if (!response.isSuccessful) throw ApiException(response.code, errorMessage(text, fallback))
		return text
	}
}
