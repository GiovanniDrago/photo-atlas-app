package dev.giovannidrago.photoatlas.studio.data.device

/** One image or video of the device media library (MediaStore). */
data class DeviceMedia(
	val id: Long,
	val name: String,
	val uri: String,
	val mime: String?,
	val mediaType: String,
	val sizeBytes: Long?,
	val fileCreatedAtMs: Long?,
	val takenAtMs: Long?,
	val modifiedAtMs: Long?,
	val durationS: Double?,
	val width: Int?,
	val height: Int?,
	val relativePath: String?,
	val bucketId: Long?,
	val lat: Double?,
	val lon: Double?,
) {
	val isVideo: Boolean get() = mediaType == "video"
}

/** One MediaStore bucket (device folder) with its item count. */
data class DeviceFolder(
	val id: String,
	val name: String,
	val path: String,
	val count: Int,
)

/** One page of device media plus the total of the queried set. */
data class DevicePage(
	val items: List<DeviceMedia>,
	val total: Int,
	val hasMore: Boolean,
)

/** The device media library, behind an interface so the gallery is testable. */
interface DeviceMediaSource {
	suspend fun loadLibrary(forceRefresh: Boolean = false): List<DeviceMedia>

	/** Device folders (MediaStore buckets) with their item counts. */
	suspend fun listFolders(): List<DeviceFolder>

	/** One page of a single folder, newest first. */
	suspend fun loadFolderPage(albumId: String, page: Int, size: Int = 120): DevicePage

	/** The newest device files (collections preview). */
	suspend fun recent(limit: Int = 6): List<DeviceMedia>

	/**
	 * Device copies of indexed items, keyed by external key: used by the album
	 * view so upload/delete work on cloud rows.
	 */
	suspend fun resolveForItems(items: List<dev.giovannidrago.photoatlas.studio.data.remote.MediaItemDto>): Map<String, DeviceMedia>

	fun invalidate()
}
