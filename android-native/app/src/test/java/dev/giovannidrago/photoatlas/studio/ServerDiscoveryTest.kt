package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.data.discovery.ProbeOutcome
import dev.giovannidrago.photoatlas.studio.data.discovery.ServerDiscovery
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class ServerDiscoveryTest {
	private lateinit var server: MockWebServer

	private val configBody =
		"""{"supabase_url":"https://x.supabase.co","supabase_publishable_key":"sb_test"}"""

	@Before
	fun setUp() {
		server = MockWebServer()
		server.start()
	}

	@After
	fun tearDown() {
		server.shutdown()
	}

	private fun discovery(baseUrl: String): ServerDiscovery = ServerDiscovery(
		settings = FakeBaseUrlProvider(baseUrl),
		client = OkHttpClient(),
	)

	private fun route(handler: (String) -> MockResponse) {
		server.dispatcher = object : Dispatcher() {
			override fun dispatch(request: RecordedRequest): MockResponse =
				handler(request.path.orEmpty())
		}
	}

	@Test
	fun `test reports success only for the photo atlas api`() = runBlocking {
		route { path ->
			when (path) {
				"/health" -> MockResponse().setResponseCode(200).setBody("""{"status":"ok"}""")
				"/api/config" -> MockResponse().setResponseCode(200).setBody(configBody)
				else -> MockResponse().setResponseCode(404)
			}
		}
		val outcome = discovery(server.url("/").toString()).test(server.url("/").toString())
		assertTrue("outcome: $outcome", outcome is ProbeOutcome.Success)
		assertTrue((outcome as ProbeOutcome.Success).configOk)
	}

	@Test
	fun `test rejects a server that is not our api`() = runBlocking {
		route { path ->
			if (path == "/health") {
				MockResponse().setResponseCode(200).setBody("""{"status":"ok"}""")
			} else {
				MockResponse().setResponseCode(404)
			}
		}
		val outcome = discovery(server.url("/").toString()).test(server.url("/").toString())
		assertTrue("outcome: $outcome", outcome is ProbeOutcome.Failure)
		assertEquals("not the Photo Atlas API", (outcome as ProbeOutcome.Failure).reason)
	}

	@Test
	fun `test reports http errors timeouts and refusals`() = runBlocking {
		route { MockResponse().setResponseCode(500) }
		val http = discovery(server.url("/").toString()).test(server.url("/").toString())
		assertTrue("http: $http", http is ProbeOutcome.HttpError)
		assertEquals(500, (http as ProbeOutcome.HttpError).code)

		route {
			MockResponse().setResponseCode(200)
				.setBody("""{"status":"ok"}""")
				.setBodyDelay(2, TimeUnit.SECONDS)
		}
		val timeout = discovery(server.url("/").toString())
			.test(server.url("/").toString(), timeoutMs = 300)
		assertTrue("timeout: $timeout", timeout is ProbeOutcome.Timeout)

		val refused = discovery("http://127.0.0.1:1").test("http://127.0.0.1:1")
		assertTrue("refused: $refused", refused is ProbeOutcome.Refused)
	}

	@Test
	fun `detect adopts a reachable candidate and records the failures`() = runBlocking {
		route { path ->
			when (path) {
				"/health" -> MockResponse().setResponseCode(200).setBody("""{"status":"ok"}""")
				"/api/config" -> MockResponse().setResponseCode(200).setBody(configBody)
				else -> MockResponse().setResponseCode(404)
			}
		}
		val reachable = server.url("/").toString().trimEnd('/')
		val settings = FakeBaseUrlProvider(reachable)
		val discovery = ServerDiscovery(settings, OkHttpClient())

		val result = discovery.detectAndSave(prefer = "http://127.0.0.1:1", scanLan = false)
		assertEquals(reachable, result.url)
		assertEquals(reachable, settings.url)
		assertTrue("attempts: ${result.attempts}", result.attempts.isNotEmpty())
		assertTrue(result.attempts.first() is ProbeOutcome.Refused)
	}

	@Test
	fun `detect does not adopt a health only server`() = runBlocking {
		route { path ->
			if (path == "/health") {
				MockResponse().setResponseCode(200).setBody("""{"status":"ok"}""")
			} else {
				MockResponse().setResponseCode(404)
			}
		}
		val healthOnly = server.url("/").toString().trimEnd('/')
		val settings = FakeBaseUrlProvider(healthOnly)
		val discovery = ServerDiscovery(settings, OkHttpClient())

		val result = discovery.detectAndSave(prefer = healthOnly, scanLan = false)
		assertNull(result.url)
		assertTrue(
			"attempts: ${result.attempts}",
			result.attempts.any {
				it is ProbeOutcome.Failure && it.reason.contains("/api/config")
			},
		)
	}
}
