package dev.giovannidrago.photoatlas.studio.ui.bootstrap

import dev.giovannidrago.photoatlas.studio.data.discovery.DetectResult
import dev.giovannidrago.photoatlas.studio.data.discovery.ServerDiscovery
import dev.giovannidrago.photoatlas.studio.data.discovery.reason
import dev.giovannidrago.photoatlas.studio.data.remote.ApiException
import dev.giovannidrago.photoatlas.studio.data.remote.ConnectionException
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.data.remote.SupabaseConfigStore
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface BootstrapState {
	data object Loading : BootstrapState

	data class Error(val message: String) : BootstrapState

	data object Ready : BootstrapState
}

/**
 * Finds the API on the LAN, loads the public Supabase configuration and then
 * restores the stored session. Starts with the app and re-runs whenever the
 * address changes (Save/Detect in the server settings).
 */
@Singleton
class BootstrapController @Inject constructor(
	private val discovery: ServerDiscovery,
	private val api: PhotoAtlasClient,
	private val supabase: SupabaseConfigStore,
	private val auth: AuthRepository,
) {
	private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
	private val _state = MutableStateFlow<BootstrapState>(BootstrapState.Loading)
	val state: StateFlow<BootstrapState> = _state.asStateFlow()
	private var job: Job? = null

	init {
		bootstrap()
	}

	fun bootstrap(prefer: String? = null, scanLan: Boolean = false, pin: Boolean = false) {
		job?.cancel()
		job = scope.launch {
			_state.value = BootstrapState.Loading
			try {
				val detected = discovery.detectAndSave(prefer = prefer, scanLan = scanLan, pin = pin)
				detected.url ?: throw ConnectionException(unreachableMessage(detected))
				val config = api.config()
				if (config.supabaseUrl.isBlank() || config.supabasePublishableKey.isBlank()) {
					throw ApiException(500, "The API did not return the Supabase configuration (/api/config)")
				}
				supabase.set(config)
				auth.restore()
				_state.value = BootstrapState.Ready
			} catch (error: Exception) {
				_state.value = BootstrapState.Error(error.message ?: error.toString())
			}
		}
	}

	private fun unreachableMessage(detected: DetectResult): String {
		val tried = detected.attempts.joinToString("; ") { outcome ->
			"${outcome.url} -> ${outcome.reason()}"
		}
		val lan = if (detected.scannedLan) "; LAN scan: no server found" else ""
		return "No reachable API server ($tried$lan)"
	}
}
