package dev.giovannidrago.photoatlas.studio.domain.map

import kotlin.math.roundToInt

/** Pure helpers of the smart-album location picker (tested). */
object LocationPicker {
	const val MinRadiusM = 100.0
	const val MaxRadiusM = 200000.0
	const val DefaultRadiusM = 5000.0
	const val DefaultLat = 41.9
	const val DefaultLon = 12.5
	const val DefaultZoomWithoutCenter = 5.0
	const val DefaultZoomWithCenter = 11.0

	fun clampRadius(radiusM: Double?): Double =
		(radiusM ?: DefaultRadiusM).coerceIn(MinRadiusM, MaxRadiusM)

	/** Km label with no decimals when integer, one otherwise (`albumRuleRadius`). */
	fun radiusKmLabel(radiusM: Double): String {
		val km = radiusM / 1000.0
		return if (km == km.roundToInt().toDouble()) {
			km.roundToInt().toString()
		} else {
			"%.1f".format(km)
		}
	}

	fun zoomFor(hasCenter: Boolean): Double =
		if (hasCenter) DefaultZoomWithCenter else DefaultZoomWithoutCenter
}
