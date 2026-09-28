package dev.giovannidrago.photoatlas.studio.ui.screens.gallery

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.CloudQueue
import androidx.compose.material.icons.filled.ImageNotSupported
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import androidx.compose.ui.platform.LocalContext
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry

/** One gallery tile: thumbnail plus state badges, like the Flutter tile. */
@Composable
fun GalleryTile(
	entry: GalleryEntry,
	size: Dp,
	selectionMode: Boolean,
	selected: Boolean,
	onTap: () -> Unit,
) {
	val scheme = MaterialTheme.colorScheme
	Box(
		modifier = Modifier
			.size(size)
			.clip(RoundedCornerShape(14.dp))
			.background(scheme.surfaceContainerHighest)
			.clickable(onClick = onTap),
	) {
		val model: Any? = entry.local?.uri ?: entry.cloud?.thumbnailUrl
		if (model == null) {
			Icon(
				imageVector = if (entry.isVideo) {
					Icons.Filled.Videocam
				} else {
					Icons.Filled.ImageNotSupported
				},
				contentDescription = null,
				tint = scheme.onSurfaceVariant,
				modifier = Modifier.align(Alignment.Center).size(28.dp),
			)
		} else {
			AsyncImage(
				model = ImageRequest.Builder(LocalContext.current)
					.data(model)
					.crossfade(true)
					.build(),
				contentDescription = entry.name,
				contentScale = ContentScale.Crop,
				modifier = Modifier.fillMaxSize(),
			)
		}

		if (entry.isVideo) {
			Row(
				modifier = Modifier
					.align(Alignment.BottomStart)
					.padding(6.dp)
					.background(
						color = Color.Black.copy(alpha = 0.54f),
						shape = RoundedCornerShape(8.dp),
					)
					.padding(horizontal = 6.dp, vertical = 2.dp),
				verticalAlignment = Alignment.CenterVertically,
				horizontalArrangement = Arrangement.spacedBy(2.dp),
			) {
				Icon(
					imageVector = Icons.Filled.PlayArrow,
					contentDescription = null,
					tint = Color.White,
					modifier = Modifier.size(12.dp),
				)
				Text(
					text = durationLabel(entry.durationS),
					color = Color.White,
					fontSize = 10.sp,
				)
			}
		}

		if (!selectionMode) {
			Box(
				modifier = Modifier
					.align(Alignment.BottomEnd)
					.padding(6.dp)
					.background(
						color = Color.Black.copy(alpha = 0.54f),
						shape = RoundedCornerShape(8.dp),
					)
					.padding(3.dp),
			) {
				val (icon, tint) = when {
					entry.isUploaded -> Icons.Filled.CloudDone to Color.White
					entry.isBackupFailed -> Icons.Filled.CloudOff to scheme.error
					else -> Icons.Filled.CloudQueue to Color.White
				}
				Icon(
					imageVector = icon,
					contentDescription = null,
					tint = tint,
					modifier = Modifier.size(14.dp),
				)
			}

			val topLabel = when {
				entry.isLocalOnly -> Icons.Filled.Smartphone to stringResource(R.string.gallery_local_only)
				entry.isMetadataMissing -> Icons.Filled.Info to stringResource(
					if (entry.cloud?.metadataStatus == "none") {
						R.string.no_metadata
					} else {
						R.string.partial_metadata
					},
				)
				else -> null
			}
			if (topLabel != null) {
				Row(
					modifier = Modifier
						.align(Alignment.TopEnd)
						.padding(6.dp)
						.background(
							color = scheme.tertiaryContainer.copy(alpha = 0.9f),
							shape = RoundedCornerShape(8.dp),
						)
						.padding(horizontal = 6.dp, vertical = 2.dp),
					verticalAlignment = Alignment.CenterVertically,
					horizontalArrangement = Arrangement.spacedBy(3.dp),
				) {
					Icon(
						imageVector = topLabel.first,
						contentDescription = null,
						tint = scheme.onTertiaryContainer,
						modifier = Modifier.size(10.dp),
					)
					Text(
						text = topLabel.second,
						color = scheme.onTertiaryContainer,
						fontSize = 9.sp,
					)
				}
			}
		}

		if (selectionMode) {
			Box(
				modifier = Modifier
					.align(Alignment.TopStart)
					.padding(6.dp)
					.size(22.dp)
					.clip(CircleShape)
					.background(
						if (selected) {
							scheme.primary
						} else {
							scheme.surface.copy(alpha = 0.85f)
						},
					)
					.border(1.dp, scheme.outline, CircleShape),
				contentAlignment = Alignment.Center,
			) {
				Icon(
					imageVector = Icons.Filled.Check,
					contentDescription = null,
					tint = if (selected) scheme.onPrimary else scheme.surfaceContainerHighest,
					modifier = Modifier.size(14.dp),
				)
			}
		}
	}
}

/** `mm:ss` like the Flutter tile; `--:--` when the duration is unknown. */
internal fun durationLabel(durationS: Double?): String {
	val seconds = durationS?.toLong() ?: return "--:--"
	val minutes = seconds / 60
	val rest = seconds % 60
	return "%02d:%02d".format(minutes, rest)
}

/** Small text used by the counters and backdrops. */
@Composable
internal fun LabelSmall(text: String, modifier: Modifier = Modifier) {
	Text(
		text = text,
		style = MaterialTheme.typography.labelSmall,
		fontWeight = FontWeight.Normal,
		modifier = modifier,
	)
}
