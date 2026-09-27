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

	private companion object {
		val ApiBaseUrlKey = stringPreferencesKey("api_base_url")
	}
}
