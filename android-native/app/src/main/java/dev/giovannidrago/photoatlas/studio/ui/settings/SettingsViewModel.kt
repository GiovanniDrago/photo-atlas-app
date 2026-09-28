package dev.giovannidrago.photoatlas.studio.ui.settings

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.giovannidrago.photoatlas.studio.data.discovery.ProbeOutcome
import dev.giovannidrago.photoatlas.studio.data.discovery.ServerCandidates
import dev.giovannidrago.photoatlas.studio.data.discovery.ServerDiscovery
import dev.giovannidrago.photoatlas.studio.data.local.SettingsStore
import dev.giovannidrago.photoatlas.studio.ui.bootstrap.BootstrapController
import javax.inject.Inject
import kotlinx.coroutines.launch

sealed interface ServerResult {
	data class Found(val url: String) : ServerResult

	data object NotFound : ServerResult

	data object Saved : ServerResult
}

/** Server address handling shared by the login screen, the bootstrap error
 * screen and the settings tab. */
@HiltViewModel
class SettingsViewModel @Inject constructor(
	private val settingsStore: SettingsStore,
	private val discovery: ServerDiscovery,
	private val bootstrap: BootstrapController,
) : ViewModel() {
	var serverUrl by mutableStateOf("")
		private set
	var detecting by mutableStateOf(false)
		private set
	var testing by mutableStateOf(false)
		private set
	var result by mutableStateOf<ServerResult?>(null)
		private set
	var testOutcome by mutableStateOf<ProbeOutcome?>(null)
		private set
	var candidates by mutableStateOf<List<String>>(emptyList())
		private set

	init {
		viewModelScope.launch {
			serverUrl = settingsStore.currentApiBaseUrl()
			candidates = ServerCandidates.candidates(saved = serverUrl)
		}
	}

	fun onServerUrlChange(value: String) {
		serverUrl = value
		testOutcome = null
	}

	/** Saves the address and retries the whole bootstrap. */
	fun save() {
		viewModelScope.launch {
			if (serverUrl.isBlank()) {
				testOutcome = ProbeOutcome.Failure("", "empty address")
				return@launch
			}
			settingsStore.setApiBaseUrl(serverUrl)
			result = ServerResult.Saved
			testOutcome = null
			bootstrap.bootstrap(prefer = serverUrl)
		}
	}

	fun retry() = save()

	fun detect() {
		viewModelScope.launch {
			detecting = true
			testOutcome = null
			val detected = discovery.detectAndSave(prefer = serverUrl, scanLan = true)
			detecting = false
			candidates = detected.tried
			val found = detected.url
			if (found != null) {
				serverUrl = found
				result = ServerResult.Found(found)
				bootstrap.bootstrap(prefer = found)
			} else {
				result = ServerResult.NotFound
			}
		}
	}

	fun testConnection() {
		viewModelScope.launch {
			testing = true
			result = null
			testOutcome = discovery.test(serverUrl, timeoutMs = 4000)
			testing = false
		}
	}

	fun clearResult() {
		result = null
	}
}
