package dev.giovannidrago.photoatlas.studio.ui.screens.gallery

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.CloudQueue
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.ImageNotSupported
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import coil.compose.AsyncImage
import coil.request.ImageRequest
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.data.remote.MediaItemDto
import java.net.URLEncoder
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Full screen viewer: swipe, tap to zoom, vertical scroll for the details. */
@Composable
fun MediaViewerDialog(
	entries: List<GalleryEntry>,
	initialIndex: Int,
	onDismiss: () -> Unit,
	onSelect: (GalleryEntry) -> Unit,
) {
	Dialog(
		onDismissRequest = onDismiss,
		properties = DialogProperties(
			usePlatformDefaultWidth = false,
			decorFitsSystemWindows = false,
		),
	) {
		val pagerState = rememberPagerState(
			initialPage = initialIndex.coerceIn(0, (entries.size - 1).coerceAtLeast(0)),
			pageCount = { entries.size },
		)
		val context = LocalContext.current
		var zoomedKey by remember { mutableStateOf<String?>(null) }

		Surface(modifier = Modifier.fillMaxSize(), color = Color.Black) {
			BackHandler(enabled = zoomedKey != null) { zoomedKey = null }
			if (entries.isEmpty() || pagerState.currentPage !in entries.indices) {
				Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
					Text(stringResource(R.string.gallery_empty), color = Color.White)
				}
				return@Surface
			}
			val entry = entries[pagerState.currentPage]
			if (zoomedKey == entry.key) {
				ZoomedImage(entry = entry, onClose = { zoomedKey = null })
				return@Surface
			}
			Box(modifier = Modifier.fillMaxSize()) {
				HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
					ViewerPage(
						entry = entries[page],
						onZoom = { zoomedKey = entries[page].key },
						context = context,
					)
				}
				ViewerTopBar(
					entry = entry,
					position = pagerState.currentPage + 1,
					total = entries.size,
					onDismiss = onDismiss,
					onSelect = { onSelect(entry) },
					context = context,
				)
			}
		}
	}
}

@Composable
private fun ViewerTopBar(
	entry: GalleryEntry,
	position: Int,
	total: Int,
	onDismiss: () -> Unit,
	onSelect: () -> Unit,
	context: Context,
) {
	var menuOpen by remember { mutableStateOf(false) }
	Row(
		modifier = Modifier
			.fillMaxWidth()
			.background(Color.Black.copy(alpha = 0.5f))
			.padding(horizontal = 4.dp, vertical = 4.dp),
		verticalAlignment = Alignment.CenterVertically,
	) {
		IconButton(onClick = onDismiss) {
			Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close), tint = Color.White)
		}
		Column(modifier = Modifier.weight(1f)) {
			Text(
				text = entry.name,
				color = Color.White,
				maxLines = 1,
				style = MaterialTheme.typography.bodyMedium,
			)
			Text(
				text = stringResource(R.string.viewer_position, position, total),
				color = Color.White.copy(alpha = 0.7f),
				style = MaterialTheme.typography.labelSmall,
			)
		}
		Box {
			IconButton(onClick = { menuOpen = true }) {
				Icon(Icons.Filled.MoreVert, contentDescription = null, tint = Color.White)
			}
			DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
				val downloadUrl = entry.cloud?.downloadUrl
				if (!downloadUrl.isNullOrBlank()) {
					DropdownMenuItem(
						text = { Text(stringResource(R.string.download_original)) },
						leadingIcon = { Icon(Icons.Filled.Download, contentDescription = null) },
						onClick = {
							menuOpen = false
							openExternally(context, downloadUrl, R.string.download_unavailable)
						},
					)
				}
				if (hasPosition(entry)) {
					DropdownMenuItem(
						text = { Text(stringResource(R.string.viewer_open_in_maps)) },
						leadingIcon = { Icon(Icons.Filled.Map, contentDescription = null) },
						onClick = {
							menuOpen = false
							openInMaps(context, entry)
						},
					)
				}
				DropdownMenuItem(
					text = { Text(stringResource(R.string.viewer_select)) },
					onClick = {
						menuOpen = false
						onSelect()
					},
				)
			}
		}
	}
}

