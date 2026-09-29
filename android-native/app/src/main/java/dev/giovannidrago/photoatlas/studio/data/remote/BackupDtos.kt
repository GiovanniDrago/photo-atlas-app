package dev.giovannidrago.photoatlas.studio.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class BackupTotalsDto(
	val total: Int = 0,
	val uploaded: Int = 0,
	val pending: Int = 0,
	val failed: Int = 0,
	@SerialName("bytes_uploaded") val bytesUploaded: Long = 0,
	@SerialName("bytes_total") val bytesTotal: Long = 0,
)

/** One claimed item of the backup queue (`uploading` while the app owns it). */
@Serializable
data class PendingBackupItemDto(
	val id: String = "",
	@SerialName("source_id") val sourceId: String = "",
	@SerialName("external_key") val externalKey: String = "",
	val path: String? = null,
	val name: String = "",
	val mime: String? = null,
	@SerialName("media_type") val mediaType: String = "image",
	@SerialName("size_bytes") val sizeBytes: Long? = null,
	@SerialName("backup_status") val backupStatus: String = "pending",
	@SerialName("backup_attempts") val backupAttempts: Int = 0,
	@SerialName("backup_error") val backupError: String? = null,
	@SerialName("source_label") val sourceLabel: String? = null,
)

@Serializable
data class PendingBackupResponse(val items: List<PendingBackupItemDto> = emptyList())

@Serializable
data class ReleaseClaimsRequest(val ids: List<String>)

@Serializable
data class ReleaseClaimsResponse(val released: Int = 0)

@Serializable
data class VerifyQueueItemDto(
	val id: String = "",
	@SerialName("source_id") val sourceId: String = "",
	@SerialName("external_key") val externalKey: String = "",
	val name: String = "",
	@SerialName("size_bytes") val sizeBytes: Long? = null,
	@SerialName("backup_status") val backupStatus: String = "uploaded",
	@SerialName("kdrive_file_id") val kdriveFileId: Long? = null,
	@SerialName("backed_up_at") val backedUpAt: String? = null,
	@SerialName("source_label") val sourceLabel: String? = null,
)

@Serializable
data class VerifyQueueResponse(val items: List<VerifyQueueItemDto> = emptyList())

@Serializable
data class VerifyResultDto(
	val ok: Boolean = false,
	val status: String? = null,
	val reason: String? = null,
	@SerialName("kdrive_size") val kdriveSize: Long? = null,
)

@Serializable
data class BackupRunDto(
	val id: String = "",
	val kind: String = "backup",
	val status: String = "running",
	@SerialName("source_id") val sourceId: String? = null,
	@SerialName("device_id") val deviceId: String? = null,
	@SerialName("files_seen") val filesSeen: Int = 0,
	@SerialName("files_uploaded") val filesUploaded: Int = 0,
	@SerialName("files_skipped") val filesSkipped: Int = 0,
	@SerialName("files_failed") val filesFailed: Int = 0,
	@SerialName("verified_ok") val verifiedOk: Int = 0,
	@SerialName("verified_missing") val verifiedMissing: Int = 0,
	@SerialName("bytes_uploaded") val bytesUploaded: Long = 0,
	val errors: List<String> = emptyList(),
	@SerialName("started_at") val startedAt: String? = null,
	@SerialName("finished_at") val finishedAt: String? = null,
)

@Serializable
data class BackupRunResponse(val run: BackupRunDto = BackupRunDto())

@Serializable
data class CreateBackupRunBody(
	val kind: String,
	@SerialName("source_id") val sourceId: String? = null,
	@SerialName("device_id") val deviceId: String? = null,
)

/** Null fields are omitted, so a PATCH only touches what the run changed. */
@Serializable
data class PatchBackupRunBody(
	val status: String? = null,
	@SerialName("files_seen") val filesSeen: Int? = null,
	@SerialName("files_uploaded") val filesUploaded: Int? = null,
	@SerialName("files_skipped") val filesSkipped: Int? = null,
	@SerialName("files_failed") val filesFailed: Int? = null,
	@SerialName("verified_ok") val verifiedOk: Int? = null,
	@SerialName("verified_missing") val verifiedMissing: Int? = null,
	@SerialName("bytes_uploaded") val bytesUploaded: Long? = null,
	val errors: List<String>? = null,
)
