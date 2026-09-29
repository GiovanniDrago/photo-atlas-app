package dev.giovannidrago.photoatlas.studio.ui.screens.map

import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.data.remote.MediaClusterDto
import dev.giovannidrago.photoatlas.studio.domain.map.GlobeMath
import dev.giovannidrago.photoatlas.studio.domain.map.MapThresholds
import kotlin.math.sin
import kotlin.math.sqrt
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Curated orthographic globe: Natural Earth land, gradient ocean, atmosphere
 * glow, depth-sorted clusters, drag with inertia and pinch zoom.
 */
@Composable
fun PlanetGlobe(
	land: List<FloatArray>,
	clusters: List<MediaClusterDto>,
	centerLat: Double,
	centerLon: Double,
	scale: Double,
	selectedKey: String?,
	onCenterChanged: (Double, Double) -> Unit,
	onScaleChanged: (Double) -> Unit,
	onClusterTap: (MediaClusterDto) -> Unit,
	onSwitchToMap: () -> Unit,
	modifier: Modifier = Modifier,
) {
	val scheme = MaterialTheme.colorScheme
	val scope = rememberCoroutineScope()
	val currentCenter = rememberUpdatedState(centerLat to centerLon)
	val currentScale = rememberUpdatedState(scale)
	val currentClusters = rememberUpdatedState(clusters)
	val hitPoints = remember { mutableListOf<Pair<Float, Float>>() }
	val hitIndices = remember { mutableListOf<Int>() }
	val velocity = remember { FloatArray(2) }
	val inertiaJob = remember { mutableStateOf<Job?>(null) }
	val pulse = remember { mutableStateOf(0f) }
	val labelPaint = remember {
		Paint().apply {
			isAntiAlias = true
			textAlign = Paint.Align.CENTER
			typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
		}
	}

	// Soft pulse on the selected cluster.
	LaunchedEffect(selectedKey) {
		while (true) {
			pulse.value = ((sin(System.currentTimeMillis() / 400.0) + 1.0) / 2.0).toFloat()
			delay(50)
		}
	}

	fun scheduleInertia() {
		inertiaJob.value?.cancel()
		inertiaJob.value = scope.launch {
			delay(70)
			var vx = velocity[0]
			var vy = velocity[1]
			while (sqrt(vx * vx + vy * vy) > 0.6f) {
				val (lat, lon) = GlobeMath.dragTo(
					currentCenter.value.first,
					currentCenter.value.second,
					vx,
					vy,
					currentScale.value,
				)
				onCenterChanged(lat, lon)
				vx *= 0.92f
				vy *= 0.92f
				delay(16)
			}
		}
	}

	Canvas(
		modifier = modifier
			.fillMaxSize()
			.pointerInput(Unit) {
				detectTransformGestures { _, pan, zoom, _ ->
					inertiaJob.value?.cancel()
					velocity[0] = pan.x
					velocity[1] = pan.y
					if (zoom != 1f) {
						val next = (currentScale.value * zoom).coerceIn(
							GlobeMath.MinScale,
							GlobeMath.MaxScale,
						)
						onScaleChanged(next)
						if (next >= MapThresholds.GlobeToMapScale) {
							onSwitchToMap()
							return@detectTransformGestures
						}
					}
					if (pan != Offset.Zero) {
						val (lat, lon) = GlobeMath.dragTo(
							currentCenter.value.first,
							currentCenter.value.second,
							pan.x,
							pan.y,
							currentScale.value,
						)
						onCenterChanged(lat, lon)
					}
					scheduleInertia()
				}
			}
			.pointerInput(clusters) {
				detectTapGestures { offset ->
					val hit = GlobeMath.hitTest(hitPoints, offset.x, offset.y)
						?: return@detectTapGestures
					val index = hitIndices.getOrNull(hit) ?: return@detectTapGestures
					currentClusters.value.getOrNull(index)?.let(onClusterTap)
				}
			},
	) {
		val origin = Offset(size.width / 2f, size.height / 2f)
		val radius = GlobeMath.radius(size.width, size.height, currentScale.value)
		val primary = scheme.primary
		val center = currentCenter.value
		val density = density

		// Atmosphere glow + ocean gradient.
		drawCircle(
			brush = Brush.radialGradient(
				colors = listOf(
					primary.copy(alpha = 0.18f),
					primary.copy(alpha = 0.05f),
					Color.Transparent,
				),
				center = origin,
				radius = radius + 26.dp.toPx(),
			),
			radius = radius + 26.dp.toPx(),
			center = origin,
		)
		drawCircle(
			brush = Brush.radialGradient(
				colors = listOf(
					scheme.surfaceContainerHighest,
					scheme.surfaceContainerHighest.copy(alpha = 0.72f),
				),
				center = origin - Offset(0f, radius * 0.35f),
				radius = radius * 1.6f,
			),
			radius = radius,
			center = origin,
		)

		// Land polygons.
		val landFill = primary.copy(alpha = 0.22f)
		val landStroke = primary.copy(alpha = 0.75f)
		val strokeWidth = 0.8.dp.toPx()
		for (ring in land) {
			val path = Path()
			var started = false
			var index = 0
			while (index + 1 < ring.size) {
				val projected = GlobeMath.project(
					latDeg = ring[index + 1].toDouble(),
					lonDeg = ring[index].toDouble(),
					centerLat = center.first,
					centerLon = center.second,
					originX = origin.x,
					originY = origin.y,
					radius = radius,
				)
				if (projected == null) {
					started = false
				} else if (!started) {
					path.moveTo(projected.first, projected.second)
					started = true
				} else {
					path.lineTo(projected.first, projected.second)
				}
				index += 2
			}
			drawPath(path, color = landFill)
			drawPath(path, color = landStroke, style = Stroke(width = strokeWidth))
		}

		// Graticule.
		val graticule = scheme.onSurface.copy(alpha = 0.08f)
		val graticuleWidth = 0.5.dp.toPx()
		fun graticulePoint(lat: Double, lon: Double) = GlobeMath.project(
			latDeg = lat,
			lonDeg = lon,
			centerLat = center.first,
			centerLon = center.second,
			originX = origin.x,
			originY = origin.y,
			radius = radius,
		)
		for (lat in -60..60 step 30) {
			drawPolyline(
				points = (-180..180 step 6).map { lon ->
					graticulePoint(lat.toDouble(), lon.toDouble())
				},
				color = graticule,
				width = graticuleWidth,
			)
		}
		for (lon in -150..180 step 30) {
			drawPolyline(
				points = (-90..90 step 6).map { lat ->
					graticulePoint(lat.toDouble(), lon.toDouble())
				},
				color = graticule,
				width = graticuleWidth,
			)
		}

		// Clusters, sorted by depth (nearer the center first).
		val maxCount = clusters.maxOfOrNull { it.count }?.coerceAtLeast(1) ?: 1
		hitPoints.clear()
		hitIndices.clear()
		val projected = clusters.map { cluster ->
			graticulePoint(cluster.lat, cluster.lon)
		}
		val order = projected.indices
			.filter { projected[it] != null }
			.sortedByDescending { index ->
				val point = projected[index]!!
				val dx = point.first - origin.x
				val dy = point.second - origin.y
				1f - (sqrt(dx * dx + dy * dy) / radius)
			}
		for (index in order) {
			val point = projected[index]!!
			val cluster = clusters[index]
			hitPoints.add(point)
			hitIndices.add(index)
			val circleRadius = GlobeMath.clusterRadius(radius, cluster.count, maxCount)
			val selected = cluster.key == selectedKey
			drawCircle(
				brush = Brush.radialGradient(
					colors = listOf(
						primary.copy(alpha = if (selected) 0.95f else 0.7f),
						Color.Transparent,
					),
					center = point,
					radius = circleRadius * 2.4f,
				),
				radius = circleRadius * 2.4f,
				center = point,
			)
			drawCircle(primary.copy(alpha = if (selected) 0.95f else 0.8f), circleRadius, point)
			drawCircle(
				color = scheme.onPrimary.copy(alpha = 0.9f),
				radius = circleRadius,
				center = point,
				style = Stroke(width = if (selected) 2.6.dp.toPx() else 1.1.dp.toPx()),
			)
			if (selected) {
				drawCircle(
					color = primary.copy(alpha = 0.2f + 0.35f * pulse.value),
					radius = circleRadius + 6.dp.toPx(),
					center = point,
					style = Stroke(width = 1.6.dp.toPx()),
				)
			}
			if (circleRadius >= 13.dp.toPx()) {
				labelPaint.color = scheme.onPrimary.toArgb()
				labelPaint.textSize = GlobeMath.clusterLabelSize(circleRadius / density) * density
				drawContext.canvas.nativeCanvas.drawText(
					cluster.count.toString(),
					point.x,
					point.y + labelPaint.textSize / 3f,
					labelPaint,
				)
			}
		}

		// Rim.
		drawCircle(
			color = primary.copy(alpha = 0.55f),
			radius = radius,
			center = origin,
			style = Stroke(width = 1.4.dp.toPx()),
		)
	}
}

private fun DrawScope.drawPolyline(
	points: List<Pair<Float, Float>?>,
	color: Color,
	width: Float,
) {
	val path = Path()
	var started = false
	for (point in points) {
		if (point == null) {
			started = false
			continue
		}
		if (!started) {
			path.moveTo(point.first, point.second)
			started = true
		} else {
			path.lineTo(point.first, point.second)
		}
	}
	drawPath(path, color = color, style = Stroke(width = width))
}
