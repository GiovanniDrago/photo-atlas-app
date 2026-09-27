package dev.giovannidrago.photoatlas.studio.data.discovery

import dev.giovannidrago.photoatlas.studio.data.local.ApiBaseUrlProvider
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

/** Finds the API on the LAN and remembers the address that answers. */
@Singleton
class ServerDiscovery @Inject constructor(
	private val settings: ApiBaseUrlProvider,
	@Named("plain") private val client: OkHttpClient,
) {
	suspend fun isOnline(baseUrl: String, timeoutMs: Long = 2000): Boolean =
		probe(ServerCandidates.normalize(baseUrl), timeoutMs)

	/** Tries the known candidates, then (optionally) the whole private subnets. */
	suspend fun detectAndSave(prefer: String? = null, scanLan: Boolean = false): String? {
		val candidates = ServerCandidates.candidates(
			prefer = prefer,
			saved = runCatching { settings.currentApiBaseUrl() }.getOrNull(),
		)
		for (candidate in candidates) {
			if (probe(candidate, 2000)) {
				settings.setApiBaseUrl(candidate)
				return candidate
			}
		}
		if (scanLan) {
			val found = scanLan()
			if (found != null) {
				settings.setApiBaseUrl(found)
				return found
			}
		}
		return null
	}

	/** Probes `<prefix>.1-254:8787` on every private subnet of the device. */
	suspend fun scanLan(): String? {
		val prefixes = localSubnetPrefixes()
		if (prefixes.isEmpty()) return null
		val hosts = prefixes.flatMap { prefix ->
			(1..254).map { host -> "http://$prefix.$host:${ServerCandidates.Port}" }
		}
		val semaphore = Semaphore(32)
		var found: String? = null
		return coroutineScope {
			hosts.map { host ->
				async(Dispatchers.IO) {
					semaphore.withPermit {
						if (found == null && probe(host, 400)) found = host
					}
				}
			}.awaitAll()
			found
		}
	}

	/** Private /24 prefixes of the device interfaces, without duplicates. */
	fun localSubnetPrefixes(): List<String> {
		val prefixes = mutableListOf<String>()
		runCatching {
			val interfaces = NetworkInterface.getNetworkInterfaces()
			while (interfaces.hasMoreElements()) {
				val networkInterface = interfaces.nextElement()
				if (!runCatching { networkInterface.isUp }.getOrDefault(false)) continue
				val addresses = networkInterface.inetAddresses
				while (addresses.hasMoreElements()) {
					val address = addresses.nextElement()
					if (address !is Inet4Address || address.isLoopbackAddress) continue
					val prefix = ServerCandidates.privateSubnetPrefix(address.hostAddress.orEmpty())
					if (prefix != null && !prefixes.contains(prefix)) prefixes.add(prefix)
				}
			}
		}
		return prefixes
	}

	private suspend fun probe(baseUrl: String, timeoutMs: Long): Boolean = withContext(Dispatchers.IO) {
		runCatching {
			val request = Request.Builder().url("$baseUrl/health").get().build()
			client.newBuilder()
				.callTimeout(timeoutMs, TimeUnit.MILLISECONDS)
				.build()
				.newCall(request)
				.execute()
				.use { it.isSuccessful }
		}.getOrDefault(false)
	}
}
