package dev.giovannidrago.photoatlas.studio.domain.gallery

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Shared state of the in-app upload run: the gallery, the folder switch and the
 * album retries all drive it, and the UI renders one progress bar. M5 will
 * extend it with the background job.
 */
@Singleton
class UploadRunner @Inject constructor() {
	private val _state = MutableStateFlow<GalleryUploadState?>(null)
	val state: StateFlow<GalleryUploadState?> = _state.asStateFlow()
	private var cancelled = false
	private var throttle = FileProgressThrottle()

	fun begin(label: String, targets: List<GalleryEntry>): GalleryUploadState {
		cancelled = false
		throttle = FileProgressThrottle()
		val value = GalleryUploadState(label = label, targets = targets, total = targets.size)
		_state.value = value
		return value
	}

	fun record(progress: GalleryActionProgress) {
		if (throttle.shouldEmit(progress)) {
			_state.value = _state.value?.record(progress)
		}
	}

	fun finish(result: GalleryActionResult) {
		_state.value = _state.value?.finish(
			uploaded = result.uploaded,
			failed = result.failed,
			cancelled = cancelled,
		)
	}

	fun cancel() {
		cancelled = true
		_state.value = _state.value?.markStopping()
	}

	fun dismiss() {
		_state.value = null
	}

	fun isCancelled(): Boolean = cancelled

	val isRunning: Boolean get() = _state.value?.running == true
}
