package dev.giovannidrago.photoatlas.studio.ui.screens.albums

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PhotoAlbum
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.ui.albums.AlbumAddOutcome
import dev.giovannidrago.photoatlas.studio.ui.albums.AlbumsViewModel

/** Sheet shown to add the selected entries to a manual album. */
@Composable
fun AlbumPickerSheet(
	viewModel: AlbumsViewModel,
	entries: List<GalleryEntry>,
	onDismiss: () -> Unit,
	onResult: (AlbumAddOutcome) -> Unit,
) {
	val albums by viewModel.albums.collectAsStateWithLifecycle()
	val manual = albums.filter { !it.isSmart }
	val context = LocalContext.current
	var busy by remember { mutableStateOf(false) }
	var showNameDialog by remember { mutableStateOf(false) }

	Column(modifier = Modifier.padding(bottom = 12.dp)) {
		Text(
			text = stringResource(R.string.album_add_title),
			style = MaterialTheme.typography.titleMedium,
			modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
		)
		if (busy) {
			CircularProgressIndicator(modifier = Modifier.padding(horizontal = 16.dp))
		}
		LazyColumn(contentPadding = PaddingValues(bottom = 8.dp)) {
			item {
				ListItem(
					leadingContent = { Icon(Icons.Filled.Add, contentDescription = null) },
					headlineContent = { Text(stringResource(R.string.album_new)) },
					modifier = Modifier.clickable(enabled = !busy) { showNameDialog = true },
				)
			}
			if (manual.isEmpty()) {
				item {
					ListItem(
						leadingContent = {
							Icon(Icons.Filled.PhotoAlbum, contentDescription = null)
						},
						headlineContent = { Text(stringResource(R.string.album_no_manual)) },
						enabled = false,
					)
				}
			}
			items(manual, key = { it.id }) { album ->
				ListItem(
					leadingContent = {
						Icon(Icons.Filled.PhotoAlbum, contentDescription = null)
					},
					headlineContent = { Text(album.name) },
					supportingContent = {
						Text(context.getString(R.string.item_count, album.itemCount))
					},
					modifier = Modifier.clickable(enabled = !busy) {
						busy = true
						viewModel.addToAlbum(album.id, entries) { outcome ->
							busy = false
							onResult(outcome)
						}
					},
				)
			}
		}
	}

	if (showNameDialog) {
		AlbumNameDialog(
			create = true,
			onDismiss = { showNameDialog = false },
			onConfirm = { name ->
				showNameDialog = false
				busy = true
				viewModel.createAndAdd(name, entries) { outcome ->
					busy = false
					onResult(outcome)
				}
			},
		)
	}
}
