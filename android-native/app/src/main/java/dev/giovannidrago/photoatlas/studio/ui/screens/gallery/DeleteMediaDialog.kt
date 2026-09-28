package dev.giovannidrago.photoatlas.studio.ui.screens.gallery

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.domain.gallery.DeleteOptions
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry

/** Asks what to delete: the cloud copy, the device file, or both. */
@Composable
fun DeleteMediaDialog(
	entries: List<GalleryEntry>,
	allowAlbum: Boolean = false,
	onDismiss: () -> Unit,
	onConfirm: (DeleteOptions, Boolean) -> Unit,
) {
	val canCloud = entries.any { it.canDeleteCloud }
	val canLocal = entries.any { it.canDeleteLocal }
	val canAlbum = allowAlbum && entries.any { it.cloud != null }
	var cloud by remember { mutableStateOf(canCloud) }
	var local by remember { mutableStateOf(canLocal) }
	var album by remember { mutableStateOf(false) }
	val nothingSelected = !cloud && !local && !album

	AlertDialog(
		onDismissRequest = onDismiss,
		title = { Text(stringResource(R.string.delete_title)) },
		text = {
			Column {
				Row(verticalAlignment = Alignment.CenterVertically) {
					Checkbox(
						checked = cloud,
						onCheckedChange = if (canCloud) {
							{ value -> cloud = value }
						} else {
							null
						},
					)
					Spacer(Modifier.width(8.dp))
					Column {
						Text(stringResource(R.string.delete_cloud))
						Text(
							text = stringResource(R.string.delete_cloud_hint),
							style = MaterialTheme.typography.labelSmall,
							color = MaterialTheme.colorScheme.onSurfaceVariant,
						)
					}
				}
				Spacer(Modifier.height(8.dp))
				Row(verticalAlignment = Alignment.CenterVertically) {
					Checkbox(
						checked = local,
						onCheckedChange = if (canLocal) {
							{ value -> local = value }
						} else {
							null
						},
					)
					Spacer(Modifier.width(8.dp))
					Column {
						Text(stringResource(R.string.delete_local))
						Text(
							text = stringResource(R.string.delete_local_hint),
							style = MaterialTheme.typography.labelSmall,
							color = MaterialTheme.colorScheme.onSurfaceVariant,
						)
					}
				}
				if (allowAlbum) {
					Spacer(Modifier.height(8.dp))
					Row(verticalAlignment = Alignment.CenterVertically) {
						Checkbox(
							checked = album,
							onCheckedChange = if (canAlbum) {
								{ value -> album = value }
							} else {
								null
							},
						)
						Spacer(Modifier.width(8.dp))
						Column {
							Text(stringResource(R.string.album_delete_from_album))
							Text(
								text = stringResource(R.string.album_delete_from_album_hint),
								style = MaterialTheme.typography.labelSmall,
								color = MaterialTheme.colorScheme.onSurfaceVariant,
							)
						}
					}
				}
			}
		},
		confirmButton = {
			TextButton(
				onClick = { onConfirm(DeleteOptions(cloud = cloud, local = local), album) },
				enabled = !nothingSelected,
			) {
				Text(stringResource(R.string.delete_confirm))
			}
		},
		dismissButton = {
			TextButton(onClick = onDismiss) {
				Text(stringResource(R.string.cancel))
			}
		},
	)
}
