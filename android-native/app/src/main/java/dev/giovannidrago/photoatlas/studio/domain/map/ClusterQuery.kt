package dev.giovannidrago.photoatlas.studio.domain.map

import java.util.Objects

/** Cluster query key: same fields as the Flutter app (west/south/east/north/zoom). */
data class ClusterQuery(
	val west: Double,
	val south: Double,
	val north: Double,
	val east: Double,
	val zoom: Int,
) {
	companion object {
		val World = ClusterQuery(west = -180.0, south = -90.0, north = 90.0, east = 180.0, zoom = 1)
	}

	override fun equals(other: Any?): Boolean =
		other is ClusterQuery &&
			other.west == west &&
			other.south == south &&
			other.east == east &&
			other.north == north &&
			other.zoom == zoom

	override fun hashCode(): Int = Objects.hash(west, south, east, north, zoom)
}

/** Zoom buckets and mode thresholds, ported from the Flutter map screen. */
object MapThresholds {
	const val GlobeToMapScale = 2.5
	const val MapToGlobeZoom = 2.6
	const val MapSwitchZoom = 4.5
	const val MapRefetchDebounceMs = 450L
	const val MinMapZoom = 2
	const val MaxMapZoom = 18
	const val SectionLimit = 200

	/** Cluster zoom of the globe for a pinch scale. */
	fun globeZoom(scale: Double): Int = when {
		scale < 1.4 -> 1
		scale < 1.8 -> 2
		else -> 3
	}

	/** Camera zoom of the detailed map, as the Flutter app floors it. */
	fun mapZoom(zoom: Double): Int = zoom.toInt().coerceIn(0, 18)

	fun clampWest(value: Double): Double = value.coerceIn(-180.0, 180.0)

	fun clampLat(value: Double): Double = value.coerceIn(-90.0, 90.0)
}
