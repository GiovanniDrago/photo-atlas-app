package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.data.remote.BatchItem
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class MediaClientTest {
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
	fun `media list sends the filters and parses the page`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"items":[{"id":"m1","source_id":"s1","external_key":"asset-1","name":"a.jpg",
				 "media_type":"image","backup_status":"uploaded","taken_at":"2024-01-01T10:00:00Z",
				 "thumbnail_url":"http://host/thumb","size_bytes":1234}],
				 "total":42,"limit":100,"offset":0}""",
			),
		)
		val page = client.media(
			status = "all",
			type = "image",
			backupStatus = "uploaded",
			limit = 100,
			offset = 0,
		)
		assertEquals("total", 42, page.total)
		assertEquals("items", 1, page.items.size)
		val item = page.items.first()
		assertEquals("name", "a.jpg", item.name)
		assertEquals("thumbnail", "http://host/thumb", item.thumbnailUrl)
		assertTrue("uploaded", item.isUploaded)
		assertEquals("size", 1234L, item.sizeBytes)
		assertEquals("taken", 1_704_103_200_000L, item.takenAtMs)

		val path = server.takeRequest().path.orEmpty()
		assertTrue("path: $path", path.startsWith("/api/media?"))
		assertTrue("type: $path", path.contains("type=image"))
		assertTrue("status: $path", path.contains("backup_status=uploaded"))
		assertTrue("limit: $path", path.contains("limit=100"))
	}

	@Test
	fun `device registration sends the fingerprint`() = runTest {
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"device":{"id":"dev-1"}}"""))
		val id = client.registerDevice("fp-123", "Android device", "android")
		val request = server.takeRequest()
		val body = request.body.readUtf8()
		assertEquals("path: ${request.path}", "/api/devices", request.path)
		assertEquals("body: $body", "dev-1", id)
		assertTrue("fingerprint: $body", body.contains("\"fingerprint\":\"fp-123\""))
		assertTrue("platform: $body", body.contains("\"platform\":\"android\""))
	}

	@Test
	fun `sources listing and creation use the expected payloads`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"sources":[{"id":"s1","kind":"local","label":"Camera","album_key":"path:Camera"}]}""",
			),
		)
		val sources = client.sources()
		assertEquals("label", "Camera", sources.first().label)
		assertEquals("album key", "path:Camera", sources.first().albumKey)

		server.enqueue(
			MockResponse().setResponseCode(201).setBody(
				"""{"source":{"id":"s2","kind":"local","label":"Manual"}}""",
			),
		)
		val source = client.createSource(
			kind = "local",
			label = "Manual",
			rootPath = "album:path:Manual",
			deviceId = "dev-1",
			albumKey = "path:Manual",
		)
		val body = server.takeRequest().body.readUtf8()
		assertEquals("source id", "s2", source.id)
		assertTrue("album_key: $body", body.contains("\"album_key\":\"path:Manual\""))
		assertTrue("root_path: $body", body.contains("\"root_path\":\"album:path:Manual\""))
	}

	@Test
	fun `batch indexing sends the item and reads the ids`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"indexed":1,"items":[{"id":"m9","external_key":"42"}]}""",
			),
		)
		val batch = client.batchMedia(
			"source-1",
			listOf(
				BatchItem(
					externalKey = "42",
					name = "IMG.jpg",
					mime = "image/jpeg",
					mediaType = "image",
					sizeBytes = 10L,
					thumbnailB64 = "aGk=",
				),
			),
		)
		val body = server.takeRequest().body.readUtf8()
		assertEquals("indexed", 1, batch.indexed)
		assertEquals("media id", "m9", batch.items.first().id)
		assertTrue("thumbnail: $body", body.contains("\"thumbnail_b64\":\"aGk=\""))
		assertTrue("source: $body", body.contains("\"source_id\":\"source-1\""))
	}

	@Test
	fun `delete sends the flags and reads the counters`() = runTest {
		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"deleted":1,"cloud_deleted":1,"reset":0,"failed":[]}""",
			),
		)
		val deleted = client.deleteMedia(ids = listOf("m1"), cloud = true, index = true)
		val body = server.takeRequest().body.readUtf8()
		assertEquals("deleted", 1, deleted.deleted)
		assertEquals("cloud deleted", 1, deleted.cloudDeleted)
		assertTrue("index: $body", body.contains("\"index\":true"))
		assertTrue("cloud: $body", body.contains("\"cloud\":true"))
	}
}
