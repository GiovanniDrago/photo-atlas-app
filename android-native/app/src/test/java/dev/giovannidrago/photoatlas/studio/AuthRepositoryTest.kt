package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.data.auth.Session
import dev.giovannidrago.photoatlas.studio.data.auth.SessionManager
import dev.giovannidrago.photoatlas.studio.data.auth.SessionStore
import dev.giovannidrago.photoatlas.studio.data.remote.ApiConfigDto
import dev.giovannidrago.photoatlas.studio.data.remote.ApiException
import dev.giovannidrago.photoatlas.studio.data.remote.GoTrueClient
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.data.remote.SupabaseConfigStore
import dev.giovannidrago.photoatlas.studio.data.security.InMemorySecureStorage
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthRepository
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthState
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class AuthRepositoryTest {
	private lateinit var server: MockWebServer
	private lateinit var json: Json
	private lateinit var config: SupabaseConfigStore
	private lateinit var sessions: SessionManager
	private lateinit var repository: AuthRepository

	private val requests = mutableListOf<Pair<String, String>>()

	@Before
	fun setUp() {
		server = MockWebServer()
		server.start()
		json = testJson()
		val baseUrl = server.url("/").toString().trimEnd('/')
		val base = FakeBaseUrlProvider(baseUrl)
		val client = OkHttpClient()
		config = SupabaseConfigStore().apply {
			set(
				ApiConfigDto(
					supabaseUrl = baseUrl,
					supabasePublishableKey = "sb_publishable_test",
					emailConfirmRedirectUrl = "https://example.test/confirm",
				),
			)
		}
		sessions = SessionManager(
			SessionStore(InMemorySecureStorage(), json),
			config,
			json,
			client,
		)
		val gotrue = GoTrueClient(config, sessions, client, json)
		val api = PhotoAtlasClient(base, client, json)
		repository = AuthRepository(sessions, gotrue, api, config)
	}

	@After
	fun tearDown() {
		server.shutdown()
	}

	private fun respond(path: String, body: String, code: Int = 200): MockResponse {
		requests.add(path to body)
		return MockResponse().setResponseCode(code).setBody(body)
	}

	private fun route(handler: (String, String) -> MockResponse) {
		server.dispatcher = LambdaDispatcher { request ->
			handler(request.path.orEmpty(), request.body.readUtf8())
		}
	}

	private val meBody = """
		{"user":{"id":"user-1","email":"a@b.c","display_name":"Alice","mfa_enabled":false}}
	""".trimIndent()

	private val sessionBody = """
		{"access_token":"access-1","refresh_token":"refresh-1","expires_in":3600,
		 "user":{"id":"user-1","email":"a@b.c","user_metadata":{"display_name":"Alice"}}}
	""".trimIndent()

	@Test
	fun `sign in stores the session and loads the profile`() = runTest {
		route { path, _ ->
			when {
				path.startsWith("/auth/v1/token") && path.contains("grant_type=password") ->
					respond(path, sessionBody)
				path == "/api/auth/me" -> respond(path, meBody)
				path == "/api/auth/recovery-codes" ->
					respond(path, """{"password_remaining":8,"mfa_remaining":0}""")
				else -> respond(path, """{"error":"unexpected $path"}""", 404)
			}
		}

		val state = repository.signIn("a@b.c", "secret-password")
		assertTrue(state is AuthState.SignedIn)
		assertEquals("a@b.c", (state as AuthState.SignedIn).user.email)
		assertEquals("access-1", sessions.session.value?.accessToken)
	}

	@Test
	fun `wrong password surfaces the server message`() = runTest {
		route { path, _ ->
			respond(
				path,
				"""{"error":"invalid_grant","error_description":"Invalid login credentials"}""",
				400,
			)
		}
		val failure = runCatching { repository.signIn("a@b.c", "nope") }.exceptionOrNull()
		assertTrue(failure is ApiException)
		assertEquals("Invalid login credentials", failure?.message)
	}

	@Test
	fun `mfa required then verify completes the login`() = runTest {
		var meCalls = 0
		route { path, _ ->
			when {
				path.startsWith("/auth/v1/token") -> respond(path, sessionBody)
				path == "/api/auth/me" -> {
					meCalls += 1
					if (meCalls == 1) {
						respond(path, """{"error":"mfa_required"}""", 403)
					} else {
						respond(path, meBody)
					}
				}
				path == "/auth/v1/user" -> respond(
					path,
					"""{"id":"user-1","factors":[{"id":"factor-1","factor_type":"totp","status":"verified"}]}""",
				)
				path == "/auth/v1/factors/factor-1/challenge" -> respond(path, """{"id":"challenge-1"}""")
				path == "/auth/v1/factors/factor-1/verify" -> respond(path, sessionBody)
				path == "/api/auth/recovery-codes" ->
					respond(path, """{"password_remaining":8,"mfa_remaining":0}""")
				else -> respond(path, """{"error":"unexpected $path"}""", 404)
			}
		}

		assertEquals(AuthState.MfaRequired, repository.signIn("a@b.c", "secret-password"))
		assertEquals(AuthState.MfaRequired, repository.state.value)

		val state = repository.verifyMfa("123456")
		assertTrue(state is AuthState.SignedIn)
		assertEquals("a@b.c", (state as AuthState.SignedIn).user.email)
	}

	@Test
	fun `restore refreshes an expired token once`() = runTest {
		sessions.save(
			Session(
				accessToken = "old-access",
				refreshToken = "refresh-1",
				expiresAtEpochMs = System.currentTimeMillis() - 1000,
				userId = "user-1",
				email = "a@b.c",
			),
		)
		var meCalls = 0
		route { path, _ ->
			when {
				path == "/api/auth/me" -> {
					meCalls += 1
					if (meCalls == 1) {
						respond(path, """{"error":"unauthorized"}""", 401)
					} else {
						respond(path, meBody)
					}
				}
				path.startsWith("/auth/v1/token") && path.contains("refresh_token") ->
					respond(path, sessionBody)
				path == "/api/auth/recovery-codes" ->
					respond(path, """{"password_remaining":8,"mfa_remaining":0}""")
				else -> respond(path, """{"error":"unexpected $path"}""", 404)
			}
		}

		val state = repository.restore()
		assertTrue(state is AuthState.SignedIn)
		assertEquals("access-1", sessions.session.value?.accessToken)
	}

	@Test
	fun `register without a session needs the email confirmation`() = runTest {
		route { path, _ ->
			when {
				path.startsWith("/auth/v1/signup") ->
					respond(path, """{"id":"user-1","email":"a@b.c"}""")
				else -> respond(path, """{"error":"unexpected $path"}""", 404)
			}
		}
		val signedIn = repository.register("a@b.c", "secret-password", "Alice", null)
		assertFalse(signedIn)
		assertEquals(null, sessions.session.value)
	}

	@Test
	fun `login without recovery codes generates them once`() = runTest {
		// GET and POST share the path: the GET reports zero codes, the POST
		// returns the fresh list.
		server.dispatcher = LambdaDispatcher { request ->
			val path = request.path.orEmpty()
			when {
				path.startsWith("/auth/v1/token") -> respond(path, sessionBody)
				path == "/api/auth/me" -> respond(path, meBody)
				path == "/api/auth/recovery-codes" && request.method == "GET" ->
					respond(path, """{"password_remaining":0,"mfa_remaining":0}""")
				path == "/api/auth/recovery-codes" && request.method == "POST" ->
					respond(path, """{"recovery_codes":["AAAA-BBBB","CCCC-DDDD"]}""")
				else -> respond(path, """{"error":"unexpected $path"}""", 404)
			}
		}

		val state = repository.signIn("a@b.c", "secret-password")
		assertTrue(state is AuthState.SignedIn)
		assertEquals(
			listOf("AAAA-BBBB", "CCCC-DDDD"),
			(state as AuthState.SignedIn).newRecoveryCodes,
		)
	}

	@Test
	fun `password reset with a recovery code hits the public endpoint`() = runTest {
		route { path, body ->
			if (path == "/api/auth/password/reset-with-code") {
				respond(path, """{"ok":true}""")
			} else {
				respond(path, """{"error":"unexpected $path"}""", 404)
			}
		}
		repository.resetPasswordWithCode("a@b.c", "ABCD-EF23", "brand-new-password")
		val recorded = server.takeRequest()
		assertEquals("/api/auth/password/reset-with-code", recorded.path)
		assertTrue(recorded.body.readUtf8().contains("ABCD-EF23"))
	}

	@Test
	fun `logout clears the stored session`() = runTest {
		sessions.save(
			Session(
				accessToken = "access-1",
				refreshToken = "refresh-1",
				expiresAtEpochMs = System.currentTimeMillis() + 3600_000,
				userId = "user-1",
			),
		)
		route { path, _ ->
			if (path.startsWith("/auth/v1/logout")) {
				respond(path, "")
			} else {
				respond(path, """{"error":"unexpected $path"}""", 404)
			}
		}
		repository.logout()
		assertEquals(AuthState.SignedOut, repository.state.value)
		assertEquals(null, sessions.session.value)
		assertNotNull(server.takeRequest())
	}
}
