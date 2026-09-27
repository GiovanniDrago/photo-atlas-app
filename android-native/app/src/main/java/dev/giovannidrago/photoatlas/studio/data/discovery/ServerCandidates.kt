package dev.giovannidrago.photoatlas.studio.data.discovery

/**
 * Address candidates of the development API. The hotspot hands out a different
 * subnet at every restart, so the default is only a first guess: detection
 * (and a LAN scan) find the server when it does not answer.
 */
object ServerCandidates {
	const val DefaultApiBaseUrl = "http://10.234.121.225:8787"
	const val FallbackApiBaseUrl = "http://localhost:8787"
	const val Port = 8787

	fun normalize(value: String): String = value.trim().trimEnd('/')

	/** Most likely first, unique, without empty values. */
	fun candidates(prefer: String? = null, saved: String? = null): List<String> {
		val result = mutableListOf<String>()
		fun add(value: String?) {
			val normalized = normalize(value.orEmpty())
			if (normalized.isEmpty() || result.contains(normalized)) return
			result.add(normalized)
		}
		add(prefer)
		add(saved)
		add(DefaultApiBaseUrl)
		add(FallbackApiBaseUrl)
		return result
	}

	/** `a.b.c` for a private IPv4 address (RFC 1918), null otherwise. */
	fun privateSubnetPrefix(address: String): String? {
		val parts = address.split('.')
		if (parts.size != 4) return null
		val octets = parts.map { it.toIntOrNull() ?: return null }
		if (octets.any { it < 0 || it > 255 }) return null
		val isPrivate = octets[0] == 10 ||
			(octets[0] == 192 && octets[1] == 168) ||
			(octets[0] == 172 && octets[1] in 16..31)
		if (!isPrivate) return null
		return "${octets[0]}.${octets[1]}.${octets[2]}"
	}
}
