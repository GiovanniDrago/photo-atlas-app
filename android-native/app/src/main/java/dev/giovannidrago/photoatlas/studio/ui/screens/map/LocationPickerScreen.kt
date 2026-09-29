package dev.giovannidrago.photoatlas.studio.ui.screens.map

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.map.OsmSupport
import dev.giovannidrago.photoatlas.studio.domain.map.LocationPicker
import dev.giovannidrago.photoatlas.studio.domain.map.MapThresholds
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import org.osmdroid.events.MapEventsReceiver
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.MapEventsOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polygon

/**
 * Smart-album location rule picker on the osmdroid map: tap to set the center,
 * slider for the radius, Apply returns (lat, lon, radiusM). Same flow as the
 * Flutter `location_picker_screen.dart`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocationPickerScreen(
	initialLat: Double?,
	initialLon: Double?,
	initialRadiusM: Double?,
	onDone: (Double, Double, Double) -> Unit,
	onBack: () -> Unit,
) {
	val density = LocalDensity.current.density
	val isDark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
	val primary = MaterialTheme.colorScheme.primary
	var center by remember {
		mutableStateOf(
			if (initialLat != null && initialLon != null) initialLat to initialLon else null,
		)
	}
	var radiusM by remember { mutableStateOf(LocationPicker.clampRadius(initialRadiusM)) }
	var mapView by remember { mutableStateOf<MapView?>(null) }
	var markerOverlay by remember { mutableStateOf<Marker?>(null) }
	val circleOverlay = remember { Polygon().apply { isEnabled = false } }
	val eventsOverlay = remember {
		MapEventsOverlay(
			object : MapEventsReceiver {
				override fun singleTapConfirmedHelper(p: GeoPoint): Boolean {
					center = p.latitude to p.longitude
					return true
				}

				override fun longPressHelper(p: GeoPoint): Boolean = false
			},
		)
	}

	Scaffold(
		containerColor = MaterialTheme.colorScheme.background,
		topBar = {
			TopAppBar(
				title = { Text(stringResource(R.string.album_location_title)) },
				navigationIcon = {
					IconButton(onClick = onBack) {
						Icon(
							imageVector = Icons.AutoMirrored.Filled.ArrowBack,
							contentDescription = null,
						)
					}
				},
			)
		},
	) { padding ->
		Column(
			modifier = Modifier
				.fillMaxSize()
				.padding(padding),
		) {
			AndroidView(
				modifier = Modifier
					.weight(1f)
					.fillMaxWidth(),
				factory = { viewContext ->
					OsmSupport.configure(viewContext)
					MapView(viewContext).apply {
						setTileSource(OsmSupport.tileSource(isDark))
						setMultiTouchControls(true)
						minZoomLevel = MapThresholds.MinMapZoom.toDouble()
						maxZoomLevel = MapThresholds.MaxMapZoom.toDouble()
						setMapOrientation(0f)
						isTilesScaledToDpi = false
						overlays.add(circleOverlay)
						Marker(this).apply {
							setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
							icon = ContextCompat.getDrawable(viewContext, R.drawable.ic_map_pin)
							isEnabled = false
						}.let { marker ->
							overlays.add(marker)
							markerOverlay = marker
						}
						overlays.add(eventsOverlay)
						val initial = center
						controller.setCenter(
							if (initial != null) {
								GeoPoint(initial.first, initial.second)
							} else {
								GeoPoint(LocationPicker.DefaultLat, LocationPicker.DefaultLon)
							},
						)
						controller.setZoom(LocationPicker.zoomFor(initial != null))
						mapView = this
					}
				},
				update = { view ->
					val source = OsmSupport.tileSource(isDark)
					if (view.tileProvider.tileSource != source) view.setTileSource(source)
					val current = center
					circleOverlay.isEnabled = current != null
					if (current != null) {
						circleOverlay.points = circlePoints(current.first, current.second, radiusM)
						circleOverlay.fillColor = primary.copy(alpha = 0.2f).toArgb()
						circleOverlay.outlinePaint.color = primary.toArgb()
						circleOverlay.outlinePaint.strokeWidth = 2f * density
					}
					markerOverlay?.let { marker ->
						marker.isEnabled = current != null
						if (current != null) {
							marker.position = GeoPoint(current.first, current.second)
						}
					}
					view.invalidate()
				},
			)
			Column(
				modifier = Modifier
					.fillMaxWidth()
					.padding(16.dp),
				verticalArrangement = Arrangement.spacedBy(4.dp),
			) {
				val current = center
				Text(
					text = if (current != null) {
						"%.4f, %.4f".format(current.first, current.second)
					} else {
						stringResource(R.string.album_location_hint)
					},
					style = MaterialTheme.typography.bodySmall,
					color = MaterialTheme.colorScheme.onSurfaceVariant,
				)
				Row(verticalAlignment = Alignment.CenterVertically) {
					Text(stringResource(R.string.album_radius))
					Slider(
						value = radiusM.toFloat(),
						onValueChange = { radiusM = it.toDouble() },
						valueRange = LocationPicker.MinRadiusM.toFloat()..
							LocationPicker.MaxRadiusM.toFloat(),
						steps = 99,
						modifier = Modifier
							.weight(1f)
							.padding(horizontal = 12.dp),
					)
					Text("${LocationPicker.radiusKmLabel(radiusM)} km")
				}
				Button(
					onClick = {
						center?.let { point -> onDone(point.first, point.second, radiusM) }
					},
					enabled = center != null,
					modifier = Modifier.fillMaxWidth(),
				) {
					Text(stringResource(R.string.album_location_apply))
				}
			}
		}
	}

	val lifecycleOwner = LocalLifecycleOwner.current
	DisposableEffect(lifecycleOwner, mapView) {
		val view = mapView ?: return@DisposableEffect onDispose { }
		val observer = LifecycleEventObserver { _, event ->
			when (event) {
				Lifecycle.Event.ON_RESUME -> view.onResume()
				Lifecycle.Event.ON_PAUSE -> view.onPause()
				else -> Unit
			}
		}
		lifecycleOwner.lifecycle.addObserver(observer)
		view.onResume()
		onDispose {
			lifecycleOwner.lifecycle.removeObserver(observer)
			view.onPause()
		}
	}
}

/** Circle of [radiusM] meters around the center, as a 64 point polygon. */
private fun circlePoints(lat: Double, lon: Double, radiusM: Double): List<GeoPoint> {
	val points = mutableListOf<GeoPoint>()
	val latRadius = radiusM / 111_320.0
	val lonRadius = radiusM / (111_320.0 * cos(Math.toRadians(lat)).coerceAtLeast(1e-6))
	for (step in 0 until CircleSteps) {
		val angle = 2.0 * PI * step / CircleSteps
		points += GeoPoint(
			lat + latRadius * sin(angle),
			lon + lonRadius * cos(angle),
		)
	}
	return points
}

private const val CircleSteps = 64
