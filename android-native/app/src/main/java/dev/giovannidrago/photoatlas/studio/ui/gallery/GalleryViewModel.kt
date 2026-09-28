package dev.giovannidrago.photoatlas.studio.ui.gallery

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMedia
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaSource
import dev.giovannidrago.photoatlas.studio.data.remote.MediaItemDto
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryFilter
import dev.giovannidrago.photoatlas.studio.domain.gallery.galleryEntryMatches
import dev.giovannidrago.photoatlas.studio.domain.gallery.mergeGalleryEntries
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

/**
 * Loads the indexed items (paged) and the whole device library (one ordered
 * query) and merges them, like the Flutter gallery controller.
 */
@HiltViewModel
class GalleryViewModel @Inject constructor(
	private val api: PhotoAtlasClient,
	private val device: DeviceMediaSource,
) : ViewModel() {
	private val cloud = mutableListOf<MediaItemDto>()
	private val cloudIds = mutableSetOf<String>()
	private var cloudPage = 0
	private var cloudTotal = 0
	private var cloudDone = false
	private var deviceItems: List<DeviceMedia> = emptyList()
	private var filter = GalleryFilter()
	private var generation = 0

	private val _state = MutableStateFlow(GalleryState())
	val state: StateFlow<GalleryState> = _state.asStateFlow()

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
