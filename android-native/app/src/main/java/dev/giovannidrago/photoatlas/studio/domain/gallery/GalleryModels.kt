package dev.giovannidrago.photoatlas.studio.domain.gallery

import dev.giovannidrago.photoatlas.studio.data.device.DeviceMedia
import dev.giovannidrago.photoatlas.studio.data.remote.MediaItemDto

enum class GalleryUploadFilter { All, Uploaded, Pending }

/** Gallery filters: media type, metadata completeness and backup state. */
data class GalleryFilter(
	val type: String = "all",
	val missingOnly: Boolean = false,
	val upload: GalleryUploadFilter = GalleryUploadFilter.All,
) {
	/** Value for the API `backup_status` filter, null when not restricted. */
	val backupStatus: String?
		get() = when (upload) {
			GalleryUploadFilter.Uploaded -> "uploaded"
			GalleryUploadFilter.Pending -> "none,pending,uploading,failed"
			GalleryUploadFilter.All -> null
		}
}

/** One gallery tile: the indexed record, the device file, or both. */
data class GalleryEntry(
	val cloud: MediaItemDto? = null,
	val local: DeviceMedia? = null,
) {
	companion object {
		/** Local sources use the device asset id (or the absolute path). */
		fun cloudKey(item: MediaItemDto): String =
			if (item.isKDriveSource) "kdrive:${item.externalKey}" else "local:${item.externalKey}"

		fun localKey(media: DeviceMedia): String = "local:${media.id}"
	}

	val key: String get() = cloud?.let { cloudKey(it) } ?: localKey(local!!)
	val name: String get() = cloud?.name ?: local?.name ?: ""
	val mediaType: String get() = cloud?.mediaType ?: local?.mediaType ?: "image"
	val isVideo: Boolean get() = mediaType == "video"
	val sourceLabel: String? get() = cloud?.sourceLabel
	val sizeBytes: Long? get() = cloud?.sizeBytes ?: local?.sizeBytes
	val thumbnailUrl: String? get() = cloud?.thumbnailUrl
	val backupError: String? get() = cloud?.backupError

	/** Cloud only videos have no duration in the device copy. */
	val durationS: Double? get() = local?.durationS ?: cloud?.durationS

	val sortDateMs: Long?
		get() = cloud?.takenAtMs
			?: local?.takenAtMs
			?: cloud?.fileCreatedAtMs
			?: local?.modifiedAtMs

	val isIndexed: Boolean get() = cloud != null
	val isUploaded: Boolean get() = cloud?.isUploaded == true
	val isBackupFailed: Boolean get() = cloud?.isBackupFailed == true
	val hasLocal: Boolean get() = local != null
	val isCloudOnly: Boolean get() = cloud != null && local == null
	val isLocalOnly: Boolean get() = cloud == null && local != null
	val isKDriveSource: Boolean get() = cloud?.isKDriveSource == true
	val canUpload: Boolean get() = hasLocal && !isUploaded
	val canDeleteCloud: Boolean get() = isUploaded || isKDriveSource
	val canDeleteLocal: Boolean get() = hasLocal
	val isMetadataMissing: Boolean get() = cloud != null && cloud?.hasFullMetadata == false
}

/**
 * Merges indexed items with device files, newest first. Rebuilding the device
 * media library assigns new asset ids, so indexed items are matched by name and
 * size as well to avoid showing a photo twice.
 */
fun mergeGalleryEntries(
	cloud: List<MediaItemDto>,
	local: List<DeviceMedia>,
): List<GalleryEntry> {
	val entries = LinkedHashMap<String, GalleryEntry>()
	val byNameSize = HashMap<String, String>()
	for (item in cloud) {
		val key = GalleryEntry.cloudKey(item)
		entries[key] = GalleryEntry(cloud = item, local = null)
		if (!item.isKDriveSource) {
			val size = item.sizeBytes
			if (size != null && size > 0 && item.name.isNotEmpty()) {
				byNameSize.putIfAbsent("${item.name}|$size", key)
			}
		}
	}
	for (media in local) {
		var key = GalleryEntry.localKey(media)
		if (!entries.containsKey(key)) {
			val size = media.sizeBytes
			if (size != null && size > 0 && media.name.isNotEmpty()) {
				val candidate = byNameSize["${media.name}|$size"]
				val candidateEntry = candidate?.let { entries[it] }
				if (candidate != null && candidateEntry != null && candidateEntry.local == null) {
					key = candidate
				}
			}
		}
		val existing = entries[key]
		entries[key] = GalleryEntry(cloud = existing?.cloud, local = media)
	}
	return entries.values.sortedWith(
		compareByDescending<GalleryEntry> { it.sortDateMs ?: Long.MIN_VALUE }
			.thenBy { it.name },
	)
}

fun galleryEntryMatches(entry: GalleryEntry, filter: GalleryFilter): Boolean {
	if (filter.type != "all" && entry.mediaType != filter.type) return false
	when (filter.upload) {
		GalleryUploadFilter.Uploaded -> if (!entry.isUploaded) return false
		GalleryUploadFilter.Pending -> if (entry.isUploaded) return false
		GalleryUploadFilter.All -> Unit
	}
	if (filter.missingOnly) {
		val cloud = entry.cloud ?: return false
		if (cloud.hasFullMetadata) return false
	}
	return true
}

/** Why the gallery grid has no entries, so the UI picks the right message. */
enum class GalleryEmptyReason { Uploaded, NotUploaded, Filtered, NoMedia }

fun galleryEmptyReason(filter: GalleryFilter): GalleryEmptyReason = when {
	filter.upload == GalleryUploadFilter.Uploaded -> GalleryEmptyReason.Uploaded
	filter.upload == GalleryUploadFilter.Pending -> GalleryEmptyReason.NotUploaded
	filter.type != "all" || filter.missingOnly -> GalleryEmptyReason.Filtered
	else -> GalleryEmptyReason.NoMedia
}
