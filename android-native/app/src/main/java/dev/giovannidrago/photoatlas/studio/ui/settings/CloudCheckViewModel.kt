package dev.giovannidrago.photoatlas.studio.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.giovannidrago.photoatlas.studio.data.local.ApiBaseUrlProvider
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** One step of the cloud self check, so the UI can show a localized label. */
enum class CloudCheckStep { Server, Account, KDrive, Sources, Totals, Uploaded, Clusters }

data class CloudCheckResult(
	val step: CloudCheckStep,
	val ok: Boolean,
	val detail: String,
)

data class CloudCheckState(
	val running: Boolean = false,
	val results: List<CloudCheckResult> = emptyList(),
)

/**
 * Read-only self check of the cloud chain: server address, account, kDrive,
 * sources, totals, uploaded items and clusters. Used to diagnose why cloud
 * content is not visible on a device, without showing any secret.
 */
@HiltViewModel
class CloudCheckViewModel @Inject constructor(
	private val api: PhotoAtlasClient,
	private val baseUrls: ApiBaseUrlProvider,
) : ViewModel() {
	private val _state = MutableStateFlow(CloudCheckState())
	val state: StateFlow<CloudCheckState> = _state.asStateFlow()

	fun run() {
		if (_state.value.running) return
		viewModelScope.launch {
			_state.value = CloudCheckState(running = true, results = emptyList())
			val results = mutableListOf<CloudCheckResult>()
			suspend fun step(step: CloudCheckStep, block: suspend () -> String) {
				val result = runCatching { block() }
					.map { CloudCheckResult(step, ok = true, detail = it) }
					.getOrElse { CloudCheckResult(step, ok = false, detail = it.message ?: "error") }
				results += result
				_state.value = CloudCheckState(running = true, results = results.toList())
			}
			step(CloudCheckStep.Server) { baseUrls.currentApiBaseUrl() }
			step(CloudCheckStep.Account) { api.me().email.ifBlank { "(no email)" } }
			step(CloudCheckStep.KDrive) {
				val status = api.kdriveStatus()
				"connected=${status.connected} drive=${status.account?.driveId ?: "-"}"
			}
			step(CloudCheckStep.Sources) {
				val sources = api.sources()
				"total=${sources.size} local=${sources.count { it.kind == "local" }} " +
					"kdrive=${sources.count { it.isKDrive }}"
			}
			step(CloudCheckStep.Totals) {
				val totals = api.backupStatusFull().totals
				"total=${totals.total} uploaded=${totals.uploaded} " +
					"pending=${totals.pending} failed=${totals.failed}"
			}
			step(CloudCheckStep.Uploaded) {
				"total=${api.media(backupStatus = "uploaded", limit = 1).total}"
			}
			step(CloudCheckStep.Clusters) {
				"clusters=" + api.clusters(
					west = -180.0,
					south = -90.0,
					east = 180.0,
					north = 90.0,
					zoom = 1,
				).size
			}
			_state.value = CloudCheckState(running = false, results = results.toList())
		}
	}
}
