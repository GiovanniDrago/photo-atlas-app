package dev.giovannidrago.photoatlas.studio.ui.screens.map

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.material3.MaterialTheme
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.map.OsmSupport
import dev.giovannidrago.photoatlas.studio.data.remote.MediaClusterDto
import dev.giovannidrago.photoatlas.studio.domain.map.ClusterQuery
import dev.giovannidrago.photoatlas.studio.domain.map.MapThresholds
import org.osmdroid.events.DelayedMapListener
import org.osmdroid.events.MapListener
import org.osmdroid.events.ScrollEvent
import org.osmdroid.events.ZoomEvent
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker

/**
 * osmdroid map inside Compose: CARTO tiles, cluster overlay, tap selection and
 * a debounced movement callback (same 450 ms as the Flutter map).
 */
@Composable
fun OsmMapView(
	center: Pair<Double, Double>,
	zoom: Double,
	clusters: List<MediaClusterDto>,
	selectedKey: String?,
	interactive: Boolean,
	onSelect: (MediaClusterDto) -> Unit,
	onMoved: (ClusterQuery) -> Unit,
	modifier: Modifier = Modifier,
	marker: Pair<Double, Double>? = null,
) {
	val context = LocalContext.current
	val isDark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
	val primary = MaterialTheme.colorScheme.primary
	val onSurface = MaterialTheme.colorScheme.onSurface
	val currentOnSelect by rememberUpdatedState(onSelect)
	val currentOnMoved by rememberUpdatedState(onMoved)

	var mapView by remember { mutableStateOf<MapView?>(null) }
	val overlay = remember {
		ClusterOverlay(context) { cluster -> currentOnSelect(cluster) }
	}
	val markerOverlay = remember {
		Marker(context).apply {
			setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
			icon = ContextCompat.getDrawable(context, R.drawable.ic_map_pin)
			isEnabled = false
		}
	}

	AndroidView(
		modifier = modifier,
		factory = { viewContext ->
			OsmSupport.configure(viewContext)
			MapView(viewContext).apply {
				setTileSource(OsmSupport.tileSource(isDark))
				setMultiTouchControls(interactive)
				minZoomLevel = MapThresholds.MinMapZoom.toDouble()
				maxZoomLevel = MapThresholds.MaxMapZoom.toDouble()
				setMapOrientation(0f)
				isTilesScaledToDpi = false
				overlays.add(overlay)
				overlays.add(markerOverlay)
				controller.setCenter(GeoPoint(center.first, center.second))
				controller.setZoom(zoom)
				if (interactive) {
					addMapListener(
						DelayedMapListener(
							object : MapListener {
								override fun onScroll(event: ScrollEvent?): Boolean {
									setMapOrientation(0f)
									reportPosition()
									return false
								}

								override fun onZoom(event: ZoomEvent?): Boolean {
									reportPosition()
									return false
								}

								private fun reportPosition() {
									val box = boundingBox ?: return
									currentOnMoved(
										ClusterQuery(
											west = box.lonWest.coerceIn(-180.0, 180.0),
											south = box.latSouth.coerceIn(-90.0, 90.0),
											north = box.latNorth.coerceIn(-90.0, 90.0),
											east = box.lonEast.coerceIn(-180.0, 180.0),
											zoom = MapThresholds.mapZoom(zoomLevelDouble),
										),
									)
								}
							},
							MapThresholds.MapRefetchDebounceMs,
						),
					)
				}
				mapView = this
			}
		},
		update = { view ->
			val source = OsmSupport.tileSource(isDark)
			if (view.tileProvider.tileSource != source) view.setTileSource(source)
			view.setMultiTouchControls(interactive)
			overlay.clusters = clusters
			overlay.selectedKey = selectedKey
			overlay.primaryColor = primary.toArgb()
			overlay.labelColor = onSurface.toArgb()
			if (marker != null) {
				markerOverlay.isEnabled = true
				markerOverlay.position = GeoPoint(marker.first, marker.second)
			} else {
				markerOverlay.isEnabled = false
			}
			view.invalidate()
		},
	)

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

