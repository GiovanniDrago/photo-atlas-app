package dev.giovannidrago.photoatlas.studio.ui.bootstrap

import dev.giovannidrago.photoatlas.studio.data.discovery.ServerDiscovery
import dev.giovannidrago.photoatlas.studio.data.local.SettingsStore
import dev.giovannidrago.photoatlas.studio.data.remote.ApiException
import dev.giovannidrago.photoatlas.studio.data.remote.ConnectionException
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.data.remote.SupabaseConfigStore
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
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
 * restores the stored session. Runs at startup and whenever the address
 * changes.
 */
@Singleton
class BootstrapController @Inject constructor(
	private val settings: SettingsStore,
	private val discovery: ServerDiscovery,
	private val api: PhotoAtlasClient,
	private val supabase: SupabaseConfigStore,
	private val auth: AuthRepository,
) {
	private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
	private val _state = MutableStateFlow<BootstrapState>(BootstrapState.Loading)
	val state: StateFlow<BootstrapState> = _state.asStateFlow()

	fun bootstrap(prefer: String? = null, scanLan: Boolean = false) {
		scope.launch {
			_state.value = BootstrapState.Loading
			try {
				discovery.detectAndSave(prefer = prefer, scanLan = scanLan)
					?: throw ConnectionException("No reachable API server")
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
}
