package dev.giovannidrago.photoatlas.studio.data.auth

import dev.giovannidrago.photoatlas.studio.data.remote.GoTrueSessionDto
import dev.giovannidrago.photoatlas.studio.data.remote.RefreshTokenBody
import dev.giovannidrago.photoatlas.studio.data.remote.SupabaseConfigStore
import dev.giovannidrago.photoatlas.studio.data.remote.encodeBody
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request

/** The API client and the GoTrue client need the current access token. */
interface TokenProvider {
	fun currentToken(): String?

	/** Blocking refresh used by the OkHttp authenticator (network thread). */
	fun refreshBlocking(): String?
}

/**
 * Single source of truth for the Supabase session: encrypted persistence,
 * in-memory flow for the UI and a single-flight token refresh.
 */
@Singleton
class SessionManager @Inject constructor(
	private val store: SessionStore,
	private val supabase: SupabaseConfigStore,
	private val json: Json,
	@Named("plain") private val client: OkHttpClient,
) : TokenProvider {
	private val refreshMutex = Mutex()
	private val _session = kotlinx.coroutines.flow.MutableStateFlow(store.load())
	val session: kotlinx.coroutines.flow.StateFlow<Session?> = _session

	override fun currentToken(): String? = _session.value?.accessToken

	override fun refreshBlocking(): String? = runBlocking { refresh()?.accessToken }

	fun save(session: Session) {
		store.save(session)
		_session.value = session
	}

	fun clear() {
		store.clear()
		_session.value = null
	}

	suspend fun refresh(): Session? = refreshMutex.withLock {
		val current = _session.value ?: return null
		val config = supabase.config.value ?: return null
		val url = "${config.supabaseUrl.trimEnd('/')}/auth/v1/token?grant_type=refresh_token"
		val request = Request.Builder()
			.url(url)
			.post(json.encodeBody(RefreshTokenBody(current.refreshToken)))
			.header("apikey", config.supabasePublishableKey)
			.header("Authorization", "Bearer ${config.supabasePublishableKey}")
			.build()
		val fresh = withContext(Dispatchers.IO) {
			runCatching {
				client.newBuilder()
					.callTimeout(15, TimeUnit.SECONDS)
					.build()
					.newCall(request)
					.execute()
					.use { response ->
						if (!response.isSuccessful) return@use null
						val body = response.body?.string() ?: return@use null
						runCatching { json.decodeFromString<GoTrueSessionDto>(body).toSession() }.getOrNull()
					}
			}.getOrNull()
		}
		if (fresh == null) {
			clear()
			return null
		}
		save(fresh)
		return fresh
	}
}
