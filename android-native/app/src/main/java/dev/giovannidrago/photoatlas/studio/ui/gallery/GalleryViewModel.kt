package dev.giovannidrago.photoatlas.studio.ui.gallery

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMedia
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaSource
import dev.giovannidrago.photoatlas.studio.data.device.DeviceShareService
import dev.giovannidrago.photoatlas.studio.data.device.DeviceTrashService
import dev.giovannidrago.photoatlas.studio.data.remote.AlbumDto
import dev.giovannidrago.photoatlas.studio.data.remote.MediaItemDto
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.domain.gallery.DeleteOptions
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryActionsService
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryFilter
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryUploadState
import dev.giovannidrago.photoatlas.studio.domain.gallery.SourceMatcher
import dev.giovannidrago.photoatlas.studio.domain.gallery.UploadRunner
import dev.giovannidrago.photoatlas.studio.domain.gallery.galleryEntryMatches
import dev.giovannidrago.photoatlas.studio.domain.gallery.mergeGalleryEntries
import dev.giovannidrago.photoatlas.studio.domain.gallery.planDelete
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class GalleryState(
	val entries: List<GalleryEntry> = emptyList(),
	val filter: GalleryFilter = GalleryFilter(),
	val cloudTotal: Int = 0,
	val deviceTotal: Int = 0,
	val cloudLoading: Boolean = true,
	val deviceLoading: Boolean = false,
	val loadingMore: Boolean = false,
	val hasMore: Boolean = false,
	val error: String? = null,
	val permissionDenied: Boolean = false,
)

/** One-shot feedback for the UI (mapped to a localized snackbar there). */
data class UiMessage(
	val kind: Kind,
	val count: Int = 0,
	val detail: String? = null,
) {
	enum class Kind { Uploaded, Deleted, Shared, Exported, Removed, Added, CoverSet, AlbumDeleted, Failed }
}

/**
 * Gallery controller for the three scopes (tab, device folder, user album):
 * loads the indexed items (paged) and the device side, merges them and runs the
 * actions.
 */
