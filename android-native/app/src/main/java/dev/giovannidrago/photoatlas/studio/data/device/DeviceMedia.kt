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

/** The device media library, behind an interface so the gallery is testable. */
interface DeviceMediaSource {
	suspend fun loadLibrary(forceRefresh: Boolean = false): List<DeviceMedia>

	fun invalidate()
}
