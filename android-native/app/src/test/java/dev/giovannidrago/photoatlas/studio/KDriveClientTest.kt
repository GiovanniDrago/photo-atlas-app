package dev.giovannidrago.photoatlas.studio

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

class KDriveClientTest {
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
	fun `status parses the connected account`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"connected":true,"account":{"id":"acc-1","label":"kDrive",
				 "drive_id":12345,"created_at":"2026-09-27T10:00:00.000Z"}}""",
			),
		)
		val status = client.kdriveStatus()
		assertEquals("path", "/api/kdrive/status", server.takeRequest().path)
		assertTrue(status.connected)
		assertEquals("acc-1", status.account?.id)
		assertEquals(12345L, status.account?.driveId)
	}

	@Test
	fun `status without account is disconnected`() = runTest {
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"connected":false,"account":null}"""))
		val status = client.kdriveStatus()
		assertFalse(status.connected)
		assertEquals(null, status.account)
	}

	@Test
	fun `connect sends the token and the drive id`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(201).setBody(
				"""{"account":{"id":"acc-1","label":"kDrive","drive_id":12345}}""",
			),
		)
		val account = client.connectKDrive(token = "tok-1", driveId = "12345")
		val request = server.takeRequest()
		val body = request.body.readUtf8()
		assertEquals("path", "/api/kdrive/connect", request.path)
		assertEquals("acc-1", account.id)
		assertTrue("token: $body", body.contains("\"token\":\"tok-1\""))
		assertTrue("drive: $body", body.contains("\"drive_id\":\"12345\""))
	}

	@Test
	fun `folders sends the parent and parses the page`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"parent_id":1,"folders":[{"id":42,"name":"Photos"},{"id":43,"name":"Videos"}],
				 "cursor":"c1","has_more":true}""",
			),
		)
		val page = client.kdriveFolders(parentId = 1, cursor = null)
		val path = server.takeRequest().path.orEmpty()
		assertTrue("parent: $path", path.contains("parent_id=1"))
		assertEquals("folders", 2, page.folders.size)
		assertEquals("Photos", page.folders.first().name)
		assertEquals(42L, page.folders.first().id)
		assertTrue(page.hasMore)
		assertEquals("c1", page.cursor)
	}

	@Test
	fun `scan sends the folder and the subfolder flag`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(202).setBody(
				"""{"scan_run_id":"run-1","source_id":"src-1","include_subfolders":false}""",
			),
		)
		val response = client.kdriveScan(folderId = 42, includeSubfolders = false, label = "kDrive: Photos")
		val body = server.takeRequest().body.readUtf8()
		assertEquals("run-1", response.scanRunId)
		assertEquals("src-1", response.sourceId)
		assertFalse(response.includeSubfolders)
		assertTrue("folder: $body", body.contains("\"folder_id\":42"))
		assertTrue("flag: $body", body.contains("\"include_subfolders\":false"))
		assertTrue("label: $body", body.contains("\"label\":\"kDrive: Photos\""))
	}

	@Test
	fun `scan run parses the counters and the completion`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"scan_run":{"id":"run-1","source_id":"src-1","status":"completed",
				 "files_seen":120,"files_indexed":118,"files_skipped":2,"errors":[]}}""",
			),
		)
		val run = client.scanRun("run-1")
		assertEquals("/api/scan-runs/run-1", server.takeRequest().path)
		assertEquals(120, run.filesSeen)
		assertEquals(118, run.filesIndexed)
		assertTrue(run.finished)
	}

	@Test
	fun `enrich and previews states parse the progress`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(202).setBody("""{"queued":50}"""),
		)
		client.kdriveEnrich(limit = 50)
		val enrichBody = server.takeRequest().body.readUtf8()
		assertTrue("limit: $enrichBody", enrichBody.contains("\"limit\":50"))

		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"running":true,"processed":12,"updated":9,"errors":[]}""",
			),
		)
		val enrich = client.kdriveEnrichState()
		val enrichPath = server.takeRequest().path.orEmpty()
		assertEquals("/api/kdrive/enrich", enrichPath)
		assertTrue(enrich.running)
		assertEquals(12, enrich.processed)
		assertEquals(9, enrich.updated)

		server.enqueue(MockResponse().setResponseCode(202).setBody("""{"queued":true}"""))
		client.kdrivePreviews()
		assertEquals("/api/kdrive/previews", server.takeRequest().path)

		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"running":false,"processed":30,"updated":28,"skipped":2,"errors":[]}""",
			),
		)
		val previews = client.kdrivePreviewsState()
		assertFalse(previews.running)
		assertEquals(30, previews.processed)
		assertEquals(2, previews.skipped)
	}

	@Test
	fun `source subfolders patch sends the flag`() = runTest {
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"source":{"id":"s1"}}"""))
		client.updateSource("s1", includeSubfolders = false)
		val request = server.takeRequest()
		assertEquals("PATCH", request.method)
		assertEquals("/api/sources/s1", request.path)
		val body = request.body.readUtf8()
		assertTrue("include: $body", body.contains("\"include_subfolders\":false"))
	}
}
