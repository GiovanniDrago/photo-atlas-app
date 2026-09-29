package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.data.remote.PatchBackupRunBody
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class BackupClientTest {
	private lateinit var server: MockWebServer
	private lateinit var client: PhotoAtlasClient

	@Before
	fun setUp() {
		server = MockWebServer()
		server.start()
		val base = FakeBaseUrlProvider(server.url("/").toString().trimEnd('/'))
		client = PhotoAtlasClient(base, OkHttpClient(), testJson())
	}

	@After
	fun tearDown() {
		server.shutdown()
	}

	@Test
	fun `status parses sources and totals`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"sources":[{"id":"s1","label":"Camera","total":10,"uploaded":7,
				 "pending":2,"failed":1,"auto_backup":true}],
				 "totals":{"total":10,"uploaded":7,"pending":2,"failed":1,
				 "bytes_uploaded":1000,"bytes_total":2000}}""",
			),
		)
		val response = client.backupStatusFull()
		assertEquals(1, response.sources.size)
		assertEquals(1000L, response.totals.bytesUploaded)
		assertEquals(2000L, response.totals.bytesTotal)
		assertEquals(7, response.totals.uploaded)
	}

	@Test
	fun `pending sends the source and reads the claimed items`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"items":[{"id":"m1","source_id":"s1","external_key":"42","name":"a.jpg",
				 "media_type":"image","size_bytes":123,"backup_status":"uploading",
				 "backup_attempts":1,"source_label":"Camera"}]}""",
			),
		)
		val items = client.backupPending(sourceId = "s1", limit = 5)
		val path = server.takeRequest().path.orEmpty()
		assertEquals(1, items.size)
		assertEquals("42", items.first().externalKey)
		assertEquals("uploading", items.first().backupStatus)
		assertTrue("source: $path", path.contains("source_id=s1"))
		assertTrue("limit: $path", path.contains("limit=5"))
	}

	@Test
	fun `release sends the claimed ids`() = runTest {
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"released":2}"""))
		val released = client.backupRelease(listOf("m1", "m2"))
		val body = server.takeRequest().body.readUtf8()
		assertEquals(2, released)
		assertTrue("ids: $body", body.contains("\"ids\":[\"m1\",\"m2\"]"))
	}

	@Test
	fun `verify queue and verify result parse the outcomes`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"items":[{"id":"m1","source_id":"s1","external_key":"42","name":"a.jpg",
				 "size_bytes":123,"backup_status":"uploaded","kdrive_file_id":987,
				 "source_label":"Camera"}]}""",
			),
		)
		val queue = client.verifyQueue(sourceId = "s1", limit = 500)
		val queuePath = server.takeRequest().path.orEmpty()
		assertEquals(1, queue.size)
		assertEquals(987L, queue.first().kdriveFileId)
		assertTrue("queue: $queuePath", queuePath.startsWith("/api/backup/verify-queue"))

		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"ok":false,"status":"pending","reason":"size_mismatch","kdrive_size":99}""",
			),
		)
		val result = client.verifyMedia("m1")
		assertEquals("/api/media/m1/verify", server.takeRequest().path)
		assertFalse(result.ok)
		assertEquals("size_mismatch", result.reason)
		assertEquals(99L, result.kdriveSize)
	}

	@Test
	fun `runs are created and patched with absolute counters`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(201).setBody(
				"""{"run":{"id":"r1","kind":"backup","status":"running","source_id":"s1"}}""",
			),
		)
		val run = client.createBackupRun(kind = "backup", sourceId = "s1", deviceId = "d1")
		val createBody = server.takeRequest().body.readUtf8()
		assertEquals("r1", run.id)
		assertTrue("source: $createBody", createBody.contains("\"source_id\":\"s1\""))
		assertTrue("device: $createBody", createBody.contains("\"device_id\":\"d1\""))

		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"run":{"id":"r1","kind":"backup","status":"completed","files_uploaded":3,
				 "bytes_uploaded":300,"errors":[]}}""",
			),
		)
		val patched = client.patchBackupRun(
			"r1",
			PatchBackupRunBody(
				status = "completed",
				filesUploaded = 3,
				bytesUploaded = 300,
				errors = listOf("a.jpg: boom"),
			),
		)
		val patchBody = server.takeRequest().body.readUtf8()
		assertEquals("completed", patched.status)
		assertEquals(3, patched.filesUploaded)
		assertTrue("status: $patchBody", patchBody.contains("\"status\":\"completed\""))
		assertTrue("uploaded: $patchBody", patchBody.contains("\"files_uploaded\":3"))
		assertTrue("errors: $patchBody", patchBody.contains("a.jpg: boom"))
	}
}