@Composable
private fun ViewerPage(entry: GalleryEntry, onZoom: () -> Unit, context: Context) {
	BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
		val pageHeight = maxHeight
		Column(
			modifier = Modifier
				.fillMaxSize()
				.verticalScroll(rememberScrollState()),
		) {
			Box(
				modifier = Modifier
					.fillMaxWidth()
					.height(pageHeight)
					.clickable(onClick = onZoom),
				contentAlignment = Alignment.Center,
			) {
				EntryPreview(entry = entry, context = context)
				if (entry.isVideo) {
					Row(
						modifier = Modifier
							.align(Alignment.BottomCenter)
							.padding(bottom = 64.dp)
							.background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(12.dp))
							.padding(horizontal = 10.dp, vertical = 4.dp),
						verticalAlignment = Alignment.CenterVertically,
					) {
						Icon(
							Icons.Filled.PlayArrow,
							contentDescription = null,
							tint = Color.White,
							modifier = Modifier.size(14.dp),
						)
						Text(
							text = durationLabel(entry.durationS),
							color = Color.White,
							fontSize = 12.sp,
						)
					}
				}
				Row(
					modifier = Modifier
						.align(Alignment.BottomCenter)
						.padding(bottom = 20.dp)
						.background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(16.dp))
						.padding(horizontal = 12.dp, vertical = 6.dp),
					verticalAlignment = Alignment.CenterVertically,
				) {
					Icon(
						Icons.Filled.KeyboardArrowDown,
						contentDescription = null,
						tint = Color.White,
						modifier = Modifier.size(18.dp),
					)
					Text(
						text = stringResource(R.string.viewer_scroll_details),
						color = Color.White,
						fontSize = 12.sp,
					)
				}
			}
			ViewerDetails(entry = entry, context = context)
		}
	}
}

@Composable
private fun EntryPreview(entry: GalleryEntry, context: Context) {
	val model: Any? = entry.local?.uri ?: entry.cloud?.thumbnailUrl
	if (model == null) {
		Icon(
			imageVector = if (entry.isVideo) {
				Icons.Filled.Videocam
			} else {
				Icons.Filled.ImageNotSupported
			},
			contentDescription = null,
			tint = Color.White.copy(alpha = 0.7f),
			modifier = Modifier.size(48.dp),
		)
		return
	}
	AsyncImage(
		model = ImageRequest.Builder(context).data(model).crossfade(true).build(),
		contentDescription = entry.name,
		contentScale = ContentScale.Fit,
		modifier = Modifier.fillMaxSize(),
	)
}

@Composable
private fun ZoomedImage(entry: GalleryEntry, onClose: () -> Unit) {
	val context = LocalContext.current
	Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
		val model: Any? = entry.local?.uri ?: entry.cloud?.thumbnailUrl
		if (model != null) {
			var scale by remember { mutableFloatStateOf(1f) }
			var offset by remember { mutableStateOf(Offset.Zero) }
			val transformState = rememberTransformableState { zoomChange, panChange, _ ->
				scale = (scale * zoomChange).coerceIn(1f, 6f)
				offset = if (scale > 1f) offset + panChange else Offset.Zero
			}
			AsyncImage(
				model = ImageRequest.Builder(context).data(model).crossfade(true).build(),
				contentDescription = entry.name,
				contentScale = ContentScale.Fit,
				modifier = Modifier
					.fillMaxSize()
					.transformable(transformState)
					.pointerInput(entry.key) {
						detectTapGestures(
							onDoubleTap = {
								scale = 1f
								offset = Offset.Zero
							},
						)
					}
					.graphicsLayer {
						scaleX = scale
						scaleY = scale
						translationX = offset.x
						translationY = offset.y
					},
			)
		}
		IconButton(
			onClick = onClose,
			modifier = Modifier
				.align(Alignment.TopEnd)
				.padding(8.dp),
		) {
			Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close), tint = Color.White)
		}
	}
}

