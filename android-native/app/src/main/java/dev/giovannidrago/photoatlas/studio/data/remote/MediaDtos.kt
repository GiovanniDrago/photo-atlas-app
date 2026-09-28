package dev.giovannidrago.photoatlas.studio.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class MediaItemDto(
	val id: String = "",
	@SerialName("source_id") val sourceId: String = "",
	@SerialName("external_key") val externalKey: String = "",
	val path: String? = null,
	val name: String = "",
	val mime: String? = null,
	@SerialName("media_type") val mediaType: String = "image",
	@SerialName("size_bytes") val sizeBytes: Long? = null,
	@SerialName("taken_at") val takenAt: String? = null,
	@SerialName("file_created_at") val fileCreatedAt: String? = null,
	@SerialName("modified_at") val modifiedAt: String? = null,
	val lat: Double? = null,
	val lon: Double? = null,
	@SerialName("has_gps") val hasGps: Boolean = false,
	@SerialName("metadata_status") val metadataStatus: String = "none",
	val width: Int? = null,
	val height: Int? = null,
	@SerialName("duration_s") val durationS: Double? = null,
	@SerialName("source_kind") val sourceKind: String? = null,
	@SerialName("source_label") val sourceLabel: String? = null,
	@SerialName("thumbnail_url") val thumbnailUrl: String? = null,
	@SerialName("download_url") val downloadUrl: String? = null,
	@SerialName("backup_status") val backupStatus: String = "none",
	@SerialName("kdrive_file_id") val kdriveFileId: Long? = null,
	@SerialName("backed_up_at") val backedUpAt: String? = null,
	@SerialName("backup_error") val backupError: String? = null,
) {
	val isVideo: Boolean get() = mediaType == "video"
	val isUploaded: Boolean get() = backupStatus == "uploaded"
	val isBackupFailed: Boolean get() = backupStatus == "failed"
	val hasFullMetadata: Boolean get() = metadataStatus == "full"
	val isKDriveSource: Boolean get() = sourceKind == "kdrive"

	val takenAtMs: Long? get() = Iso.date(takenAt)
	val fileCreatedAtMs: Long? get() = Iso.date(fileCreatedAt)
	val modifiedAtMs: Long? get() = Iso.date(modifiedAt)
	val backedUpAtMs: Long? get() = Iso.date(backedUpAt)
}

@Serializable
data class MediaPageDto(
	val items: List<MediaItemDto> = emptyList(),
	val total: Int = 0,
	val limit: Int = 100,
	val offset: Int = 0,
)
