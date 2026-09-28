package dev.giovannidrago.photoatlas.studio.domain.gallery

import dev.giovannidrago.photoatlas.studio.data.remote.AlbumDto
import dev.giovannidrago.photoatlas.studio.data.remote.AlbumRulesDto
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonPrimitive

/** Builds and reads the smart-album rule tree (same JSON as the Flutter app). */
object AlbumRuleDraft {
	/** `{all:[{field,op,value}]}`, dates as UTC ISO 8601 with inclusive end. */
	fun toRules(
		takenFrom: LocalDate? = null,
		takenTo: LocalDate? = null,
		uploadedFrom: LocalDate? = null,
		uploadedTo: LocalDate? = null,
		latitude: Double? = null,
		longitude: Double? = null,
		radiusM: Double? = null,
		mediaType: String = "all",
	): AlbumRulesDto {
		val rules = mutableListOf<JsonObject>()
		rules += dateRules("taken_at", takenFrom, takenTo)
		rules += dateRules("backed_up_at", uploadedFrom, uploadedTo)
		if (latitude != null && longitude != null && radiusM != null) {
			rules += JsonObject(
				mapOf(
					"field" to JsonPrimitive("location"),
					"op" to JsonPrimitive("within"),
					"value" to JsonObject(
						mapOf(
							"lat" to JsonPrimitive(latitude),
							"lon" to JsonPrimitive(longitude),
							"radius_m" to JsonPrimitive(radiusM.toInt()),
						),
					),
				),
			)
		}
		if (mediaType == "image" || mediaType == "video") {
			rules += JsonObject(
				mapOf(
					"field" to JsonPrimitive("media_type"),
					"op" to JsonPrimitive("eq"),
					"value" to JsonPrimitive(mediaType),
				),
			)
		}
		if (rules.isEmpty()) return JsonObject(emptyMap())
		return JsonObject(mapOf("all" to JsonArray(rules)))
	}

	private fun dateRules(
		field: String,
		from: LocalDate?,
		to: LocalDate?,
	): List<JsonObject> {
		val start = from?.let { atStartOfDayUtc(it) }
		val end = to?.let { atEndOfDayUtc(it) }
		return when {
			start != null && end != null -> listOf(
				JsonObject(
					mapOf(
						"field" to JsonPrimitive(field),
						"op" to JsonPrimitive("between"),
						"value" to JsonArray(listOf(JsonPrimitive(start), JsonPrimitive(end))),
					),
				),
			)

			start != null -> listOf(
				JsonObject(
					mapOf(
						"field" to JsonPrimitive(field),
						"op" to JsonPrimitive("gte"),
						"value" to JsonPrimitive(start),
					),
				),
			)

			end != null -> listOf(
				JsonObject(
					mapOf(
						"field" to JsonPrimitive(field),
						"op" to JsonPrimitive("lte"),
						"value" to JsonPrimitive(end),
					),
				),
			)

			else -> emptyList()
		}
	}

	/** Restores the builder fields from saved rules (last value per field wins). */
	fun fromRules(rules: JsonObject?): AlbumRuleState {
		var state = AlbumRuleState()
		val group = rules?.get("all") ?: rules?.get("any")
		val conditions = (group as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()
		for (condition in conditions) {
			val field = condition["field"]?.jsonPrimitive?.content ?: continue
			val op = condition["op"]?.jsonPrimitive?.content ?: continue
			val value = condition["value"]
			when (field) {
				"taken_at", "backed_up_at" -> {
					val (from, to) = readDates(op, value)
					state = if (field == "taken_at") {
						state.copy(takenFrom = from, takenTo = to)
					} else {
						state.copy(uploadedFrom = from, uploadedTo = to)
					}
				}

				"location" -> {
					val objectValue = value as? JsonObject ?: continue
					state = state.copy(
						latitude = objectValue["lat"]?.jsonPrimitive?.double,
						longitude = objectValue["lon"]?.jsonPrimitive?.double,
						radiusM = objectValue["radius_m"]?.jsonPrimitive?.double,
					)
				}

				"media_type" -> {
					val text = value?.jsonPrimitive?.content ?: continue
					state = state.copy(mediaType = text)
				}
			}
		}
		return state
	}

	private fun readDates(op: String, value: kotlinx.serialization.json.JsonElement?): Pair<LocalDate?, LocalDate?> {
		return when (op) {
			"between" -> {
				val array = value as? JsonArray ?: return null to null
				val from = array.getOrNull(0)?.jsonPrimitive?.content?.let(::dateOf)
				val to = array.getOrNull(1)?.jsonPrimitive?.content?.let(::dateOf)
				from to to
			}

			"gte" -> dateOf(value?.jsonPrimitive?.content) to null
			"lte" -> null to dateOf(value?.jsonPrimitive?.content)
			else -> null to null
		}
	}

	private fun dateOf(iso: String?): LocalDate? {
		if (iso.isNullOrBlank()) return null
		return runCatching {
			Instant.parse(iso).atZone(ZoneId.systemDefault()).toLocalDate()
		}.getOrNull()
	}

	private fun atStartOfDayUtc(date: LocalDate): String =
		date.atStartOfDay(ZoneId.systemDefault()).toInstant().toString()

	private fun atEndOfDayUtc(date: LocalDate): String =
		date.atTime(23, 59, 59, 999_000_000)
			.atZone(ZoneId.systemDefault())
			.toInstant()
			.toString()
}

/** Editable state of the smart-album builder. */
data class AlbumRuleState(
	val takenFrom: LocalDate? = null,
	val takenTo: LocalDate? = null,
	val uploadedFrom: LocalDate? = null,
	val uploadedTo: LocalDate? = null,
	val latitude: Double? = null,
	val longitude: Double? = null,
	val radiusM: Double? = null,
	val mediaType: String = "all",
) {
	val hasLocation: Boolean
		get() = latitude != null && longitude != null && radiusM != null

	val isEmpty: Boolean
		get() = takenFrom == null && takenTo == null &&
			uploadedFrom == null && uploadedTo == null &&
			!hasLocation && mediaType == "all"

	fun toRules(): AlbumRulesDto = AlbumRuleDraft.toRules(
		takenFrom = takenFrom,
		takenTo = takenTo,
		uploadedFrom = uploadedFrom,
		uploadedTo = uploadedTo,
		latitude = latitude,
		longitude = longitude,
		radiusM = radiusM,
		mediaType = mediaType,
	)

}

/** Album with its parsed builder state (for the header and the editor). */
data class AlbumUi(
	val album: AlbumDto,
	val rules: AlbumRuleState,
)

fun AlbumDto.toUi(): AlbumUi = AlbumUi(album = this, rules = AlbumRuleDraft.fromRules(rules))
