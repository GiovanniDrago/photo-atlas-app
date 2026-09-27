package dev.giovannidrago.photoatlas.studio.data.remote

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Supabase URL and publishable key handed to the app by GET /api/config. */
@Singleton
class SupabaseConfigStore @Inject constructor() {
	private val _config = MutableStateFlow<ApiConfigDto?>(null)
	val config: StateFlow<ApiConfigDto?> = _config.asStateFlow()

	fun set(value: ApiConfigDto) {
		_config.value = value
	}

	fun clear() {
		_config.value = null
	}
}
