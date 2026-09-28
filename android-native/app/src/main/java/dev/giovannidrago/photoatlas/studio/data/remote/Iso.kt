package dev.giovannidrago.photoatlas.studio.data.remote

import java.time.Instant

/** ISO-8601 helpers (the API always answers with UTC timestamps). */
object Iso {
	fun date(value: String?): Long? {
		if (value.isNullOrBlank()) return null
		return runCatching { Instant.parse(value).toEpochMilli() }.getOrNull()
	}

	fun text(epochMs: Long?): String? =
		epochMs?.let { Instant.ofEpochMilli(it).toString() }
}
