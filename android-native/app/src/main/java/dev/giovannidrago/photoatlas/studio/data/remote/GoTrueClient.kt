package dev.giovannidrago.photoatlas.studio.data.remote

import dev.giovannidrago.photoatlas.studio.data.auth.TokenProvider
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
 * Direct Supabase GoTrue client (the app never sends credentials to our API).
 * Requests carry the publishable key as `apikey` and the current access token
 * as `Authorization` when a session exists.
 */
@Singleton
class GoTrueClient @Inject constructor(
	private val supabase: SupabaseConfigStore,
	private val tokens: TokenProvider,
	@Named("plain") private val client: OkHttpClient,
	private val json: Json,
) {
	suspend fun signUp(
		email: String,
		password: String,
		displayName: String?,
		redirectTo: String?,
	): GoTrueSessionDto {
		val query = redirectTo?.takeIf { it.isNotBlank() }?.let { "redirect_to=${encode(it)}" }
		return json.decodeFromString(
			execute(
				"POST",
				"/signup",
				json.encodeBody(
					SignupBody(
						email = email,
						password = password,
						data = displayName?.takeIf { it.isNotBlank() }?.let { SignupMetadata(it) },
					),
				),
				query = query,
			),
		)
	}

	suspend fun signInWithPassword(email: String, password: String): GoTrueSessionDto =
		json.decodeFromString(
			execute("POST", "/token", json.encodeBody(PasswordGrantBody(email, password)), query = "grant_type=password"),
		)

	suspend fun resendSignup(email: String) {
		execute("POST", "/resend", json.encodeBody(ResendBody("signup", email)))
	}

	suspend fun user(): GoTrueUserDto = json.decodeFromString(execute("GET", "/user"))

	suspend fun updatePassword(password: String, currentPassword: String): GoTrueUserDto =
		json.decodeFromString(
			execute("PUT", "/user", json.encodeBody(UpdateUserBody(password, currentPassword))),
		)

	suspend fun enrollTotp(friendlyName: String): EnrollResponseDto =
		json.decodeFromString(execute("POST", "/factors", json.encodeBody(EnrollFactorBody("totp", friendlyName))))

	suspend fun challenge(factorId: String): ChallengeResponseDto =
		json.decodeFromString(execute("POST", "/factors/$factorId/challenge", EmptyBody))

	suspend fun verifyFactor(factorId: String, challengeId: String, code: String): GoTrueSessionDto =
		json.decodeFromString(
			execute("POST", "/factors/$factorId/verify", json.encodeBody(VerifyFactorBody(challengeId, code))),
		)

	suspend fun unenroll(factorId: String) {
		execute("DELETE", "/factors/$factorId")
	}

	suspend fun logout(scope: String) {
		execute("POST", "/logout", EmptyBody, query = "scope=$scope")
	}

	private fun encode(value: String): String = java.net.URLEncoder.encode(value, "UTF-8")

	private suspend fun execute(
		method: String,
		path: String,
		body: RequestBody? = null,
		query: String? = null,
	): String {
		val config = supabase.config.value
			?: throw ApiException(0, "Supabase configuration missing (/api/config)")
		val url = buildString {
			append(config.supabaseUrl.trimEnd('/'))
			append("/auth/v1")
			append(path)
			if (query != null) append('?').append(query)
		}
		val token = tokens.currentToken()
		val request = Request.Builder()
			.url(url)
			.header("apikey", config.supabasePublishableKey)
			.header("Authorization", "Bearer ${token ?: config.supabasePublishableKey}")
			.method(method, if (method == "GET") null else (body ?: EmptyBody))
			.build()
		val response = try {
			withContext(Dispatchers.IO) {
				client.newBuilder().callTimeout(30, TimeUnit.SECONDS).build().newCall(request).execute()
			}
		} catch (error: Exception) {
			throw ConnectionException(error.message ?: "network error", error)
		}
		return response.readGoTrueBody()
	}
}

private fun Response.readGoTrueBody(): String {
	use { response ->
		val text = response.body?.string().orEmpty()
		if (!response.isSuccessful) {
			throw ApiException(response.code, errorMessage(text, "HTTP ${response.code}"))
		}
		return text
	}
}
