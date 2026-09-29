package dev.giovannidrago.photoatlas.studio.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DeviceDto(val id: String = "")

@Serializable
data class DeviceResponse(val device: DeviceDto = DeviceDto())

@Serializable
data class RegisterDeviceBody(
	val fingerprint: String,
	val name: String,
	val platform: String,
)

@Serializable
data class MediaSourceDto(
	val id: String = "",
	val kind: String = "",
	val label: String = "",
	@SerialName("root_path") val rootPath: String? = null,
	@SerialName("album_key") val albumKey: String? = null,
	@SerialName("device_id") val deviceId: String? = null,
	@SerialName("kdrive_drive_id") val kdriveDriveId: Long? = null,
	@SerialName("kdrive_folder_id") val kdriveFolderId: Long? = null,
	@SerialName("include_subfolders") val includeSubfolders: Boolean = true,
	@SerialName("item_count") val itemCount: Int = 0,
	@SerialName("auto_backup") val autoBackup: Boolean = false,
	@SerialName("backup_folder_path") val backupFolderPath: String? = null,
	@SerialName("last_scan_at") val lastScanAt: String? = null,
) {
	val isKDrive: Boolean get() = kind == "kdrive"
}

@Serializable
data class SourcesResponse(val sources: List<MediaSourceDto> = emptyList())

@Serializable
data class CreateSourceRequest(
	val kind: String,
	val label: String,
	@SerialName("root_path") val rootPath: String? = null,
	@SerialName("device_id") val deviceId: String? = null,
	@SerialName("album_key") val albumKey: String? = null,
)

@Serializable
data class CreateSourceResponse(val source: MediaSourceDto = MediaSourceDto())

/** One indexed device file, as accepted by POST /api/media/batch. */
@Serializable
data class BatchItem(
	@SerialName("external_key") val externalKey: String,
	val path: String? = null,
	val name: String,
	val mime: String,
	@SerialName("media_type") val mediaType: String,
	@SerialName("size_bytes") val sizeBytes: Long,
	@SerialName("taken_at") val takenAt: String? = null,
	@SerialName("file_created_at") val fileCreatedAt: String? = null,
	@SerialName("modified_at") val modifiedAt: String? = null,
	val lat: Double? = null,
	val lon: Double? = null,
	val width: Int? = null,
	val height: Int? = null,
	@SerialName("duration_s") val durationS: Double? = null,
	@SerialName("thumbnail_b64") val thumbnailB64: String? = null,
)

@Serializable
data class BatchMediaRequest(
	@SerialName("source_id") val sourceId: String,
	@SerialName("scan_run_id") val scanRunId: String? = null,
	val items: List<BatchItem>,
)

@Serializable
data class BatchItemResponse(
	val id: String = "",
	@SerialName("external_key") val externalKey: String = "",
)

@Serializable
data class BatchMediaResponse(
	val indexed: Int = 0,
	val items: List<BatchItemResponse> = emptyList(),
)

@Serializable
data class DeleteMediaRequest(
	val ids: List<String>,
	val cloud: Boolean,
	val index: Boolean,
)

@Serializable
data class DeleteFailure(val id: String = "", val error: String = "")

@Serializable
data class DeleteMediaResponse(
	val deleted: Int = 0,
	@SerialName("cloud_deleted") val cloudDeleted: Int = 0,
	val reset: Int = 0,
	val failed: List<DeleteFailure> = emptyList(),
)
