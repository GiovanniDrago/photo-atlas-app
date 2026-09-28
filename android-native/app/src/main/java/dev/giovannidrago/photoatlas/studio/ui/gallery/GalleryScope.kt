package dev.giovannidrago.photoatlas.studio.ui.gallery

import androidx.lifecycle.SavedStateHandle
import dev.giovannidrago.photoatlas.studio.data.remote.MediaItemDto

/** What a gallery instance shows: the whole library, a device folder or an album. */
sealed interface GalleryScope {
	data object Tab : GalleryScope

	data class Folder(val albumId: String) : GalleryScope

	data class UserAlbum(val albumId: String) : GalleryScope

	val isFolder: Boolean get() = this is Folder

	val isUserAlbum: Boolean get() = this is UserAlbum

	companion object {
		const val ArgFolderAlbumId = "folderAlbumId"
		const val ArgUserAlbumId = "userAlbumId"

		fun from(savedStateHandle: SavedStateHandle): GalleryScope {
			val userAlbum = savedStateHandle.get<String>(ArgUserAlbumId)
			if (!userAlbum.isNullOrBlank()) return UserAlbum(userAlbum)
			val folder = savedStateHandle.get<String>(ArgFolderAlbumId)
			if (!folder.isNullOrBlank()) return Folder(folder)
			return Tab
		}
	}
}

/**
 * Builds gallery entries for device-only items of a folder or album: the
 * cloud row plus its current device copy.
 */
fun entriesFromDevice(items: List<MediaItemDto>, device: Map<String, dev.giovannidrago.photoatlas.studio.data.device.DeviceMedia>): List<dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry> =
	items.map { item ->
		dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry(
			cloud = item,
			local = device[item.externalKey],
		)
	}