@Composable
private fun ViewerDetails(entry: GalleryEntry, context: Context) {
	val cloud = entry.cloud
	Column(
		modifier = Modifier
			.fillMaxWidth()
			.background(Color(0xFF101414))
			.padding(16.dp),
		verticalArrangement = Arrangement.spacedBy(6.dp),
	) {
		Row(verticalAlignment = Alignment.CenterVertically) {
			Text(
				text = entry.name,
				color = Color.White,
				style = MaterialTheme.typography.titleMedium,
				modifier = Modifier.weight(1f),
			)
			StatusChip(entry)
		}
		Spacer(Modifier.height(6.dp))
		MetadataRow(R.string.field_type, stringResource(if (entry.isVideo) R.string.field_videos else R.string.field_photos))
		if (cloud?.mime != null) MetadataRow(R.string.field_mime, cloud.mime)
		MetadataRow(R.string.field_size, formatBytes(entry.sizeBytes))
		MetadataRow(
			R.string.field_taken,
			formatDate(cloud?.takenAtMs ?: entry.local?.takenAtMs)
				?: stringResource(R.string.not_available),
		)
		if (cloud?.fileCreatedAtMs != null) {
			MetadataRow(
				R.string.field_file_created,
				formatDate(cloud.fileCreatedAtMs) ?: stringResource(R.string.not_available),
			)
		}
		MetadataRow(
			R.string.field_modified,
			formatDate(cloud?.modifiedAtMs ?: entry.local?.modifiedAtMs)
				?: stringResource(R.string.not_available),
		)
		val lat = cloud?.lat ?: entry.local?.lat
		val lon = cloud?.lon ?: entry.local?.lon
		MetadataRow(
			R.string.field_gps,
			if (lat != null && lon != null) {
				"%.6f, %.6f".format(lat, lon)
			} else {
				stringResource(R.string.not_available)
			},
		)
		val width = cloud?.width ?: entry.local?.width
		val height = cloud?.height ?: entry.local?.height
		MetadataRow(
			R.string.field_dimensions,
			if (width != null && height != null) "$width × $height" else stringResource(R.string.not_available),
		)
		MetadataRow(
			R.string.field_duration,
			entry.durationS?.let { durationLabel(it) } ?: stringResource(R.string.not_available),
		)
		if (cloud != null) {
			MetadataRow(
				R.string.field_metadata_status,
				stringResource(
					when (cloud.metadataStatus) {
						"full" -> R.string.metadata_complete
						"partial" -> R.string.metadata_partial
						else -> R.string.no_metadata
					},
				),
			)
			MetadataRow(R.string.field_backup, backupLabel(cloud))
			val sourceLabel = cloud.sourceLabel ?: stringResource(R.string.not_available)
			val sourceKind = cloud.sourceKind ?: "-"
			MetadataRow(R.string.field_source, "$sourceLabel ($sourceKind)")
			if (cloud.isKDriveSource) {
				MetadataRow(R.string.field_kdrive_file_id, cloud.externalKey)
			}
		}
		val path = cloud?.path ?: entry.local?.uri
		if (!path.isNullOrBlank()) {
			MetadataRow(R.string.field_path, path)
		}
		val relativePath = entry.local?.relativePath
		if (!relativePath.isNullOrBlank()) {
			Row(
				modifier = Modifier
					.fillMaxWidth()
					.clickable {
						if (!openFolder(context, relativePath)) {
							toast(context, R.string.open_folder_failed)
						}
					}
					.padding(vertical = 6.dp),
				verticalAlignment = Alignment.CenterVertically,
			) {
				Icon(
					Icons.Filled.FolderOpen,
					contentDescription = null,
					tint = Color.White,
					modifier = Modifier.size(18.dp),
				)
				Spacer(Modifier.width(8.dp))
				Text(
					text = relativePath,
					color = Color(0xFF9CF1F2),
					style = MaterialTheme.typography.bodySmall,
				)
			}
		}
	}
}

@Composable
private fun MetadataRow(labelRes: Int, value: String) {
	Row(modifier = Modifier.fillMaxWidth()) {
		Text(
			text = stringResource(labelRes),
			color = Color.White.copy(alpha = 0.6f),
			style = MaterialTheme.typography.labelSmall,
			modifier = Modifier.width(130.dp),
		)
		SelectionContainer(modifier = Modifier.weight(1f)) {
			Text(
				text = value,
				color = Color.White,
				style = MaterialTheme.typography.bodySmall,
			)
		}
	}
}

