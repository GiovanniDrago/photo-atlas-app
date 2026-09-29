package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.data.device.DeviceMedia
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaIndexer
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaSource
import dev.giovannidrago.photoatlas.studio.data.device.DeviceRegistrar
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.data.remote.UploadService
import dev.giovannidrago.photoatlas.studio.domain.backup.BackupService
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryActionsService
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.io.ByteArrayInputStream
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class BackupServiceTest {
	private lateinit var server: MockWebServer
	private lateinit var service: BackupService
	private lateinit var device: DeviceMediaSource
	private lateinit var indexer: DeviceMediaIndexer

	@Before
	fun setUp() {
		server = MockWebServer()
		server.start()
		val base = FakeBaseUrlProvider(server.url("/").toString().trimEnd('/'))
		val api = PhotoAtlasClient(base, OkHttpClient(), testJson())
		device = mockk()
		indexer = mockk()
		val registrar = mockk<DeviceRegistrar> {
			coEvery { ensureRegistered() } returns "dev-1"
		}
		val actions = mockk<GalleryActionsService>(relaxed = true)
		val uploader = UploadService(
			settings = base,
			tokens = FakeTokenProvider(token = "access-1"),
			client = OkHttpClient(),
		)
		service = BackupService(api, registrar, device, actions, indexer, uploader)
	}

	@After
	fun tearDown() {
		server.shutdown()
	}

	private fun localMedia(name: String) = DeviceMedia(
		id = 42L,
		name = name,
		uri = "content://media/42",
		mime = "image/jpeg",
		mediaType = "image",
		sizeBytes = 100L,
		fileCreatedAtMs = null,
		takenAtMs = null,
		modifiedAtMs = null,
		durationS = null,
		width = null,
		height = null,
		relativePath = "DCIM/Camera",
		bucketId = null,
		lat = null,
		lon = null,
	)

	private fun recordedRequests(): List<okhttp3.mockwebserver.RecordedRequest> {
		val requests = mutableListOf<okhttp3.mockwebserver.RecordedRequest>()
		while (true) {
			val request = server.takeRequest(1, java.util.concurrent.TimeUnit.SECONDS) ?: break
			requests += request
		}
		return requests
	}

	private fun pendingItem(id: String, name: String) =
		"""{"id":"$id","source_id":"s1","external_key":"42","name":"$name",
		 "media_type":"image","size_bytes":100,"backup_status":"uploading"}"""

	private fun runBody(id: String = "r1", kind: String = "backup") =
		"""{"run":{"id":"$id","kind":"$kind","status":"running"}}"""

	@Test
	fun `backup run uploads the pending claims and completes`() = runTest {
		coEvery { device.resolveForItems(any()) } returns mapOf("42" to localMedia("a.jpg"))
		every { indexer.openStream(any()) } returns ByteArrayInputStream(ByteArray(100))

		server.enqueue(MockResponse().setResponseCode(201).setBody(runBody()))
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"items":[${pendingItem("m1", "a.jpg")},${pendingItem("m2", "b.jpg")}]}""",
			),
		)
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"ok":true}"""))
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"ok":true}"""))
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"items":[]}"""))
		server.enqueue(MockResponse().setResponseCode(200).setBody(runBody()))

		val result = service.runBackup(sourceId = "s1")

		assertEquals(2, result.uploaded)
		assertEquals(0, result.failed)
		assertEquals(200L, result.bytesUploaded)

		val paths = recordedRequests().map { "${it.method} ${it.path}" }
		assertTrue("uploads: $paths", paths.count { it.startsWith("POST /api/media/m") } == 2)
		val patch = paths.firstOrNull { it.startsWith("PATCH /api/backup/runs/r1") }
		assertTrue("patch: $paths", patch != null)
	}

	@Test
	fun `failed uploads are not retried inside the same run`() = runTest {
		coEvery { device.resolveForItems(any()) } returns mapOf("42" to localMedia("a.jpg"))
		every { indexer.openStream(any()) } returns ByteArrayInputStream(ByteArray(100))

		server.enqueue(MockResponse().setResponseCode(201).setBody(runBody()))
		server.enqueue(
			MockResponse().setResponseCode(200).setBody("""{"items":[${pendingItem("m1", "a.jpg")}]}"""),
		)
		server.enqueue(MockResponse().setResponseCode(502).setBody("""{"error":"upload_failed"}"""))
		server.enqueue(
			MockResponse().setResponseCode(200).setBody("""{"items":[${pendingItem("m1", "a.jpg")}]}"""),
		)
		server.enqueue(MockResponse().setResponseCode(200).setBody(runBody()))

		val result = service.runBackup(sourceId = "s1")

		assertEquals(0, result.uploaded)
		assertEquals(1, result.failed)
		assertEquals(1, result.errors.size)
		val uploads = recordedRequests().count { it.path?.startsWith("/api/media/m1/upload") == true }
		assertEquals("only one upload attempt", 1, uploads)
	}

	@Test
	fun `cancelling releases the claims of the current batch`() = runTest {
		coEvery { device.resolveForItems(any()) } returns mapOf("42" to localMedia("a.jpg"))
		every { indexer.openStream(any()) } returns ByteArrayInputStream(ByteArray(100))

		server.enqueue(MockResponse().setResponseCode(201).setBody(runBody()))
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"items":[${pendingItem("m1", "a.jpg")},${pendingItem("m2", "b.jpg")}]}""",
			),
		)
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"ok":true}"""))
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"released":1}"""))
		server.enqueue(MockResponse().setResponseCode(200).setBody(runBody()))

		var uploads = 0
		val result = service.runBackup(
			sourceId = "s1",
			onProgress = { progress ->
				if (progress.uploaded == 1) uploads = 1
			},
			isCancelled = { uploads >= 1 },
		)

		assertTrue(result.cancelled)
		assertEquals(1, result.uploaded)

		val release = recordedRequests().firstOrNull { it.path == "/api/backup/release" }
		assertTrue("release sent", release != null)
		val releaseBody = release?.body?.readUtf8().orEmpty()
		assertTrue("release body: $releaseBody", releaseBody.contains("\"m2\""))
		assertTrue("does not release the uploaded item", !releaseBody.contains("\"m1\""))
	}
	@Test
	fun `verify run counts ok and missing results`() = runTest {
		server.enqueue(MockResponse().setResponseCode(201).setBody(runBody(kind = "verify")))
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"items":[{"id":"m1","source_id":"s1","external_key":"42","name":"a.jpg",
				 "backup_status":"uploaded","kdrive_file_id":987},
				 {"id":"m2","source_id":"s1","external_key":"43","name":"b.jpg",
				 "backup_status":"uploaded","kdrive_file_id":988}]}""",
			),
		)
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"ok":true,"status":"uploaded"}"""))
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"ok":false,"status":"pending","reason":"size_mismatch"}""",
			),
		)
		server.enqueue(MockResponse().setResponseCode(200).setBody(runBody(kind = "verify")))

		val result = service.runVerify(sourceId = "s1")

		assertEquals(1, result.ok)
		assertEquals(1, result.missing)
		assertTrue(result.errors.first().contains("size_mismatch"))
	}
}
