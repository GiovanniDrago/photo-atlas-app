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
}
