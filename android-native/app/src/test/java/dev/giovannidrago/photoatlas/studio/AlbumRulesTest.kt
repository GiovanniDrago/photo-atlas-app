package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.domain.gallery.AlbumRuleDraft
import java.time.LocalDate
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AlbumRulesTest {
	@Test
	fun `date ranges compile to between gte and lte with utc bounds`() {
		val both = AlbumRuleDraft.toRules(
			takenFrom = LocalDate.of(2024, 1, 1),
			takenTo = LocalDate.of(2024, 12, 31),
		)
		val condition = both["all"]!!.jsonArray.first().jsonObject
		assertEquals("taken_at", condition["field"]?.jsonPrimitive?.content)
		assertEquals("between", condition["op"]?.jsonPrimitive?.content)
		val value = condition["value"] as JsonArray
		assertEquals(2, value.size)
		assertTrue(value[0].jsonPrimitive.content < value[1].jsonPrimitive.content)

		val fromOnly = AlbumRuleDraft.toRules(takenFrom = LocalDate.of(2024, 1, 1))
		assertEquals(
			"gte",
			fromOnly["all"]!!.jsonArray.first().jsonObject["op"]?.jsonPrimitive?.content,
		)

		val toOnly = AlbumRuleDraft.toRules(uploadedTo = LocalDate.of(2024, 12, 31))
		val toCondition = toOnly["all"]!!.jsonArray.first().jsonObject
		assertEquals("backed_up_at", toCondition["field"]?.jsonPrimitive?.content)
		assertEquals("lte", toCondition["op"]?.jsonPrimitive?.content)
	}

	@Test
	fun `location and media type compile like the flutter builder`() {
		val rules = AlbumRuleDraft.toRules(
			latitude = 45.07,
			longitude = 7.68,
			radiusM = 5000.0,
			mediaType = "video",
		)
		val conditions = rules["all"]!!.jsonArray.map { it.jsonObject }
		assertEquals(2, conditions.size)
		val location = conditions[0]
		assertEquals("location", location["field"]?.jsonPrimitive?.content)
		assertEquals("within", location["op"]?.jsonPrimitive?.content)
		val value = location["value"]!!.jsonObject
		assertEquals(45.07, value["lat"]?.jsonPrimitive?.content?.toDouble() ?: 0.0, 0.0001)
		assertEquals(5000, value["radius_m"]?.jsonPrimitive?.content?.toInt())
		assertEquals("media_type", conditions[1]["field"]?.jsonPrimitive?.content)
		assertEquals("video", conditions[1]["value"]?.jsonPrimitive?.content)
	}

	@Test
	fun `empty drafts and round trips`() {
		assertTrue(AlbumRuleDraft.toRules().isEmpty())
		val rules = AlbumRuleDraft.toRules(
			takenFrom = LocalDate.of(2024, 5, 1),
			takenTo = LocalDate.of(2024, 5, 31),
			mediaType = "image",
		)
		val restored = AlbumRuleDraft.fromRules(rules)
		assertEquals(LocalDate.of(2024, 5, 1), restored.takenFrom)
		assertEquals(LocalDate.of(2024, 5, 31), restored.takenTo)
		assertEquals("image", restored.mediaType)
		assertEquals(rules, restored.toRules())
	}

	@Test
	fun `existing rules with any group are still read`() {
		val payload = JsonObject(
			mapOf(
				"any" to JsonArray(
					listOf(
						JsonObject(
							mapOf(
								"field" to kotlinx.serialization.json.JsonPrimitive("media_type"),
								"op" to kotlinx.serialization.json.JsonPrimitive("eq"),
								"value" to kotlinx.serialization.json.JsonPrimitive("video"),
							),
						),
					),
				),
			),
		)
		val state = AlbumRuleDraft.fromRules(payload)
		assertEquals("video", state.mediaType)
	}
}
