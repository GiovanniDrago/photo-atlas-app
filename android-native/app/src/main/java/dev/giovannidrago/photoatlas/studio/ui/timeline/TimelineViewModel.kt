package dev.giovannidrago.photoatlas.studio.ui.timeline

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaSource
import dev.giovannidrago.photoatlas.studio.data.device.DeviceShareService
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.data.remote.TimelineBucketDto
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryActionsService
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.domain.gallery.planDelete
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class TimelineBucketState(
	val items: List<GalleryEntry> = emptyList(),
	val loading: Boolean = true,
	val error: String? = null,
)

/** One shot outcome for the screen (localized snackbar built by the UI). */
data class TimelineOutcome(
	val deleted: Int = 0,
	val failed: Int = 0,
	val shared: Int = 0,
	val error: String? = null,
)

@HiltViewModel
class TimelineViewModel @Inject constructor(
	private val api: PhotoAtlasClient,
	private val device: DeviceMediaSource,
	private val actions: GalleryActionsService,
	private val shareService: DeviceShareService,
) : ViewModel() {
	private val states = mutableMapOf<String, TimelineBucketState>()

	private val _buckets = MutableStateFlow<List<TimelineBucketDto>>(emptyList())
	val buckets: StateFlow<List<TimelineBucketDto>> = _buckets.asStateFlow()

	private val _loading = MutableStateFlow(true)
	val loading: StateFlow<Boolean> = _loading.asStateFlow()

	private val _error = MutableStateFlow<String?>(null)
	val error: StateFlow<String?> = _error.asStateFlow()

	private val _items = MutableStateFlow<Map<String, TimelineBucketState>>(emptyMap())
	val items: StateFlow<Map<String, TimelineBucketState>> = _items.asStateFlow()

	private val _outcome = MutableStateFlow<TimelineOutcome?>(null)
	val outcome: StateFlow<TimelineOutcome?> = _outcome.asStateFlow()

	init {
		refresh()
	}

	fun refresh() {
		viewModelScope.launch {
			_loading.value = true
			_error.value = null
			runCatching { api.timeline() }
				.onSuccess { buckets ->
					_buckets.value = buckets
					_loading.value = false
					states.clear()
					_items.value = emptyMap()
				}
				.onFailure {
					_error.value = it.message
					_loading.value = false
				}
		}
	}

	/** Loads one bucket page (called by the card when it appears). */
	fun loadBucket(bucket: TimelineBucketDto) {
		val key = bucket.bucketStart
		if (states[key]?.loading == false) return
		states[key] = TimelineBucketState(loading = true)
		_items.value = states.toMap()
		viewModelScope.launch {
			runCatching {
				val page = api.timelineItems(bucket.bucketStart, bucket.bucketEnd, limit = 200)
				val locals = runCatching { device.resolveForItems(page.items) }.getOrDefault(emptyMap())
				page.items.map { item -> GalleryEntry(cloud = item, local = locals[item.externalKey]) }
			}
				.onSuccess { entries ->
					states[key] = TimelineBucketState(items = entries, loading = false)
					_items.value = states.toMap()
				}
				.onFailure { error ->
					states[key] = TimelineBucketState(loading = false, error = error.message)
					_items.value = states.toMap()
				}
		}
	}

	/** Items of the bucket at [index], used by the continuous viewer. */
	suspend fun bucketEntries(index: Int): List<GalleryEntry> {
		val bucket = _buckets.value.getOrNull(index) ?: return emptyList()
		states[bucket.bucketStart]?.items?.let { cached ->
			if (cached.isNotEmpty()) return cached
		}
		return runCatching {
			val page = api.timelineItems(bucket.bucketStart, bucket.bucketEnd, limit = 200)
			val locals = runCatching { device.resolveForItems(page.items) }.getOrDefault(emptyMap())
			page.items.map { item -> GalleryEntry(cloud = item, local = locals[item.externalKey]) }
		}.getOrDefault(emptyList())
	}

	fun delete(entries: List<GalleryEntry>, cloud: Boolean) {
		viewModelScope.launch {
			val plan = planDelete(entries, cloud = cloud, local = false, deletedLocalIds = emptySet())
			val result = actions.applyDelete(plan)
			_outcome.value = if (result.errors.isNotEmpty()) {
				TimelineOutcome(failed = result.failed, error = result.errors.first())
			} else {
				TimelineOutcome(deleted = result.deletedCount)
			}
			refresh()
		}
	}

	fun share(entries: List<GalleryEntry>) {
		viewModelScope.launch {
			val result = shareService.shareEntries(entries)
			_outcome.value = if (result.errors.isNotEmpty()) {
				TimelineOutcome(error = result.errors.first())
			} else {
				TimelineOutcome(shared = result.shared)
			}
		}
	}

	fun consumeOutcome() {
		_outcome.value = null
	}
}
