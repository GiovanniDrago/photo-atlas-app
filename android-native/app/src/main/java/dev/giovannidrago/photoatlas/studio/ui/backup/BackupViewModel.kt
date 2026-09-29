package dev.giovannidrago.photoatlas.studio.ui.backup

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMedia
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaSource
import dev.giovannidrago.photoatlas.studio.data.remote.BackupSourceStatusDto
import dev.giovannidrago.photoatlas.studio.data.remote.BackupTotalsDto
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.domain.backup.BackupProgress
import dev.giovannidrago.photoatlas.studio.domain.backup.BackupRunResult
import dev.giovannidrago.photoatlas.studio.domain.backup.BackupService
import dev.giovannidrago.photoatlas.studio.domain.backup.VerifyProgress
import dev.giovannidrago.photoatlas.studio.domain.backup.VerifyRunResult
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class BackupScreenState(
	val loading: Boolean = true,
	val error: String? = null,
	val sources: List<BackupSourceStatusDto> = emptyList(),
	val totals: BackupTotalsDto = BackupTotalsDto(),
	val runningKind: String? = null,
	val backupProgress: BackupProgress? = null,
	val verifyProgress: VerifyProgress? = null,
	val lastBackup: BackupRunResult? = null,
	val lastVerify: VerifyRunResult? = null,
	val pickerLoading: Boolean = false,
	val pickerItems: List<DeviceMedia> = emptyList(),
	val pickerDenied: Boolean = false,
)

/** Backup screen: folder counters, backup/verify runs and manual uploads. */
@HiltViewModel
class BackupViewModel @Inject constructor(
	private val api: PhotoAtlasClient,
	private val backup: BackupService,
	private val device: DeviceMediaSource,
) : ViewModel() {
	private val _state = MutableStateFlow(BackupScreenState())
	val state: StateFlow<BackupScreenState> = _state.asStateFlow()

	private var cancelRequested = false

	init {
		refresh()
	}

	fun refresh() {
		viewModelScope.launch {
			_state.value = _state.value.copy(loading = true, error = null)
			loadStatus()
		}
	}

	fun startBackup(sourceId: String? = null) {
		if (_state.value.runningKind != null) return
		cancelRequested = false
		_state.value = _state.value.copy(
			runningKind = "backup",
			backupProgress = BackupProgress(),
			lastBackup = null,
		)
		viewModelScope.launch {
			val result = backup.runBackup(
				sourceId = sourceId,
				onProgress = { progress ->
					_state.value = _state.value.copy(backupProgress = progress)
				},
				isCancelled = { cancelRequested },
			)
			_state.value = _state.value.copy(
				runningKind = null,
				backupProgress = null,
				lastBackup = result,
			)
			loadStatus()
		}
	}

	fun startVerify(sourceId: String? = null) {
		if (_state.value.runningKind != null) return
		cancelRequested = false
		_state.value = _state.value.copy(
			runningKind = "verify",
			verifyProgress = VerifyProgress(),
			lastVerify = null,
		)
		viewModelScope.launch {
			val result = backup.runVerify(
				sourceId = sourceId,
				onProgress = { progress ->
					_state.value = _state.value.copy(verifyProgress = progress)
				},
				isCancelled = { cancelRequested },
			)
			_state.value = _state.value.copy(
				runningKind = null,
				verifyProgress = null,
				lastVerify = result,
			)
			loadStatus()
		}
	}

	fun cancel() {
		cancelRequested = true
	}

	fun loadPicker() {
		viewModelScope.launch {
			_state.value = _state.value.copy(pickerLoading = true, pickerDenied = false)
			runCatching { device.loadLibrary() }
				.onSuccess { items ->
					_state.value = _state.value.copy(pickerLoading = false, pickerItems = items)
				}
				.onFailure { error ->
					_state.value = _state.value.copy(
						pickerLoading = false,
						pickerDenied = error is SecurityException,
						error = if (error is SecurityException) null else error.message,
					)
				}
		}
	}

	fun uploadPicked(entries: List<GalleryEntry>) {
		if (_state.value.runningKind != null) return
		cancelRequested = false
		_state.value = _state.value.copy(
			runningKind = "upload",
			backupProgress = BackupProgress(),
			lastBackup = null,
			pickerItems = emptyList(),
		)
		viewModelScope.launch {
			val result = backup.uploadPicked(
				entries = entries,
				onProgress = { progress ->
					_state.value = _state.value.copy(backupProgress = progress)
				},
				isCancelled = { cancelRequested },
			)
			_state.value = _state.value.copy(
				runningKind = null,
				backupProgress = null,
				lastBackup = result,
			)
			loadStatus()
		}
	}

	fun dismissPicker() {
		_state.value = _state.value.copy(pickerItems = emptyList(), pickerDenied = false)
	}

	private suspend fun loadStatus() {
		runCatching { api.backupStatusFull() }
			.onSuccess { response ->
				_state.value = _state.value.copy(
					loading = false,
					error = null,
					sources = response.sources,
					totals = response.totals,
				)
			}
			.onFailure { error ->
				_state.value = _state.value.copy(loading = false, error = error.message)
			}
	}
}
