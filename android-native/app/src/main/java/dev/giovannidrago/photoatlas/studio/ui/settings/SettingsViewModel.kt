package dev.giovannidrago.photoatlas.studio.ui.settings

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
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
	var result by mutableStateOf<ServerResult?>(null)
		private set

	init {
		viewModelScope.launch {
			serverUrl = settingsStore.currentApiBaseUrl()
		}
	}

	fun onServerUrlChange(value: String) {
		serverUrl = value
	}

	fun save() {
		viewModelScope.launch {
			settingsStore.setApiBaseUrl(serverUrl)
			result = ServerResult.Saved
			bootstrap.bootstrap(prefer = serverUrl)
		}
	}

	fun detect() {
		viewModelScope.launch {
			detecting = true
			val found = discovery.detectAndSave(prefer = serverUrl, scanLan = true)
			detecting = false
			if (found != null) {
				serverUrl = found
				result = ServerResult.Found(found)
				bootstrap.bootstrap(prefer = found)
			} else {
				result = ServerResult.NotFound
			}
		}
	}

	fun clearResult() {
		result = null
	}
}
