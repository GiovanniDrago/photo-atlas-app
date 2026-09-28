package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.domain.gallery.MetadataExport
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MetadataExportTest {
	@Test
	fun `export keeps the snake case fields of the flutter app`() {
		val payload = MetadataExport.build(
			items = listOf(
				cloudItem(
					id = "media-1",
					externalKey = "asset-1",
					name = "IMG_0001.jpg",
					backupStatus = "uploaded",
					sizeBytes = 1234L,
					takenAtMs = 1_700_000_000_000L,
				),
			),
			exportedAtMs = 1_800_000_000_000L,
		)
		val document = Json.parseToJsonElement(payload).jsonObject
		assertEquals(1, document["count"]?.jsonPrimitive?.content?.toInt())
		assertEquals("2027-01-15T08:00:00Z", document["exported_at"]?.jsonPrimitive?.content)
		val item = document["items"]!!.jsonArray.first().jsonObject
		assertEquals("media-1", item["id"]?.jsonPrimitive?.content)
		assertEquals("IMG_0001.jpg", item["name"]?.jsonPrimitive?.content)
		assertEquals("image", item["media_type"]?.jsonPrimitive?.content)
		assertEquals(1234, item["size_bytes"]?.jsonPrimitive?.content?.toLong())
		assertEquals("uploaded", item["backup_status"]?.jsonPrimitive?.content)
		assertEquals("asset-1", item["external_key"]?.jsonPrimitive?.content)
		assertEquals("2023-11-14T22:13:20Z", item["taken_at"]?.jsonPrimitive?.content)
		assertEquals("local", item["source_kind"]?.jsonPrimitive?.content)
		assertTrue(item.containsKey("metadata_status"))
		assertTrue(item.containsKey("has_gps"))
	}

	@Test
	fun `export of an empty selection is valid json`() {
		val payload = MetadataExport.build(items = emptyList(), exportedAtMs = 0L)
		val document = Json.parseToJsonElement(payload).jsonObject
		assertEquals(0, document["count"]?.jsonPrimitive?.content?.toInt())
		assertEquals(0, document["items"]!!.jsonArray.size)
	}
}
