package dev.giovannidrago.photoatlas.studio.ui.screens.map

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.MotionEvent
import dev.giovannidrago.photoatlas.studio.data.remote.MediaClusterDto
import kotlin.math.sqrt
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Overlay

/**
 * Cluster circles with count labels, styled like the Flutter map layer, plus
 * tap selection of the nearest cluster.
 */
class ClusterOverlay(
	context: Context,
	private val onSelect: (MediaClusterDto) -> Unit,
) : Overlay(context) {
	var clusters: List<MediaClusterDto> = emptyList()
	var selectedKey: String? = null
	var primaryColor: Int = 0xFF00696B.toInt()
	var labelColor: Int = 0xFF161D1D.toInt()

	private val density = context.resources.displayMetrics.density
	private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
	private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
	private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }

	override fun draw(canvas: Canvas, mapView: MapView, shadow: Boolean) {
		if (shadow || clusters.isEmpty()) return
		val projection = mapView.projection
		val maxCount = clusters.maxOfOrNull { it.count }?.coerceAtLeast(1) ?: 1
		for (cluster in clusters) {
			val point = projection.toPixels(GeoPoint(cluster.lat, cluster.lon), null)
			val radius = ((10f + 26f * sqrt(cluster.count.toDouble() / maxCount)) * density).toFloat()
			val selected = cluster.key == selectedKey
			fillPaint.color = withAlpha(primaryColor, if (selected) 0.85f else 0.4f)
			canvas.drawCircle(point.x.toFloat(), point.y.toFloat(), radius, fillPaint)
			borderPaint.color = primaryColor
			borderPaint.strokeWidth = 1.5f * density
			canvas.drawCircle(point.x.toFloat(), point.y.toFloat(), radius, borderPaint)
			labelPaint.color = labelColor
			labelPaint.textSize = 12f * density
			labelPaint.isFakeBoldText = true
			canvas.drawText(
				cluster.count.toString(),
				point.x.toFloat(),
				point.y.toFloat() + labelPaint.textSize / 3f,
				labelPaint,
			)
		}
	}

	override fun onSingleTapConfirmed(event: MotionEvent, mapView: MapView): Boolean {
		if (clusters.isEmpty()) return false
		val projection = mapView.projection
		val maxDistance = 40f * density
		var best: Int? = null
		var bestDistance = maxDistance
		for ((index, cluster) in clusters.withIndex()) {
			val point = projection.toPixels(GeoPoint(cluster.lat, cluster.lon), null)
			val dx = point.x - event.x
			val dy = point.y - event.y
			val distance = sqrt(dx * dx + dy * dy)
			if (distance < bestDistance) {
				bestDistance = distance
				best = index
			}
		}
		val index = best ?: return false
		onSelect(clusters[index])
		return true
	}

	private fun withAlpha(color: Int, alpha: Float): Int {
		val value = (alpha.coerceIn(0f, 1f) * 255).toInt()
		return (color and 0x00FFFFFF) or (value shl 24)
	}
}
