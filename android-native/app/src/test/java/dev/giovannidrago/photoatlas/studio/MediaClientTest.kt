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
		assertEquals(42, page.total)
		assertEquals(1, page.items.size)
		val item = page.items.first()
		assertEquals("a.jpg", item.name)
		assertEquals("http://host/thumb", item.thumbnailUrl)
		assertTrue(item.isUploaded)
		assertEquals(1234L, item.sizeBytes)
		assertEquals(1_704_103_200_000L, item.takenAtMs)

		val request = server.takeRequest()
		val path = request.path.orEmpty()
		assertTrue(path.startsWith("/api/media?"))
		assertTrue(path.contains("type=image"))
		assertTrue(path.contains("backup_status=uploaded"))
		assertTrue(path.contains("limit=100"))
	}

	@Test
	fun `device registration sources batch and delete payloads`() = runTest {
		server.enqueue(MockResponse().setResponseCode(200).setBody("""{"device":{"id":"dev-1"}}"""))
		assertEquals("dev-1", client.registerDevice("fp-123", "Android device", "android"))
		val deviceRequest = server.takeRequest()
		assertEquals("/api/devices", deviceRequest.path)
		val deviceBody = deviceRequest.body.readUtf8()
		assertTrue(deviceBody.contains("\"fingerprint\":\"fp-123\""))
		assertTrue(deviceBody.contains("\"platform\":\"android\""))

		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"sources":[{"id":"s1","kind":"local","label":"Camera","album_key":"path:Camera"}]}""",
			),
		)
		val sources = client.sources()
		assertEquals("Camera", sources.first().label)
		assertEquals("path:Camera", sources.first().albumKey)

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
		assertEquals("s2", source.id)
		val createBody = server.takeRequest().body.readUtf8()
		assertTrue(createBody.contains("\"album_key\":\"path:Manual\""))
		assertTrue(createBody.contains("\"root_path\":\"album:path:Manual\""))

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
		assertEquals("m9", batch.items.first().id)
		assertEquals(1, batch.indexed)
		val batchBody = server.takeRequest().body.readUtf8()
		assertTrue(batchBody.contains("\"thumbnail_b64\":\"aGk=\""))
		assertTrue(batchBody.contains("\"source_id\":\"source-1\""))

		server.enqueue(
			MockResponse().setResponseCode(200).setBody(
				"""{"deleted":1,"cloud_deleted":1,"reset":0,"failed":[]}""",
			),
		)
		val deleted = client.deleteMedia(ids = listOf("m1"), cloud = true, index = true)
		assertEquals(1, deleted.deleted)
		assertEquals(1, deleted.cloudDeleted)
		val deleteBody = server.takeRequest().body.readUtf8()
		assertTrue(deleteBody.contains("\"index\":true"))
		assertTrue(deleteBody.contains("\"cloud\":true"))
	}
}
