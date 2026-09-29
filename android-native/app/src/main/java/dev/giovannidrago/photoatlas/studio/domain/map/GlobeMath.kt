package dev.giovannidrago.photoatlas.studio.domain.map

import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Orthographic projection of the planet globe, ported one-to-one from the
 * Flutter `planet_globe.dart` so the two apps look the same.
 */
object GlobeMath {
	/** Radius of the planet inside the viewport. */
	fun radius(width: Float, height: Float, scale: Double): Float =
		(min(width, height) * 0.42 * scale).toFloat()

	/**
	 * Projects a geographic point onto the viewport. Returns null when the point
	 * is beyond the horizon (the only clipping the painter does).
	 */
	fun project(
		latDeg: Double,
		lonDeg: Double,
		centerLat: Double,
		centerLon: Double,
		originX: Float,
		originY: Float,
		radius: Float,
	): Pair<Float, Float>? {
		val lat = Math.toRadians(latDeg)
		val lon = Math.toRadians(lonDeg)
		val lat0 = Math.toRadians(centerLat)
		val dlon = lon - Math.toRadians(centerLon)
		val cosc = sin(lat0) * sin(lat) + cos(lat0) * cos(lat) * cos(dlon)
		if (cosc < -0.03) return null
		val x = radius * cos(lat) * sin(dlon)
		val y = -radius * (cos(lat0) * sin(lat) - sin(lat0) * cos(lat) * cos(dlon))
		return (originX + x) to (originY + y)
	}

	/**
	 * Rotation while dragging: [deltaX]/[deltaY] pixels become degrees
	 * (0.35° per pixel at scale 1), latitude is clamped to ±75° and longitude
	 * wraps into (-180, 180].
	 */
	fun dragTo(
		centerLat: Double,
		centerLon: Double,
		deltaX: Float,
		deltaY: Float,
		scale: Double,
	): Pair<Double, Double> {
		val dLon = -deltaX * DragSensitivity / scale
		val dLat = deltaY * DragSensitivity / scale
		val lat = (centerLat + dLat).coerceIn(-75.0, 75.0)
		var lon = centerLon + dLon
		while (lon > 180.0) lon -= 360.0
		while (lon <= -180.0) lon += 360.0
		return lat to lon
	}

	/** Cluster circle radius on the globe, from the shared count maximum. */
	fun clusterRadius(baseRadius: Float, count: Int, maxCount: Int): Float {
		val weight = sqrt(count.toDouble() / maxCount.coerceAtLeast(1))
		return (baseRadius * (0.025 + 0.075 * weight) + 3.0).toFloat()
	}

	/** Count labels only fit on circles of at least 13 px. */
	fun clusterLabelSize(circleRadius: Float): Float =
		min(13f, circleRadius * 0.7f).coerceAtLeast(0f)

	/** Nearest cluster within [maxDistance] pixels, or null. */
	fun hitTest(
		points: List<Pair<Float, Float>>,
		x: Float,
		y: Float,
		maxDistance: Float = TapDistance,
	): Int? {
		var best: Int? = null
		var bestDistance = maxDistance
		for ((index, point) in points.withIndex()) {
			val dx = point.first - x
			val dy = point.second - y
			val distance = sqrt((dx * dx + dy * dy).toDouble()).toFloat()
			if (distance < bestDistance) {
				bestDistance = distance
				best = index
			}
		}
		return best
	}

	const val DragSensitivity = 0.35
	const val TapDistance = 32f
	const val MinScale = 1.0
	const val MaxScale = 3.2
	const val MaxLatitude = 75.0
}