@Composable
private fun StatusChip(entry: GalleryEntry) {
	val (icon, labelRes, tint) = when {
		entry.isUploaded -> Triple(Icons.Filled.CloudDone, R.string.status_uploaded, Color(0xFF80D4D5))
		entry.isBackupFailed -> Triple(Icons.Filled.CloudOff, R.string.status_upload_failed, Color(0xFFFFB4AB))
		else -> Triple(Icons.Filled.CloudQueue, R.string.status_not_uploaded, Color.White.copy(alpha = 0.7f))
	}
	Row(
		modifier = Modifier
			.background(tint.copy(alpha = 0.12f), RoundedCornerShape(10.dp))
			.padding(horizontal = 8.dp, vertical = 3.dp),
		verticalAlignment = Alignment.CenterVertically,
	) {
		Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(14.dp))
		Spacer(Modifier.width(4.dp))
		Text(
			text = stringResource(labelRes),
			color = tint,
			style = MaterialTheme.typography.labelSmall,
		)
	}
}

@Composable
private fun backupLabel(item: MediaItemDto): String {
	return when {
		item.isUploaded -> {
			val moment = formatDate(item.backedUpAtMs)
			if (moment == null) {
				stringResource(R.string.backup_on_kdrive)
			} else {
				"${stringResource(R.string.backup_on_kdrive)} · $moment"
			}
		}
		item.isBackupFailed -> {
			val error = item.backupError
			if (error.isNullOrBlank()) {
				stringResource(R.string.status_upload_failed)
			} else {
				"${stringResource(R.string.status_upload_failed)} ($error)"
			}
		}
		else -> stringResource(R.string.status_not_uploaded)
	}
}

private fun hasPosition(entry: GalleryEntry): Boolean {
	val lat = entry.cloud?.lat ?: entry.local?.lat
	val lon = entry.cloud?.lon ?: entry.local?.lon
	return lat != null && lon != null
}

private fun openInMaps(context: Context, entry: GalleryEntry) {
	val lat = entry.cloud?.lat ?: entry.local?.lat ?: return
	val lon = entry.cloud?.lon ?: entry.local?.lon ?: return
	val geo = Uri.parse("geo:$lat,$lon?q=$lat,$lon")
	val fallback = Uri.parse("https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=16/$lat/$lon")
	val opened = runCatching {
		context.startActivity(Intent(Intent.ACTION_VIEW, geo).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
		true
	}.getOrDefault(false)
	if (opened) return
	val fallbackOpened = runCatching {
		context.startActivity(
			Intent(Intent.ACTION_VIEW, fallback).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
		)
		true
	}.getOrDefault(false)
	if (!fallbackOpened) toast(context, R.string.viewer_open_maps_failed)
}

private fun openExternally(context: Context, url: String, errorRes: Int) {
	val opened = runCatching {
		context.startActivity(
			Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
		)
		true
	}.getOrDefault(false)
	if (!opened) toast(context, errorRes)
}

/** Opens the system Files app on the folder that holds a device media item. */
private fun openFolder(context: Context, relativePath: String): Boolean {
	val encoded = URLEncoder.encode(relativePath, "UTF-8").replace("+", "%20")
	val uri = Uri.parse("content://com.android.externalstorage.documents/document/primary%3A$encoded")
	return try {
		context.startActivity(
			Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
		)
		true
	} catch (_: ActivityNotFoundException) {
		false
	}
}

private fun toast(context: Context, messageRes: Int) {
	Toast.makeText(context, messageRes, Toast.LENGTH_SHORT).show()
}

internal fun formatDate(epochMs: Long?): String? {
	if (epochMs == null || epochMs <= 0L) return null
	val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
	val moment = Instant.ofEpochMilli(epochMs).atZone(ZoneId.systemDefault())
	return formatter.format(moment)
}

internal fun formatBytes(bytes: Long?): String {
	if (bytes == null || bytes <= 0L) return "n/a"
	return when {
		bytes < 1024 -> "$bytes B"
		bytes < 1024 * 1024 -> "%.1f KB".format(bytes / 1024.0)
		bytes < 1024L * 1024L * 1024L -> "%.1f MB".format(bytes / (1024.0 * 1024.0))
		else -> "%.2f GB".format(bytes / (1024.0 * 1024.0 * 1024.0))
	}
}
