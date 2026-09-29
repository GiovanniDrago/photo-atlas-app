package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.data.remote.ApiException
import dev.giovannidrago.photoatlas.studio.data.remote.UploadCancelled
import dev.giovannidrago.photoatlas.studio.data.remote.UploadService
import java.io.ByteArrayInputStream
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class UploadServiceTest {
	private lateinit var server: MockWebServer
	private lateinit var service: UploadService

	@Before
	fun setUp() {
		server = MockWebServer()
		server.start()
		service = UploadService(
			settings = FakeBaseUrlProvider(server.url("/").toString().trimEnd('/')),
			tokens = FakeTokenProvider(token = "access-1"),
			client = OkHttpClient(),
		)
	}

	@After
	fun tearDown() {
		server.shutdown()
	}

	@Test
	fun `streams the file reporting the progress`() = runBlocking {
		val bytes = ByteArray(200_000) { index -> index.toByte() }
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"ok":true}"""))
		val progress = mutableListOf<Pair<Long, Long>>()

		service.upload(
			mediaId = "media-1",
			openStream = { ByteArrayInputStream(bytes) },
			contentLength = bytes.size.toLong(),
			onProgress = { sent, total -> progress += sent to total },
		)

		assertTrue(progress.isNotEmpty())
		assertEquals(bytes.size.toLong(), progress.last().first)
		assertEquals(bytes.size.toLong(), progress.last().second)
		assertTrue(progress.zipWithNext().all { (a, b) -> a.first <= b.first })

		val request = server.takeRequest()
		assertEquals("/api/media/media-1/upload", request.path)
		assertEquals("Bearer access-1", request.getHeader("Authorization"))
		assertEquals(bytes.size.toLong(), request.bodySize)
	}

	@Test
	fun `cancellation stops the upload`() {
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"ok":true}"""))
		assertThrows(UploadCancelled::class.java) {
			runBlocking {
				service.upload(
					mediaId = "media-2",
					openStream = { ByteArrayInputStream(ByteArray(100_000)) },
					contentLength = 100_000L,
					isCancelled = { true },
				)
			}
		}
	}

	@Test
	fun `manual destination goes in the query`() = runBlocking {
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"ok":true}"""))
		service.upload(
			mediaId = "media-4",
			openStream = { ByteArrayInputStream(ByteArray(10)) },
			contentLength = 10L,
			destination = "manual",
		)
		assertEquals("/api/media/media-4/upload?destination=manual", server.takeRequest().path)
	}

	@Test
	fun `server errors become api exceptions`() {
		server.enqueue(
			MockResponse().setResponseCode(400).setBody("""{"error":"empty_body"}"""),
		)
		val failure = assertThrows(ApiException::class.java) {
			runBlocking {
				service.upload(
					mediaId = "media-3",
					openStream = { ByteArrayInputStream(ByteArray(1024)) },
					contentLength = 1024L,
				)
			}
		}
		assertEquals(400, failure.statusCode)
		assertEquals("empty_body", failure.message)
	}
}
