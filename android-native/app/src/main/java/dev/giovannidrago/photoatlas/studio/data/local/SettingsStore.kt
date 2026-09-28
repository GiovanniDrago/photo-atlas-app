package dev.giovannidrago.photoatlas.studio.data.local

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.giovannidrago.photoatlas.studio.data.discovery.ServerCandidates
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(name = "studio_settings")

@Singleton
class SettingsStore @Inject constructor(
	@ApplicationContext private val context: Context,
) : ApiBaseUrlProvider {
	val apiBaseUrl: Flow<String> = context.settingsDataStore.data.map { preferences ->
		preferences[ApiBaseUrlKey] ?: ServerCandidates.DefaultApiBaseUrl
	}

	override suspend fun currentApiBaseUrl(): String = apiBaseUrl.first()

	override suspend fun setApiBaseUrl(value: String) {
		val normalized = ServerCandidates.normalize(value)
		context.settingsDataStore.edit { preferences ->
			preferences[ApiBaseUrlKey] = normalized
		}
	}

	/** Stable per-installation device fingerprint (registered on the API). */
	suspend fun deviceFingerprint(): String {
		val existing = context.settingsDataStore.data.first()[DeviceFingerprintKey]
		if (!existing.isNullOrBlank()) return existing
		val generated = buildString {
			val random = java.security.SecureRandom()
			repeat(16) { append("%02x".format(random.nextInt(256))) }
		}
		context.settingsDataStore.edit { it[DeviceFingerprintKey] = generated }
		return generated
	}

	suspend fun deviceId(): String? =
		context.settingsDataStore.data.first()[DeviceIdKey]?.takeIf { it.isNotBlank() }

	suspend fun setDeviceId(value: String) {
		context.settingsDataStore.edit { it[DeviceIdKey] = value }
	}

	private companion object {
		val ApiBaseUrlKey = stringPreferencesKey("api_base_url")
		val DeviceFingerprintKey = stringPreferencesKey("device_fingerprint")
		val DeviceIdKey = stringPreferencesKey("device_id")
	}
}
