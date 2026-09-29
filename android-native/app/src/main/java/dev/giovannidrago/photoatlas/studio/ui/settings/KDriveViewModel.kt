package dev.giovannidrago.photoatlas.studio.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.giovannidrago.photoatlas.studio.data.remote.MediaSourceDto
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Progress of a kDrive folder scan (seen/indexed counters while running). */
data class KDriveScanProgress(
	val running: Boolean = true,
	val seen: Int = 0,
	val indexed: Int = 0,
	val status: String = "running",
	val error: String? = null,
)

data class KDriveState(
	val checking: Boolean = true,
	val statusError: String? = null,
	val connected: Boolean = false,
	val driveId: Long? = null,
	val sources: List<MediaSourceDto> = emptyList(),
	val connecting: Boolean = false,
	val connectError: String? = null,
	val scanning: Boolean = false,
	val scanProgress: KDriveScanProgress? = null,
	val enrichRunning: Boolean = false,
	val enrichProcessed: Int = 0,
	val enrichUpdated: Int = 0,
	val previewsRunning: Boolean = false,
	val previewsProcessed: Int = 0,
	val previewsUpdated: Int = 0,
)

/**
 * Settings → kDrive: account connection, folder scans, metadata enrichment and
 * previews, ported from the Flutter settings section.
 */
@HiltViewModel
class KDriveViewModel @Inject constructor(
	private val api: PhotoAtlasClient,
) : ViewModel() {
	private val _state = MutableStateFlow(KDriveState())
	val state: StateFlow<KDriveState> = _state.asStateFlow()

	private var scanJob: Job? = null

	init {
		refresh()
		loadEnrichState()
		loadPreviewsState()
	}

	fun refresh() {
		viewModelScope.launch {
			_state.value = _state.value.copy(checking = true, statusError = null)
			runCatching { api.kdriveStatus() }
				.onSuccess { status ->
					_state.value = _state.value.copy(
						checking = false,
						connected = status.connected,
						driveId = status.account?.driveId,
						sources = refreshSources(),
					)
				}
				.onFailure { error ->
					_state.value = _state.value.copy(
						checking = false,
						statusError = error.message,
					)
				}
		}
	}

	fun connect(token: String, driveId: String) {
		viewModelScope.launch {
			_state.value = _state.value.copy(connecting = true, connectError = null)
			runCatching { api.connectKDrive(token = token, driveId = driveId) }
				.onSuccess {
					_state.value = _state.value.copy(connecting = false)
					refresh()
				}
				.onFailure { error ->
					_state.value = _state.value.copy(
						connecting = false,
						connectError = error.message,
					)
				}
		}
	}

	/** Scans a kDrive folder and follows the scan run until it finishes. */
	fun scan(folderId: Long, includeSubfolders: Boolean, label: String? = null) {
		if (_state.value.scanning) return
		scanJob?.cancel()
		scanJob = viewModelScope.launch {
			_state.value = _state.value.copy(
				scanning = true,
				scanProgress = KDriveScanProgress(running = true),
			)
			val response = runCatching {
				api.kdriveScan(folderId, includeSubfolders, label)
			}.getOrElse { error ->
				_state.value = _state.value.copy(
					scanning = false,
					scanProgress = KDriveScanProgress(
						running = false,
						status = "failed",
						error = error.message,
					),
				)
				return@launch
			}
			while (true) {
				val run = runCatching { api.scanRun(response.scanRunId) }.getOrNull() ?: break
				_state.value = _state.value.copy(
					scanProgress = KDriveScanProgress(
						running = !run.finished,
						seen = run.filesSeen,
						indexed = run.filesIndexed,
						status = run.status,
						error = run.errors.firstOrNull(),
					),
				)
				if (run.finished) break
				delay(ScanPollMs)
			}
			_state.value = _state.value.copy(scanning = false, sources = refreshSources())
		}
	}

	fun rescan(source: MediaSourceDto) {
		scan(
			folderId = source.kdriveFolderId ?: RootFolderId,
			includeSubfolders = source.includeSubfolders,
			label = null,
		)
	}

	fun toggleSubfolders(source: MediaSourceDto, enabled: Boolean) {
		viewModelScope.launch {
			runCatching { api.updateSource(source.id, includeSubfolders = enabled) }
			_state.value = _state.value.copy(sources = refreshSources())
		}
	}

	fun deleteSource(source: MediaSourceDto) {
		viewModelScope.launch {
			runCatching { api.deleteSource(source.id) }
			_state.value = _state.value.copy(sources = refreshSources())
		}
	}

	fun enrich() {
		if (_state.value.enrichRunning) return
		viewModelScope.launch {
			_state.value = _state.value.copy(
				enrichRunning = true,
				enrichProcessed = 0,
				enrichUpdated = 0,
			)
			runCatching { api.kdriveEnrich(EnrichLimit) }
			pollEnrich()
		}
	}

	fun generatePreviews() {
		if (_state.value.previewsRunning) return
		viewModelScope.launch {
			_state.value = _state.value.copy(
				previewsRunning = true,
				previewsProcessed = 0,
				previewsUpdated = 0,
			)
			runCatching { api.kdrivePreviews() }
			pollPreviews()
		}
	}

	private fun loadEnrichState() {
		viewModelScope.launch {
			runCatching { api.kdriveEnrichState() }.onSuccess { enrich ->
				_state.value = _state.value.copy(
					enrichRunning = enrich.running,
					enrichProcessed = enrich.processed,
					enrichUpdated = enrich.updated,
				)
				if (enrich.running) pollEnrich()
			}
		}
	}

	private fun loadPreviewsState() {
		viewModelScope.launch {
			runCatching { api.kdrivePreviewsState() }.onSuccess { previews ->
				_state.value = _state.value.copy(
					previewsRunning = previews.running,
					previewsProcessed = previews.processed,
					previewsUpdated = previews.updated,
				)
				if (previews.running) pollPreviews()
			}
		}
	}

	private suspend fun pollEnrich() {
		while (true) {
			val enrich = runCatching { api.kdriveEnrichState() }.getOrNull() ?: break
			_state.value = _state.value.copy(
				enrichRunning = enrich.running,
				enrichProcessed = enrich.processed,
				enrichUpdated = enrich.updated,
			)
			if (!enrich.running) break
			delay(ScanPollMs)
		}
	}

	private suspend fun pollPreviews() {
		while (true) {
			val previews = runCatching { api.kdrivePreviewsState() }.getOrNull() ?: break
			_state.value = _state.value.copy(
				previewsRunning = previews.running,
				previewsProcessed = previews.processed,
				previewsUpdated = previews.updated,
			)
			if (!previews.running) break
			delay(PreviewPollMs)
		}
	}

	private suspend fun refreshSources(): List<MediaSourceDto> =
		runCatching { api.sources().filter { it.isKDrive } }.getOrDefault(_state.value.sources)

	companion object {
		const val RootFolderId = 1L
		private const val ScanPollMs = 2000L
		private const val PreviewPollMs = 3000L
		private const val EnrichLimit = 50
	}
}
