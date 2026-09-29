package dev.giovannidrago.photoatlas.studio.ui.screens.map

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Public
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.map.OsmSupport
import dev.giovannidrago.photoatlas.studio.data.remote.MediaClusterDto
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.ui.screens.gallery.GalleryTile
import dev.giovannidrago.photoatlas.studio.ui.screens.gallery.MediaViewerDialog

/**
 * Map tab: curated globe or detailed map, cluster section at the bottom,
 * switch in the top bar (same flow as the Flutter map screen).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MapScreen(viewModel: MapViewModel = hiltViewModel()) {
	val state by viewModel.state.collectAsStateWithLifecycle()
	val land by viewModel.land.collectAsStateWithLifecycle()
	var viewerIndex by remember { mutableStateOf<Int?>(null) }

	Scaffold(
		containerColor = MaterialTheme.colorScheme.background,
		topBar = {
			TopAppBar(
				title = { Text(stringResource(R.string.app_name)) },
				actions = {
					IconButton(
						onClick = {
							if (state.globeMode) viewModel.switchToMap() else viewModel.switchToGlobe()
						},
					) {
						Icon(
							imageVector = if (state.globeMode) Icons.Filled.Map else Icons.Filled.Public,
							contentDescription = stringResource(
								if (state.globeMode) R.string.map_show_map else R.string.map_show_globe,
							),
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
			Box(
				modifier = Modifier
					.weight(1f)
					.fillMaxWidth(),
			) {
				if (state.globeMode) {
					PlanetGlobe(
						land = land,
						clusters = state.clusters,
						centerLat = state.globeLat,
						centerLon = state.globeLon,
						scale = state.globeScale,
						selectedKey = state.selected?.key,
						onCenterChanged = viewModel::onGlobeCenterChanged,
						onScaleChanged = viewModel::onGlobeScaleChanged,
						onClusterTap = viewModel::select,
						onSwitchToMap = viewModel::switchToMap,
						modifier = Modifier.fillMaxSize(),
					)
					PlanetHint(
						modifier = Modifier
							.align(Alignment.BottomCenter)
							.padding(bottom = 14.dp),
					)
				} else {
					OsmMapView(
						center = state.mapLat to state.mapLon,
						zoom = state.mapZoom,
						clusters = state.clusters,
						selectedKey = state.selected?.key,
						interactive = true,
						onSelect = viewModel::select,
						onMoved = viewModel::onMapMoved,
						modifier = Modifier.fillMaxSize(),
					)
					Text(
						text = OsmSupport.Attribution,
						color = MaterialTheme.colorScheme.onSurfaceVariant,
						style = MaterialTheme.typography.labelSmall,
						modifier = Modifier
							.align(Alignment.BottomEnd)
							.padding(4.dp)
							.background(
								color = MaterialTheme.colorScheme.surface.copy(alpha = 0.75f),
								shape = RoundedCornerShape(6.dp),
							)
							.padding(horizontal = 6.dp, vertical = 2.dp),
					)
				}
				if (state.loading) {
					CircularProgressIndicator(
						modifier = Modifier
							.align(Alignment.TopEnd)
							.padding(12.dp)
							.size(20.dp),
						strokeWidth = 2.dp,
					)
				}
			}
			state.selected?.let { cluster ->
				SectionPanel(
					cluster = cluster,
					items = state.sectionItems,
					loading = state.sectionLoading,
					error = state.sectionError,
					onClose = viewModel::clearSelection,
					onOpen = { viewerIndex = it },
				)
			}
		}
	}

	val index = viewerIndex
	if (index != null && index in state.sectionItems.indices) {
		MediaViewerDialog(
			entries = state.sectionItems,
			initialIndex = index,
			onDismiss = { viewerIndex = null },
			onSelect = { viewerIndex = null },
		)
	}
}

@Composable
private fun PlanetHint(modifier: Modifier = Modifier) {
	Surface(
		modifier = modifier,
		shape = RoundedCornerShape(20.dp),
		color = MaterialTheme.colorScheme.surface.copy(alpha = 0.85f),
		border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
	) {
		Text(
			text = stringResource(R.string.map_planet_hint),
			style = MaterialTheme.typography.labelMedium,
			modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
		)
	}
}

/** Selected cluster: header with the count plus the horizontal media section. */
@Composable
private fun SectionPanel(
	cluster: MediaClusterDto,
	items: List<GalleryEntry>,
	loading: Boolean,
	error: String?,
	onClose: () -> Unit,
	onOpen: (Int) -> Unit,
) {
	val scheme = MaterialTheme.colorScheme
	Column(
		modifier = Modifier
			.fillMaxWidth()
			.height(200.dp)
			.background(scheme.surfaceContainer),
	) {
		HorizontalDivider(color = scheme.outlineVariant)
		Row(
			modifier = Modifier
				.fillMaxWidth()
				.padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
			verticalAlignment = Alignment.CenterVertically,
		) {
			Icon(
				imageVector = Icons.Filled.Place,
				contentDescription = null,
				tint = scheme.primary,
				modifier = Modifier.size(20.dp),
			)
			Spacer(Modifier.width(10.dp))
			Column(modifier = Modifier.weight(1f)) {
				Text(
					text = stringResource(R.string.map_section_selected),
					style = MaterialTheme.typography.titleSmall,
				)
				Text(
					text = stringResource(R.string.item_count, cluster.count),
					style = MaterialTheme.typography.bodySmall,
					color = scheme.onSurfaceVariant,
				)
			}
			IconButton(onClick = onClose) {
				Icon(
					imageVector = Icons.Filled.Close,
					contentDescription = stringResource(R.string.close),
				)
			}
		}
		when {
			loading -> Box(
				modifier = Modifier
					.fillMaxWidth()
					.weight(1f),
				contentAlignment = Alignment.Center,
			) {
				CircularProgressIndicator(modifier = Modifier.size(28.dp), strokeWidth = 2.dp)
			}

			error != null -> SectionMessage(stringResource(R.string.error_loading_short))

			items.isEmpty() -> SectionMessage(stringResource(R.string.gallery_empty))

			else -> LazyRow(
				modifier = Modifier.weight(1f),
				contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
				horizontalArrangement = Arrangement.spacedBy(10.dp),
			) {
				itemsIndexed(items, key = { _, entry -> entry.key }) { index, entry ->
					GalleryTile(
						entry = entry,
						size = 110.dp,
						selectionMode = false,
						selected = false,
						onTap = { onOpen(index) },
					)
				}
			}
		}
	}
}

@Composable
private fun ColumnScope.SectionMessage(text: String) {
	Box(
		modifier = Modifier
			.fillMaxWidth()
			.weight(1f),
		contentAlignment = Alignment.Center,
	) {
		Text(
			text = text,
			style = MaterialTheme.typography.bodySmall,
			color = MaterialTheme.colorScheme.onSurfaceVariant,
		)
	}
}
