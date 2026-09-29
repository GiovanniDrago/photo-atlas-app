package dev.giovannidrago.photoatlas.studio.ui.screens.map

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaSource
import dev.giovannidrago.photoatlas.studio.data.map.GeoData
import dev.giovannidrago.photoatlas.studio.data.remote.MediaClusterDto
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.domain.map.ClusterQuery
import dev.giovannidrago.photoatlas.studio.domain.map.MapThresholds
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Globe camera, detailed map camera, clusters and the selected section. */
data class MapState(
	val globeMode: Boolean = true,
	val globeLat: Double = 25.0,
	val globeLon: Double = 0.0,
	val globeScale: Double = 1.0,
	val globeQuery: ClusterQuery = ClusterQuery.World,
	val mapLat: Double = 25.0,
	val mapLon: Double = 0.0,
	val mapZoom: Double = MapThresholds.MapSwitchZoom,
	val mapQuery: ClusterQuery = ClusterQuery.World,
	val clusters: List<MediaClusterDto> = emptyList(),
	val loading: Boolean = false,
	val error: String? = null,
	val selected: MediaClusterDto? = null,
	val sectionItems: List<GalleryEntry> = emptyList(),
	val sectionLoading: Boolean = false,
	val sectionError: String? = null,
)

/**
 * Cluster fetching and camera of the map tab, ported from the Flutter
 * `map_screen.dart`: one globe query, one map query, mode thresholds and the
 * selected section loaded from the cluster bounds.
 */
@HiltViewModel
class MapViewModel @Inject constructor(
	private val api: PhotoAtlasClient,
	private val device: DeviceMediaSource,
	private val geoData: GeoData,
) : ViewModel() {
	private val _state = MutableStateFlow(MapState())
	val state: StateFlow<MapState> = _state.asStateFlow()

	private val _land = MutableStateFlow<List<FloatArray>>(emptyList())
	val land: StateFlow<List<FloatArray>> = _land.asStateFlow()

	private var lastQuery: ClusterQuery? = null

	init {
		viewModelScope.launch {
			_land.value = geoData.loadLand()
		}
		refreshClusters()
	}

	/** Globe drag frames only move the camera: the query stays the world. */
	fun onGlobeCenterChanged(lat: Double, lon: Double) {
		_state.value = _state.value.copy(globeLat = lat, globeLon = lon)
	}

	/** Pinch zoom on the globe refetches only when the zoom bucket changes. */
	fun onGlobeScaleChanged(scale: Double) {
		val query = ClusterQuery.World.copy(zoom = MapThresholds.globeZoom(scale))
		val changed = query != _state.value.globeQuery
		_state.value = _state.value.copy(globeScale = scale, globeQuery = query)
		if (changed) refreshClusters()
	}

	/** Manual switch from the top bar: same target as the Flutter pinch switch. */
	fun switchToMap() {
		val state = _state.value
		if (!state.globeMode) return
		_state.value = state.copy(
			globeMode = false,
			selected = null,
			sectionItems = emptyList(),
			sectionError = null,
			mapLat = state.globeLat,
			mapLon = state.globeLon,
			mapZoom = MapThresholds.MapSwitchZoom,
			mapQuery = ClusterQuery.World.copy(
				zoom = MapThresholds.mapZoom(MapThresholds.MapSwitchZoom),
			),
		)
		refreshClusters()
	}

	fun switchToGlobe() {
		switchToGlobeAt(_state.value.mapLat, _state.value.mapLon)
	}

	/** Map movement, debounced by the view: below 2.6 the globe comes back. */
	fun onMapMoved(query: ClusterQuery) {
		val state = _state.value
		if (state.globeMode) return
		if (query.zoom < MapThresholds.MapToGlobeZoom) {
			switchToGlobeAt(
				lat = (query.south + query.north) / 2.0,
				lon = (query.west + query.east) / 2.0,
			)
			return
		}
		val changed = query != state.mapQuery
		_state.value = state.copy(
			mapLat = (query.south + query.north) / 2.0,
			mapLon = (query.west + query.east) / 2.0,
			mapZoom = query.zoom.toDouble(),
			mapQuery = query,
		)
		if (changed) refreshClusters()
	}

	fun select(cluster: MediaClusterDto) {
		_state.value = _state.value.copy(
			selected = cluster,
			sectionItems = emptyList(),
			sectionLoading = true,
			sectionError = null,
		)
		viewModelScope.launch {
			runCatching {
				val page = api.media(
					west = cluster.bounds.west,
					south = cluster.bounds.south,
					east = cluster.bounds.east,
					north = cluster.bounds.north,
					limit = MapThresholds.SectionLimit,
				)
				val locals = runCatching { device.resolveForItems(page.items) }
					.getOrDefault(emptyMap())
				page.items.map { item -> GalleryEntry(cloud = item, local = locals[item.externalKey]) }
			}
				.onSuccess { entries ->
					if (_state.value.selected?.key != cluster.key) return@onSuccess
					_state.value = _state.value.copy(
						sectionItems = entries,
						sectionLoading = false,
					)
				}
				.onFailure { error ->
					if (_state.value.selected?.key != cluster.key) return@onFailure
					_state.value = _state.value.copy(
						sectionLoading = false,
						sectionError = error.message,
					)
				}
		}
	}

	fun clearSelection() {
		_state.value = _state.value.copy(
			selected = null,
			sectionItems = emptyList(),
			sectionError = null,
		)
	}

	private fun switchToGlobeAt(lat: Double, lon: Double) {
		var wrapped = lon
		while (wrapped > 180.0) wrapped -= 360.0
		while (wrapped <= -180.0) wrapped += 360.0
		_state.value = _state.value.copy(
			globeMode = true,
			selected = null,
			sectionItems = emptyList(),
			sectionError = null,
			globeScale = 1.0,
			globeQuery = ClusterQuery.World,
			globeLat = lat,
			globeLon = wrapped,
		)
		refreshClusters()
	}

	/**
	 * Loads the clusters of the active camera. A query already loaded (or in
	 * flight) is not repeated, and late responses of replaced queries are
	 * dropped, like the Riverpod family cache in the Flutter app.
	 */
	private fun refreshClusters() {
		val query = if (_state.value.globeMode) _state.value.globeQuery else _state.value.mapQuery
		if (query == lastQuery) return
		lastQuery = query
		_state.value = _state.value.copy(loading = true, error = null)
		viewModelScope.launch {
			runCatching {
				api.clusters(
					west = query.west,
					south = query.south,
					east = query.east,
					north = query.north,
					zoom = query.zoom,
				)
			}
				.onSuccess { clusters ->
					if (lastQuery != query) return@onSuccess
					_state.value = _state.value.copy(clusters = clusters, loading = false)
				}
				.onFailure { error ->
					if (lastQuery != query) return@onFailure
					lastQuery = null
					_state.value = _state.value.copy(loading = false, error = error.message)
				}
		}
	}
}
