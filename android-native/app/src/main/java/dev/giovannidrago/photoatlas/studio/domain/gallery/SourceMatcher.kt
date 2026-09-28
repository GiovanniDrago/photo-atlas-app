package dev.giovannidrago.photoatlas.studio.domain.gallery

import dev.giovannidrago.photoatlas.studio.data.remote.MediaSourceDto

/** Maps device folders to indexed sources (pure, tested). */
object SourceMatcher {
	const val ManualFolder = "Manual"

	/** Last folder segment of a relative path (`DCIM/Camera/` → `Camera`). */
	fun folderName(relativePath: String?): String {
		val segments = relativePath.orEmpty().split('/').filter { it.isNotBlank() }
		return segments.lastOrNull() ?: ManualFolder
	}

	fun findSource(sources: List<MediaSourceDto>, folder: String): MediaSourceDto? =
		sources.firstOrNull { source ->
			source.kind == "local" &&
				(source.label == folder || source.albumKey == "path:$folder")
		}

	/**
	 * Matches a MediaStore folder to its source, ported from the Flutter
	 * `matchSourceForFolder`: exact album id first, then the legacy
	 * `album:path:<name>` keys, then the label as a last resort.
	 */
	fun findSourceForFolder(
		sources: List<MediaSourceDto>,
		albumId: String,
		folderName: String?,
	): MediaSourceDto? {
		val local = sources.filter { it.kind == "local" }
		local.firstOrNull { source ->
			source.rootPath == "album:$albumId" || source.albumKey == "album:$albumId"
		}?.let { return it }
		if (!folderName.isNullOrBlank()) {
			local.firstOrNull { source ->
				source.rootPath == "album:path:$folderName" ||
					source.albumKey == "path:$folderName"
			}?.let { return it }
			local.firstOrNull { source ->
				source.label == folderName && (source.rootPath?.startsWith("album:") == true)
			}?.let { return it }
		}
		return null
	}
}
