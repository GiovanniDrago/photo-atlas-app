package dev.giovannidrago.photoatlas.studio.domain.gallery

import dev.giovannidrago.photoatlas.studio.data.remote.Iso
import dev.giovannidrago.photoatlas.studio.data.remote.MediaItemDto
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class ExportItem(
	val id: String,
	val name: String,
	@SerialName("media_type") val mediaType: String,
	val mime: String? = null,
	@SerialName("size_bytes") val sizeBytes: Long? = null,
	@SerialName("taken_at") val takenAt: String? = null,
	@SerialName("file_created_at") val fileCreatedAt: String? = null,
	@SerialName("modified_at") val modifiedAt: String? = null,
	val latitude: Double? = null,
	val longitude: Double? = null,
	@SerialName("has_gps") val hasGps: Boolean = false,
	val width: Int? = null,
	val height: Int? = null,
	@SerialName("duration_s") val durationS: Double? = null,
	@SerialName("metadata_status") val metadataStatus: String = "none",
	val source: String? = null,
	@SerialName("source_kind") val sourceKind: String? = null,
	@SerialName("external_key") val externalKey: String = "",
	val path: String? = null,
	@SerialName("backup_status") val backupStatus: String = "none",
)

@Serializable
data class MetadataExportDocument(
	@SerialName("exported_at") val exportedAt: String,
	val count: Int,
	val items: List<ExportItem>,
)

/** JSON export of the indexed metadata, same fields as the Flutter app. */
object MetadataExport {
	private val json = Json { prettyPrint = true }

	fun build(items: List<MediaItemDto>, exportedAtMs: Long): String {
		val document = MetadataExportDocument(
			exportedAt = Iso.text(exportedAtMs) ?: "",
			count = items.size,
			items = items.map { item ->
				ExportItem(
					id = item.id,
					name = item.name,
					mediaType = item.mediaType,
					mime = item.mime,
					sizeBytes = item.sizeBytes,
					takenAt = item.takenAt,
					fileCreatedAt = item.fileCreatedAt,
					modifiedAt = item.modifiedAt,
					latitude = item.lat,
					longitude = item.lon,
					hasGps = item.hasGps,
					width = item.width,
					height = item.height,
					durationS = item.durationS,
					metadataStatus = item.metadataStatus,
					source = item.sourceLabel,
					sourceKind = item.sourceKind,
					externalKey = item.externalKey,
					path = item.path,
					backupStatus = item.backupStatus,
				)
			},
		)
		return json.encodeToString(document)
	}
}