@HiltViewModel
class GalleryViewModel @Inject constructor(
	savedStateHandle: SavedStateHandle,
	private val api: PhotoAtlasClient,
	private val device: DeviceMediaSource,
	private val actions: GalleryActionsService,
	private val shareService: DeviceShareService,
	private val trashService: DeviceTrashService,
	private val uploadRunner: UploadRunner,
) : ViewModel() {
	val scope: GalleryScope = GalleryScope.from(savedStateHandle)

	private val cloud = mutableListOf<MediaItemDto>()
	private val cloudIds = mutableSetOf<String>()
	private var cloudPage = 0
	private var cloudTotal = 0
	private var cloudDone = false
	private var deviceItems: List<DeviceMedia> = emptyList()
	private var folderPage = 0
	private var folderDone = false
	private var sourceId: String? = null
	private var deviceTotal = 0
	private var filter = GalleryFilter()
	private var generation = 0
	private var cloudError: String? = null

	private val _state = MutableStateFlow(GalleryState())
	val state: StateFlow<GalleryState> = _state.asStateFlow()

	val upload: StateFlow<GalleryUploadState?> = uploadRunner.state

	/** Album detail data (only for the user-album scope). */
	var album by mutableStateOf<AlbumDto?>(null)
		private set
	var albumFailedCount by mutableStateOf(0)
		private set

	var message by mutableStateOf<UiMessage?>(null)
		private set

	init {
		refresh(forceDevice = true)
		if (scope is GalleryScope.UserAlbum) loadAlbum()
	}

	fun setFilter(value: GalleryFilter) {
		if (value == filter) return
		filter = value
		restart(loadDevice = scope.isFolder)
	}

	fun refresh(forceDevice: Boolean = true) {
		if (forceDevice) device.invalidate()
		restart(loadDevice = scope.isFolder || scope == GalleryScope.Tab)
		if (scope is GalleryScope.UserAlbum) loadAlbum()
	}

	fun loadMore() {
		if (_state.value.cloudLoading || _state.value.loadingMore) return
		if (cloudDone && folderDone) return
		val current = generation
		_state.value = _state.value.copy(loadingMore = true)
		viewModelScope.launch {
			cloudError = null
			runCatching {
				if (!cloudDone) fetchCloud(cloudPage)
				val folderScope = scope as? GalleryScope.Folder
				if (folderScope != null && !folderDone) fetchFolderPage(folderScope.albumId)
			}.onFailure {
				if (current == generation) cloudError = it.message
			}
			if (current != generation) return@launch
			_state.value = snapshot(loadingMore = false)
		}
	}

	// --- Actions ---

	fun startUpload(entries: List<GalleryEntry>, label: String) {
		if (uploadRunner.isRunning) return
		val targets = entries.filter { it.canUpload }
		if (targets.isEmpty()) {
			message = UiMessage(UiMessage.Kind.Failed, detail = "no targets")
			return
		}
		uploadRunner.begin(label, targets)
		viewModelScope.launch {
			val result = actions.upload(
				targets,
				onProgress = uploadRunner::record,
				isCancelled = uploadRunner::isCancelled,
			)
			uploadRunner.finish(result)
			message = if (result.errors.isNotEmpty()) {
				UiMessage(UiMessage.Kind.Failed, detail = result.errors.first())
			} else {
				UiMessage(UiMessage.Kind.Uploaded, count = result.uploaded)
			}
			refresh()
		}
	}

	fun cancelUpload() = uploadRunner.cancel()

	fun dismissUpload() = uploadRunner.dismiss()

	/** System trash request for the device copies of the selection (API 30+). */
	fun trashRequest(entries: List<GalleryEntry>): android.content.IntentSender? =
		trashService.trashRequest(deviceUris(entries))

	/** Permanent delete for API 26-29, returning the ids actually removed. */
	suspend fun deleteDeviceFiles(entries: List<GalleryEntry>): Set<Long> =
		trashService.deletePermanently(deviceUris(entries))

	fun applyDelete(
		entries: List<GalleryEntry>,
		options: DeleteOptions,
		deletedLocalIds: Set<Long>,
		removeFromAlbum: Boolean = false,
	) {
		viewModelScope.launch {
			var removed = 0
			if (removeFromAlbum) {
				val albumId = (scope as? GalleryScope.UserAlbum)?.albumId
				if (albumId != null) {
					val ids = entries.mapNotNull { it.cloud?.id }
					if (ids.isNotEmpty()) {
						removed = runCatching { api.removeAlbumItems(albumId, ids) }.getOrDefault(0)
					}
				}
			}
			val plan = planDelete(
				entries = entries,
				cloud = options.cloud,
				local = options.local,
				deletedLocalIds = deletedLocalIds,
			)
			val result = actions.applyDelete(plan)
			val deletedCount = deletedLocalIds.size + result.deletedCount
			message = when {
				result.errors.isNotEmpty() && deletedCount == 0 ->
					UiMessage(UiMessage.Kind.Failed, detail = result.errors.first())

				removeFromAlbum && !options.cloud && !options.local ->
					UiMessage(UiMessage.Kind.Removed, count = removed)

				else -> UiMessage(UiMessage.Kind.Deleted, count = deletedCount)
			}
			device.invalidate()
			refresh()
		}
	}

	fun removeFromAlbum(entries: List<GalleryEntry>) {
		val albumId = (scope as? GalleryScope.UserAlbum)?.albumId ?: return
		viewModelScope.launch {
			val ids = entries.mapNotNull { it.cloud?.id }
			if (ids.isEmpty()) return@launch
			try {
				val removed = api.removeAlbumItems(albumId, ids)
				message = UiMessage(UiMessage.Kind.Removed, count = removed)
			} catch (error: Exception) {
				message = UiMessage(UiMessage.Kind.Failed, detail = error.message)
			}
			refresh()
		}
	}

	fun setCover(entry: GalleryEntry) {
		val albumId = (scope as? GalleryScope.UserAlbum)?.albumId ?: return
		val mediaId = entry.cloud?.id ?: return
		viewModelScope.launch {
			try {
				album = api.updateAlbum(albumId, coverMediaId = mediaId)
				message = UiMessage(UiMessage.Kind.CoverSet)
			} catch (error: Exception) {
				message = UiMessage(UiMessage.Kind.Failed, detail = error.message)
			}
		}
	}

	fun deleteAlbum(onDeleted: () -> Unit) {
		val albumId = (scope as? GalleryScope.UserAlbum)?.albumId ?: return
		viewModelScope.launch {
			try {
				api.deleteAlbum(albumId)
				message = UiMessage(UiMessage.Kind.AlbumDeleted)
				onDeleted()
			} catch (error: Exception) {
				message = UiMessage(UiMessage.Kind.Failed, detail = error.message)
			}
		}
	}

	fun renameAlbum(name: String, onRenamed: (AlbumDto) -> Unit) {
		val albumId = (scope as? GalleryScope.UserAlbum)?.albumId ?: return
		viewModelScope.launch {
			try {
				val updated = api.updateAlbum(albumId, name = name)
				album = updated
				onRenamed(updated)
			} catch (error: Exception) {
				message = UiMessage(UiMessage.Kind.Failed, detail = error.message)
			}
		}
	}

	/** Re-uploads the album items whose upload failed. */
	fun retryFailed(label: String, noTargetsDetail: String) {
		val albumId = (scope as? GalleryScope.UserAlbum)?.albumId ?: return
		if (uploadRunner.isRunning) return
		viewModelScope.launch {
			val page = runCatching {
				api.albumMedia(albumId, limit = 500, backupStatus = "failed")
			}.getOrElse { error ->
				message = UiMessage(UiMessage.Kind.Failed, detail = error.message)
				return@launch
			}
			if (page.items.isEmpty()) return@launch
			val locals = runCatching { device.resolveForItems(page.items) }.getOrDefault(emptyMap())
			val entries = page.items.map { item ->
				GalleryEntry(cloud = item, local = locals[item.externalKey])
			}
			if (entries.none { it.canUpload }) {
				message = UiMessage(UiMessage.Kind.Failed, detail = noTargetsDetail)
				return@launch
			}
			startUpload(entries, label)
		}
	}

	fun share(entries: List<GalleryEntry>) {
		viewModelScope.launch {
			val result = shareService.shareEntries(entries)
			message = if (result.errors.isNotEmpty()) {
				UiMessage(UiMessage.Kind.Failed, detail = result.errors.first())
			} else {
				UiMessage(UiMessage.Kind.Shared, count = result.shared)
			}
		}
	}

	fun exportMetadata(entries: List<GalleryEntry>) {
		viewModelScope.launch {
			try {
				val file = shareService.exportMetadata(entries)
				message = UiMessage(UiMessage.Kind.Exported, detail = file.absolutePath)
				shareService.shareFile(file)
			} catch (error: Exception) {
				message = UiMessage(UiMessage.Kind.Failed, detail = error.message)
			}
		}
	}

	fun reportAlbumAdd(outcome: dev.giovannidrago.photoatlas.studio.ui.albums.AlbumAddOutcome) {
		message = if (outcome.failed > 0) {
			UiMessage(UiMessage.Kind.Failed, detail = "${outcome.added} ok, ${outcome.failed} failed")
		} else {
			UiMessage(UiMessage.Kind.Added, count = outcome.added)
		}
	}

	fun consumeMessage() {
		message = null
	}

	private fun deviceUris(entries: List<GalleryEntry>): List<Uri> =
		entries.mapNotNull { entry -> entry.local?.uri?.let { Uri.parse(it) } }

	// --- Loading ---

	private fun loadAlbum() {
		val albumId = (scope as? GalleryScope.UserAlbum)?.albumId ?: return
		viewModelScope.launch {
			runCatching { api.albums().firstOrNull { it.id == albumId } }
				.getOrNull()
				?.let { album = it }
			albumFailedCount = runCatching {
				api.albumMedia(albumId, limit = 1, backupStatus = "failed").total
			}.getOrDefault(0)
		}
	}

	private fun restart(loadDevice: Boolean) {
		generation += 1
		val current = generation
		cloud.clear()
		cloudIds.clear()
		cloudPage = 0
		cloudTotal = 0
		cloudDone = false
		cloudError = null
		folderPage = 0
		folderDone = scope !is GalleryScope.Folder || !loadDevice
		if (loadDevice) deviceItems = emptyList()
		sourceId = null
		_state.value = GalleryState(filter = filter, cloudLoading = true)
		viewModelScope.launch {
			if (scope.isFolder) resolveSource()
			runCatching { fetchCloud(0) }
				.onFailure {
					if (current == generation) cloudError = it.message
				}
			if (current != generation) return@launch
			_state.value = snapshot(cloudLoading = false, deviceLoading = loadDevice)
			if (loadDevice) loadDevice(current)
		}
	}

	private suspend fun resolveSource() {
		val folderScope = scope as? GalleryScope.Folder ?: return
		sourceId = runCatching {
			val sources = api.sources()
			val folder = device.listFolders().firstOrNull { it.id == folderScope.albumId }
			SourceMatcher.findSourceForFolder(sources, folderScope.albumId, folder?.name)?.id
		}.getOrNull()
	}

	private suspend fun fetchCloud(page: Int) {
		val pageData = when (val current = scope) {
			is GalleryScope.UserAlbum ->
				api.albumMedia(current.albumId, limit = CloudPageSize, offset = page * CloudPageSize)

			is GalleryScope.Folder -> {
				val source = sourceId
				if (source == null) {
					cloudDone = true
					return
				}
				api.media(
					status = if (filter.missingOnly) "missing" else "all",
					type = filter.type,
					sourceId = source,
					backupStatus = filter.backupStatus,
					limit = CloudPageSize,
					offset = page * CloudPageSize,
				)
			}

			GalleryScope.Tab -> api.media(
				status = if (filter.missingOnly) "missing" else "all",
				type = filter.type,
				backupStatus = filter.backupStatus,
				limit = CloudPageSize,
				offset = page * CloudPageSize,
			)
		}
		if (page == 0) {
			cloud.clear()
			cloudIds.clear()
		}
		val locals = if (scope.isUserAlbum) {
			runCatching { device.resolveForItems(pageData.items) }.getOrDefault(emptyMap())
		} else {
			emptyMap()
		}
		for (item in pageData.items) {
			if (cloudIds.add(item.id)) cloud.add(item)
		}
		if (scope.isUserAlbum && pageData.items.isNotEmpty()) {
			deviceItems = mergeLocalsForAlbum(pageData.items, locals)
		}
		cloudTotal = pageData.total
		cloudPage = page + 1
		cloudDone = pageData.items.size < CloudPageSize || cloud.size >= cloudTotal
	}

	private fun mergeLocalsForAlbum(
		items: List<MediaItemDto>,
		locals: Map<String, DeviceMedia>,
	): List<DeviceMedia> {
		val known = deviceItems.associateBy { it.id }.toMutableMap()
		for (item in items) {
			locals[item.externalKey]?.let { known[it.id] = it }
		}
		return known.values.toList()
	}

	private suspend fun fetchFolderPage(albumId: String) {
		val page = device.loadFolderPage(albumId, folderPage, FolderPageSize)
		val known = deviceItems.map { it.id }.toMutableSet()
		val appended = deviceItems.toMutableList()
		for (item in page.items) {
			if (known.add(item.id)) appended += item
		}
		deviceItems = appended
		deviceTotal = page.total
		folderPage += 1
		folderDone = !page.hasMore
	}

	private suspend fun loadDevice(current: Int) {
		try {
			when (val scopeNow = scope) {
				is GalleryScope.Folder -> {
					deviceItems = emptyList()
					folderPage = 0
					fetchFolderPage(scopeNow.albumId)
					if (current != generation) return
					_state.value = snapshot(deviceLoading = false)
				}

				GalleryScope.Tab -> {
					val items = device.loadLibrary(forceRefresh = true)
					if (current != generation) return
					deviceItems = items
					deviceTotal = items.size
					_state.value = snapshot(deviceLoading = false)
				}

				is GalleryScope.UserAlbum -> {
					if (current != generation) return
					deviceTotal = deviceItems.size
					_state.value = snapshot(deviceLoading = false)
				}
			}
		} catch (_: SecurityException) {
			if (current != generation) return
			_state.value = snapshot(deviceLoading = false, permissionDenied = true)
		} catch (_: Exception) {
			if (current != generation) return
			_state.value = snapshot(deviceLoading = false)
		}
	}

	private fun snapshot(
		cloudLoading: Boolean = false,
		deviceLoading: Boolean = false,
		loadingMore: Boolean = false,
		permissionDenied: Boolean = false,
	): GalleryState {
		val entries = mergeGalleryEntries(cloud = cloud.toList(), local = deviceItems)
			.filter { galleryEntryMatches(it, filter) }
		return GalleryState(
			entries = entries,
			filter = filter,
			cloudTotal = cloudTotal,
			deviceTotal = deviceTotal,
			cloudLoading = cloudLoading,
			deviceLoading = deviceLoading,
			loadingMore = loadingMore,
			hasMore = !cloudDone || !folderDone,
			error = cloudError,
			permissionDenied = permissionDenied,
		)
	}

	private companion object {
		const val CloudPageSize = 100
		const val FolderPageSize = 120
	}
}