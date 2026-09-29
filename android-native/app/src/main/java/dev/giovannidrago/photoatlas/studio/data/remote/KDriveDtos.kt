package dev.giovannidrago.photoatlas.studio.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class KDriveAccountDto(
	val id: String = "",
	val label: String? = null,
	@SerialName("drive_id") val driveId: Long = 0,
	@SerialName("created_at") val createdAt: String? = null,
)

@Serializable
data class KDriveStatusResponse(
	val connected: Boolean = false,
	val account: KDriveAccountDto? = null,
)

@Serializable
data class ConnectKDriveBody(
	val token: String,
	@SerialName("drive_id") val driveId: String,
	val label: String? = null,
)

@Serializable
data class ConnectKDriveResponse(val account: KDriveAccountDto = KDriveAccountDto())

@Serializable
data class KDriveFolderDto(val id: Long = 0, val name: String = "")

@Serializable
data class KDriveFoldersResponse(
	@SerialName("parent_id") val parentId: Long = 1,
	val folders: List<KDriveFolderDto> = emptyList(),
	val cursor: String? = null,
	@SerialName("has_more") val hasMore: Boolean = false,
)

@Serializable
data class KDriveScanBody(
	@SerialName("folder_id") val folderId: Long,
	@SerialName("include_subfolders") val includeSubfolders: Boolean,
	val label: String? = null,
)

@Serializable
data class KDriveScanResponse(
	@SerialName("scan_run_id") val scanRunId: String = "",
	@SerialName("source_id") val sourceId: String = "",
	@SerialName("include_subfolders") val includeSubfolders: Boolean = true,
)

@Serializable
data class ScanRunDto(
	val id: String = "",
	@SerialName("source_id") val sourceId: String = "",
	val status: String = "running",
	@SerialName("files_seen") val filesSeen: Int = 0,
	@SerialName("files_indexed") val filesIndexed: Int = 0,
	@SerialName("files_skipped") val filesSkipped: Int = 0,
	val errors: List<String> = emptyList(),
	@SerialName("finished_at") val finishedAt: String? = null,
) {
	val finished: Boolean get() = status in setOf("completed", "failed", "cancelled")
}

@Serializable
data class ScanRunResponse(val scan_run: ScanRunDto = ScanRunDto())

@Serializable
data class KDriveEnrichBody(val limit: Int = 50)

@Serializable
data class KDriveEnrichStateDto(
	val running: Boolean = false,
	val processed: Int = 0,
	val updated: Int = 0,
	val errors: List<String> = emptyList(),
)

@Serializable
data class KDrivePreviewStateDto(
	val running: Boolean = false,
	val processed: Int = 0,
	val updated: Int = 0,
	val skipped: Int = 0,
	val errors: List<String> = emptyList(),
)
