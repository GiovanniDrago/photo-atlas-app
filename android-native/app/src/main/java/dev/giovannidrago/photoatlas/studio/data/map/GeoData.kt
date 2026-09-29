package dev.giovannidrago.photoatlas.studio.data.map

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * Natural Earth land polygons (public domain) used by the globe, parsed once:
 * every ring becomes a flat [lon, lat, lon, lat, ...] FloatArray.
 */
@Singleton
class GeoData @Inject constructor(
	@ApplicationContext private val context: Context,
) {
	@Volatile
	private var cached: List<FloatArray>? = null

	suspend fun loadLand(): List<FloatArray> {
		cached?.let { return it }
		val rings = withContext(Dispatchers.IO) {
			runCatching { parse() }.getOrDefault(emptyList())
		}
		cached = rings
		return rings
	}

	private fun parse(): List<FloatArray> {
		val json = context.assets.open(ASSET).bufferedReader().use { it.readText() }
		val root = JSONObject(json)
		val features = root.optJSONArray("features") ?: return emptyList()
		val rings = mutableListOf<FloatArray>()
		for (index in 0 until features.length()) {
			val geometry = features.optJSONObject(index)?.optJSONObject("geometry") ?: continue
			when (geometry.optString("type")) {
				"Polygon" -> {
					val coordinates = geometry.optJSONArray("coordinates") ?: continue
					for (ringIndex in 0 until coordinates.length()) {
						coordinates.optJSONArray(ringIndex)?.let { rings += flatten(it) }
					}
				}

				"MultiPolygon" -> {
					val polygons = geometry.optJSONArray("coordinates") ?: continue
					for (polygonIndex in 0 until polygons.length()) {
						val polygon = polygons.optJSONArray(polygonIndex) ?: continue
						for (ringIndex in 0 until polygon.length()) {
							polygon.optJSONArray(ringIndex)?.let { rings += flatten(it) }
						}
					}
				}
			}
		}
		return rings
	}

	private fun flatten(ring: org.json.JSONArray): FloatArray {
		val points = FloatArray(ring.length() * 2)
		for (index in 0 until ring.length()) {
			val point = ring.optJSONArray(index) ?: continue
			points[index * 2] = point.optDouble(0).toFloat()
			points[index * 2 + 1] = point.optDouble(1).toFloat()
		}
		return points
	}

	private companion object {
		const val ASSET = "geo/ne_110m_land.geojson"
	}
}
