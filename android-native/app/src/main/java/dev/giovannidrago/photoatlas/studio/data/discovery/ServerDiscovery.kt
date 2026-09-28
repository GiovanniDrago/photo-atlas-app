package dev.giovannidrago.photoatlas.studio.data.discovery

import dev.giovannidrago.photoatlas.studio.data.local.ApiBaseUrlProvider
import java.io.InterruptedIOException
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

/** Result of a single address probe, with the reason it failed. */
sealed interface ProbeOutcome {
	val url: String

	data class Success(override val url: String, val configOk: Boolean) : ProbeOutcome {
		val isOurApi: Boolean get() = configOk
	}

	data class HttpError(override val url: String, val code: Int) : ProbeOutcome

	data class Timeout(override val url: String) : ProbeOutcome

	data class Refused(override val url: String) : ProbeOutcome

	data class Failure(override val url: String, val reason: String) : ProbeOutcome
}

/** Short technical reason, used by the bootstrap error message. */
fun ProbeOutcome.reason(): String = when (this) {
	is ProbeOutcome.Success -> if (configOk) "ok" else "health ok, config missing"
	is ProbeOutcome.HttpError -> "HTTP $code"
	is ProbeOutcome.Timeout -> "timeout"
	is ProbeOutcome.Refused -> "connection refused"
	is ProbeOutcome.Failure -> reason
}

/** Outcome of a discovery attempt, with the addresses that were tried. */
data class DetectResult(
	val url: String?,
	val attempts: List<ProbeOutcome>,
	val scannedLan: Boolean,
) {
	val tried: List<String> get() = attempts.map { it.url }
}

/** Finds the API on the LAN and remembers the address that answers. */
@Singleton
class ServerDiscovery @Inject constructor(
	private val settings: ApiBaseUrlProvider,
	@Named("plain") private val client: OkHttpClient,
) {
	suspend fun isOnline(baseUrl: String, timeoutMs: Long = 2000): Boolean =
		test(baseUrl, timeoutMs) is ProbeOutcome.Success

	/**
	 * Probes an address and, when it answers, checks that it really is the
	 * Photo Atlas API (/api/config with the Supabase settings).
	 */
	suspend fun test(baseUrl: String, timeoutMs: Long = 4000): ProbeOutcome {
		val normalized = ServerCandidates.normalize(baseUrl)
		if (normalized.isEmpty()) return ProbeOutcome.Failure("", "empty address")
		return when (val outcome = probe(normalized, timeoutMs)) {
			is ProbeOutcome.Success -> {
				if (isOurApi(normalized)) {
					outcome.copy(configOk = true)
				} else {
					ProbeOutcome.Failure(normalized, "not the Photo Atlas API")
				}
			}

			else -> outcome
		}
	}

	/** Tries the known candidates, then (optionally) the whole private subnets. */
	suspend fun detectAndSave(prefer: String? = null, scanLan: Boolean = false): DetectResult {
		val candidates = ServerCandidates.candidates(
			prefer = prefer,
			saved = runCatching { settings.currentApiBaseUrl() }.getOrNull(),
		)
		val attempts = mutableListOf<ProbeOutcome>()
		for (candidate in candidates) {
			val outcome = probe(candidate, 2500)
			if (outcome is ProbeOutcome.Success && isOurApi(candidate)) {
				settings.setApiBaseUrl(candidate)
				attempts += outcome.copy(configOk = true)
				return DetectResult(url = candidate, attempts = attempts, scannedLan = false)
			}
			attempts += if (outcome is ProbeOutcome.Success) {
				ProbeOutcome.Failure(candidate, "health ok but /api/config failed")
			} else {
				outcome
			}
		}
		if (scanLan) {
			val found = scanLan()
			if (found != null) {
				settings.setApiBaseUrl(found)
				return DetectResult(url = found, attempts = attempts, scannedLan = true)
			}
		}
		return DetectResult(url = null, attempts = attempts, scannedLan = scanLan)
	}

	/** Probes `<prefix>.1-254:8787` on every private subnet of the device. */
	suspend fun scanLan(): String? {
		val prefixes = localSubnetPrefixes()
		if (prefixes.isEmpty()) return null
		val hosts = prefixes.flatMap { prefix ->
			(1..254).map { host -> "http://$prefix.$host:${ServerCandidates.Port}" }
		}
		val semaphore = Semaphore(48)
		var found: String? = null
		return coroutineScope {
			hosts.map { host ->
				async(Dispatchers.IO) {
					semaphore.withPermit {
						if (found == null &&
							probe(host, ScanProbeTimeoutMs) is ProbeOutcome.Success &&
							isOurApi(host)
						) {
							found = host
						}
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

	private suspend fun probe(baseUrl: String, timeoutMs: Long): ProbeOutcome =
		withContext(Dispatchers.IO) {
			val normalized = ServerCandidates.normalize(baseUrl)
			if (normalized.isEmpty()) return@withContext ProbeOutcome.Failure("", "empty address")
			try {
				val request = Request.Builder().url("$normalized/health").get().build()
				client.newBuilder()
					.callTimeout(timeoutMs, TimeUnit.MILLISECONDS)
					.build()
					.newCall(request)
					.execute()
					.use { response ->
						if (response.isSuccessful) {
							ProbeOutcome.Success(normalized, configOk = false)
						} else {
							ProbeOutcome.HttpError(normalized, response.code)
						}
					}
			} catch (_: InterruptedIOException) {
				ProbeOutcome.Timeout(normalized)
			} catch (error: java.io.IOException) {
				val refused = generateSequence<Throwable>(error) { it.cause }
					.any { it is java.net.ConnectException }
				val message = error.message.orEmpty()
				if (refused || message.contains("refused", ignoreCase = true)) {
					ProbeOutcome.Refused(normalized)
				} else {
					ProbeOutcome.Failure(normalized, message.ifBlank { error.javaClass.simpleName })
				}
			} catch (error: Exception) {
				ProbeOutcome.Failure(normalized, error.message ?: error.javaClass.simpleName)
			}
		}

	/** True when /api/config returns the Supabase settings of our API. */
	private suspend fun isOurApi(baseUrl: String): Boolean = withContext(Dispatchers.IO) {
		runCatching {
			val request = Request.Builder().url("$baseUrl/api/config").get().build()
			client.newBuilder()
				.callTimeout(4000, TimeUnit.MILLISECONDS)
				.build()
				.newCall(request)
				.execute()
				.use { response ->
					if (!response.isSuccessful) return@use false
					val body = response.body?.string().orEmpty()
					body.contains("supabase_url") && body.contains("supabase_publishable_key")
				}
		}.getOrDefault(false)
	}

	private companion object {
		/** Wi-Fi first packets can take a moment (ARP), so be generous. */
		const val ScanProbeTimeoutMs = 800L
	}
}
