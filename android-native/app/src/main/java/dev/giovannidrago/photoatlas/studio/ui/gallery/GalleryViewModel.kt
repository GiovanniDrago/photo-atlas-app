package dev.giovannidrago.photoatlas.studio.ui.gallery

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMedia
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaSource
import dev.giovannidrago.photoatlas.studio.data.device.DeviceShareService
import dev.giovannidrago.photoatlas.studio.data.device.DeviceTrashService
import dev.giovannidrago.photoatlas.studio.data.remote.MediaItemDto
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.domain.gallery.DeleteOptions
import dev.giovannidrago.photoatlas.studio.domain.gallery.FileProgressThrottle
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryActionsService
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryFilter
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryUploadState
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
	enum class Kind { Uploaded, Deleted, Shared, Exported, Failed }
}

/**
 * Loads the indexed items (paged) and the whole device library (one ordered
 * query), merges them and runs the gallery actions.
 */
@HiltViewModel
class GalleryViewModel @Inject constructor(
	private val api: PhotoAtlasClient,
	private val device: DeviceMediaSource,
	private val actions: GalleryActionsService,
	private val shareService: DeviceShareService,
	private val trashService: DeviceTrashService,
) : ViewModel() {
	private val cloud = mutableListOf<MediaItemDto>()
	private val cloudIds = mutableSetOf<String>()
	private var cloudPage = 0
	private var cloudTotal = 0
	private var cloudDone = false
	private var deviceItems: List<DeviceMedia> = emptyList()
	private var filter = GalleryFilter()
	private var generation = 0
	private var uploadCancelled = false

	private val _state = MutableStateFlow(GalleryState())
	val state: StateFlow<GalleryState> = _state.asStateFlow()

	private val _upload = MutableStateFlow<GalleryUploadState?>(null)
	val upload: StateFlow<GalleryUploadState?> = _upload.asStateFlow()

	var message by mutableStateOf<UiMessage?>(null)
		private set

	init {
		refresh()
	}

	fun setFilter(value: GalleryFilter) {
		if (value == filter) return
		filter = value
		restart(loadDevice = false)
	}

	fun refresh(forceDevice: Boolean = true) {
		if (forceDevice) device.invalidate()
		restart(loadDevice = true)
	}

	fun loadMore() {
		if (_state.value.cloudLoading || _state.value.loadingMore || cloudDone) return
		val current = generation
		_state.value = _state.value.copy(loadingMore = true)
		viewModelScope.launch {
			runCatching { fetchCloud(cloudPage) }
				.onFailure { if (current == generation) _state.value = _state.value.copy(error = it.message) }
			if (current != generation) return@launch
			_state.value = snapshot(loadingMore = false)
		}
	}

	// --- Actions ---

	fun startUpload(entries: List<GalleryEntry>, label: String) {
		if (_upload.value?.running == true) return
		val targets = entries.filter { it.canUpload }
		if (targets.isEmpty()) {
			message = UiMessage(UiMessage.Kind.Failed, detail = "no targets")
			return
		}
		uploadCancelled = false
		_upload.value = GalleryUploadState(
			label = label,
			targets = targets,
			total = targets.size,
		)
		viewModelScope.launch {
			val throttle = FileProgressThrottle()
			val result = actions.upload(
				targets,
				onProgress = { progress ->
					if (throttle.shouldEmit(progress)) {
						_upload.value = _upload.value?.record(progress)
					}
				},
				isCancelled = { uploadCancelled },
			)
			_upload.value = _upload.value?.finish(
				uploaded = result.uploaded,
				failed = result.failed,
				cancelled = uploadCancelled,
			)
			message = if (result.errors.isNotEmpty()) {
				UiMessage(UiMessage.Kind.Failed, detail = result.errors.first())
			} else {
				UiMessage(UiMessage.Kind.Uploaded, count = result.uploaded)
			}
			refresh()
		}
	}

	fun cancelUpload() {
		uploadCancelled = true
		_upload.value = _upload.value?.markStopping()
	}

	fun dismissUpload() {
		_upload.value = null
	}

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
	) {
		viewModelScope.launch {
			val plan = planDelete(
				entries = entries,
				cloud = options.cloud,
				local = options.local,
				deletedLocalIds = deletedLocalIds,
			)
			val result = actions.applyDelete(plan)
			val deletedCount = deletedLocalIds.size + result.deletedCount
			message = if (result.errors.isNotEmpty() && deletedCount == 0) {
				UiMessage(UiMessage.Kind.Failed, detail = result.errors.first())
			} else {
				UiMessage(UiMessage.Kind.Deleted, count = deletedCount)
			}
			device.invalidate()
			refresh()
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

	fun consumeMessage() {
		message = null
	}

	private fun deviceUris(entries: List<GalleryEntry>): List<Uri> =
		entries.mapNotNull { entry -> entry.local?.uri?.let { Uri.parse(it) } }

	// --- Loading ---

	private fun restart(loadDevice: Boolean) {
		generation += 1
		val current = generation
		cloud.clear()
		cloudIds.clear()
		cloudPage = 0
		cloudTotal = 0
		cloudDone = false
		if (loadDevice) {
			deviceItems = emptyList()
		}
		_state.value = GalleryState(filter = filter, cloudLoading = true)
		viewModelScope.launch {
			runCatching { fetchCloud(0) }
				.onFailure {
					if (current == generation) {
						_state.value = _state.value.copy(error = it.message)
					}
				}
			if (current != generation) return@launch
			_state.value = snapshot(cloudLoading = false, deviceLoading = loadDevice)
			if (loadDevice) loadDeviceItems(current)
		}
	}

	private suspend fun fetchCloud(page: Int) {
		val pageData = api.media(
			status = if (filter.missingOnly) "missing" else "all",
			type = filter.type,
			backupStatus = filter.backupStatus,
			limit = CloudPageSize,
			offset = page * CloudPageSize,
		)
		if (page == 0) {
			cloud.clear()
			cloudIds.clear()
		}
		for (item in pageData.items) {
			if (cloudIds.add(item.id)) cloud.add(item)
		}
		cloudTotal = pageData.total
		cloudPage = page + 1
		cloudDone = pageData.items.size < CloudPageSize || cloud.size >= cloudTotal
	}

	private suspend fun loadDeviceItems(current: Int) {
		try {
			val items = device.loadLibrary(forceRefresh = true)
			if (current != generation) return
			deviceItems = items
			_state.value = snapshot(deviceLoading = false)
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
			deviceTotal = deviceItems.size,
			cloudLoading = cloudLoading,
			deviceLoading = deviceLoading,
			loadingMore = loadingMore,
			hasMore = !cloudDone,
			error = null,
			permissionDenied = permissionDenied,
		)
	}

	private companion object {
		const val CloudPageSize = 100
	}
}
