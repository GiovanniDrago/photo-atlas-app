package dev.giovannidrago.photoatlas.studio.data.device

import dev.giovannidrago.photoatlas.studio.data.local.SettingsStore
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Registers this installation as a device of the account (fingerprint based). */
@Singleton
class DeviceRegistrar @Inject constructor(
	private val api: PhotoAtlasClient,
	private val settings: SettingsStore,
) {
	private val mutex = Mutex()
	private var cachedId: String? = null

	suspend fun ensureRegistered(): String = mutex.withLock {
		cachedId?.let { return it }
		val id = api.registerDevice(
			fingerprint = settings.deviceFingerprint(),
			name = "Android device",
			platform = "android",
		)
		settings.setDeviceId(id)
		cachedId = id
		return id
	}
}
