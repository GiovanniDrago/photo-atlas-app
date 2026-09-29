package dev.giovannidrago.photoatlas.studio.ui.screens.map

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp

/**
 * Non-interactive 160 dp map with the item pin, like the Flutter viewer mini
 * map: tapping opens the position in the maps app.
 */
@Composable
fun MiniMap(
	lat: Double,
	lon: Double,
	onOpen: () -> Unit,
	modifier: Modifier = Modifier,
) {
	Box(
		modifier = modifier
			.fillMaxWidth()
			.height(160.dp)
			.clip(RoundedCornerShape(12.dp)),
	) {
		OsmMapView(
			center = lat to lon,
			zoom = 15.0,
			clusters = emptyList(),
			selectedKey = null,
			interactive = false,
			onSelect = {},
			onMoved = {},
			marker = lat to lon,
			modifier = Modifier.fillMaxSize(),
		)
		Box(
			modifier = Modifier
				.matchParentSize()
				.clickable(onClick = onOpen),
		)
	}
}
