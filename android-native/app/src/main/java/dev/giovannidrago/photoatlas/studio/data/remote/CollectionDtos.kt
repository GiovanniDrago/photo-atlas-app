package dev.giovannidrago.photoatlas.studio.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

@Serializable
data class UpdateSourceRequest(
	val label: String? = null,
	@SerialName("auto_backup") val autoBackup: Boolean? = null,
	@SerialName("last_scan_at") val lastScanAt: String? = null,
)

@Serializable
data class TimelineBucketDto(
	@SerialName("bucket_start") val bucketStart: String = "",
	@SerialName("bucket_end") val bucketEnd: String = "",
	val granularity: String = "month",
	val count: Int = 0,
	@SerialName("representative_id") val representativeId: String? = null,
) {
	val startMs: Long? get() = Iso.date(bucketStart)
	val endMs: Long? get() = Iso.date(bucketEnd)
}

@Serializable
data class TimelineResponse(val buckets: List<TimelineBucketDto> = emptyList())

/** Smart-album rule tree, passed through as JSON (`{all:[{field,op,value}]}`). */
typealias AlbumRulesDto = JsonObject

@Serializable
data class AlbumDto(
	val id: String = "",
	val name: String = "",
	val kind: String = "manual",
	val rules: JsonObject? = null,
	@SerialName("cover_media_id") val coverMediaId: String? = null,
	val cover: MediaItemDto? = null,
	@SerialName("item_count") val itemCount: Int = 0,
	@SerialName("created_at") val createdAt: String? = null,
	@SerialName("updated_at") val updatedAt: String? = null,
) {
	val isSmart: Boolean get() = kind == "smart"
}

@Serializable
data class AlbumsResponse(val albums: List<AlbumDto> = emptyList())

@Serializable
data class CreateAlbumRequest(
	val name: String,
	val kind: String = "manual",
	val rules: JsonObject? = null,
	@SerialName("media_ids") val mediaIds: List<String>? = null,
)

@Serializable
data class UpdateAlbumRequest(
	val name: String? = null,
	val rules: JsonObject? = null,
	@SerialName("cover_media_id") val coverMediaId: String? = null,
	@SerialName("clear_cover") val clearCover: Boolean? = null,
)

@Serializable
data class CreateAlbumResponse(val album: AlbumDto = AlbumDto())

@Serializable
data class AlbumPreviewRequest(val rules: JsonObject)

@Serializable
data class AlbumPreviewResponse(val total: Int = 0)

@Serializable
data class AlbumItemsRequest(@SerialName("media_ids") val mediaIds: List<String>)

@Serializable
data class AlbumItemsResponse(val added: Int = 0, val skipped: Int = 0)

@Serializable
data class AlbumRemovedResponse(val removed: Int = 0)

@Serializable
data class BackupSourceStatusDto(
	val id: String = "",
	val label: String = "",
	val total: Int = 0,
	val uploaded: Int = 0,
	val pending: Int = 0,
	val failed: Int = 0,
	@SerialName("auto_backup") val autoBackup: Boolean = false,
	@SerialName("backup_folder_path") val backupFolderPath: String? = null,
	@SerialName("backup_last_run_at") val backupLastRunAt: String? = null,
)

@Serializable
data class BackupStatusResponse(
	val sources: List<BackupSourceStatusDto> = emptyList(),
)
