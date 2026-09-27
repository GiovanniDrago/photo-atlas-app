package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.data.auth.SessionManager
import dev.giovannidrago.photoatlas.studio.data.auth.SessionStore
import dev.giovannidrago.photoatlas.studio.data.discovery.ServerDiscovery
import dev.giovannidrago.photoatlas.studio.data.remote.GoTrueClient
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.data.remote.SupabaseConfigStore
import dev.giovannidrago.photoatlas.studio.data.security.InMemorySecureStorage
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthRepository
import dev.giovannidrago.photoatlas.studio.ui.bootstrap.BootstrapController
import dev.giovannidrago.photoatlas.studio.ui.bootstrap.BootstrapState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class BootstrapControllerTest {
	private lateinit var server: MockWebServer
	private lateinit var json: Json

	@Before
	fun setUp() {
		Dispatchers.setMain(UnconfinedTestDispatcher())
		server = MockWebServer()
		server.start()
		json = testJson()
	}

	@After
	fun tearDown() {
		server.shutdown()
		Dispatchers.resetMain()
	}

	private fun controller(baseUrl: String): BootstrapController {
		val base = FakeBaseUrlProvider(baseUrl)
		val client = OkHttpClient()
		val supabase = SupabaseConfigStore()
		val sessions = SessionManager(
			SessionStore(InMemorySecureStorage(), json),
			supabase,
			json,
			client,
		)
		val gotrue = GoTrueClient(supabase, sessions, client, json)
		val api = PhotoAtlasClient(base, client, json)
		val auth = AuthRepository(sessions, gotrue, api, supabase)
		val discovery = ServerDiscovery(base, client)
		return BootstrapController(discovery, api, supabase, auth)
	}

	@Test
	fun `bootstrap starts with the app and becomes ready`() = runBlocking {
		server.dispatcher = LambdaDispatcher { request ->
			when (request.path) {
				"/health" -> MockResponse().setResponseCode(200).setBody("""{"status":"ok"}""")
				"/api/config" -> MockResponse().setResponseCode(200).setBody(
					"""{"supabase_url":"http://localhost:1","supabase_publishable_key":"sb_test"}""",
				)
				else -> MockResponse().setResponseCode(404)
			}
		}
		val controller = controller(server.url("/").toString().trimEnd('/'))
		val state = withTimeout(15_000) {
			controller.state.first { it !is BootstrapState.Loading }
		}
		assertTrue(state is BootstrapState.Ready)
	}

	@Test
	fun `unreachable server reports the tried addresses`() = runBlocking {
		server.dispatcher = LambdaDispatcher { MockResponse().setResponseCode(503) }
		val controller = controller("http://127.0.0.1:1")
		val state = withTimeout(30_000) {
			controller.state.first { it is BootstrapState.Error }
		} as BootstrapState.Error
		assertTrue(state.message.contains("tried:"))
	}
}
