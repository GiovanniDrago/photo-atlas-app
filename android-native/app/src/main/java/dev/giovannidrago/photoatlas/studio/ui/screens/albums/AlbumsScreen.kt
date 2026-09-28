package dev.giovannidrago.photoatlas.studio.ui.screens.albums

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PhotoAlbum
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import coil.request.ImageRequest
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.remote.AlbumDto
import dev.giovannidrago.photoatlas.studio.ui.albums.AlbumsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AlbumsScreen(
	viewModel: AlbumsViewModel,
	onOpenAlbum: (AlbumDto) -> Unit,
	onEditAlbum: (AlbumDto) -> Unit,
	onCreateSmart: () -> Unit,
) {
	val albums by viewModel.albums.collectAsStateWithLifecycle()
	val loading by viewModel.loading.collectAsStateWithLifecycle()
	val error by viewModel.error.collectAsStateWithLifecycle()
	val snackbar = remember { SnackbarHostState() }
	val context = LocalContext.current
	var showCreateSheet by remember { mutableStateOf(false) }
	var nameDialog by remember { mutableStateOf<NameDialogMode?>(null) }
	var albumToDelete by remember { mutableStateOf<AlbumDto?>(null) }
	var albumToRename by remember { mutableStateOf<AlbumDto?>(null) }

	LaunchedEffect(viewModel.message) {
		viewModel.message?.let { message ->
			val detail = message.detail?.let { ": $it" }.orEmpty()
			snackbar.showSnackbar(context.getString(R.string.action_failed) + detail)
			viewModel.dismissMessage()
		}
	}

	Scaffold(
		containerColor = MaterialTheme.colorScheme.background,
		topBar = {
			TopAppBar(
				title = { Text(stringResource(R.string.tab_albums)) },
				actions = {
					IconButton(onClick = { showCreateSheet = true }) {
						Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.album_new))
					}
				},
			)
		},
		snackbarHost = { SnackbarHost(snackbar) },
	) { padding ->
		Box(
			modifier = Modifier
				.fillMaxSize()
				.padding(padding),
		) {
			when {
				loading && albums.isEmpty() -> {
					CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
				}

				error != null && albums.isEmpty() -> {
					Column(
						modifier = Modifier.align(Alignment.Center),
						horizontalAlignment = Alignment.CenterHorizontally,
					) {
						Text(text = error.orEmpty())
						TextButton(onClick = { viewModel.refresh() }) {
							Text(stringResource(R.string.retry))
						}
					}
				}

				albums.isEmpty() -> {
					Text(
						text = stringResource(R.string.album_empty),
						modifier = Modifier
							.align(Alignment.Center)
							.padding(24.dp),
					)
				}

				else -> {
					LazyVerticalGrid(
						columns = GridCells.Fixed(2),
						contentPadding = PaddingValues(12.dp),
						horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp),
						verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp),
						modifier = Modifier.fillMaxSize(),
					) {
						items(albums, key = { it.id }) { album ->
							AlbumCard(
								album = album,
								onOpen = { onOpenAlbum(album) },
								onEdit = { onEditAlbum(album) },
								onRename = { albumToRename = album },
								onDelete = { albumToDelete = album },
							)
						}
					}
				}
			}
		}
	}

	if (showCreateSheet) {
		val sheetState = rememberModalBottomSheetState()
		ModalBottomSheet(
			onDismissRequest = { showCreateSheet = false },
			sheetState = sheetState,
		) {
			Column(modifier = Modifier.padding(bottom = 12.dp)) {
				ListItem(
					leadingContent = { Icon(Icons.Filled.PhotoAlbum, contentDescription = null) },
					headlineContent = { Text(stringResource(R.string.album_create_manual)) },
					modifier = Modifier.clickable {
						showCreateSheet = false
						nameDialog = NameDialogMode.Create
					},
				)
				ListItem(
					leadingContent = { Icon(Icons.Filled.AutoAwesome, contentDescription = null) },
					headlineContent = { Text(stringResource(R.string.album_create_smart)) },
					modifier = Modifier.clickable {
						showCreateSheet = false
						onCreateSmart()
					},
				)
			}
		}
	}

	when (val mode = nameDialog) {
		NameDialogMode.Create -> AlbumNameDialog(
			create = true,
			onDismiss = { nameDialog = null },
			onConfirm = { name ->
				nameDialog = null
				viewModel.createManual(name) { album -> onOpenAlbum(album) }
			},
		)

		NameDialogMode.Rename -> {
			val target = albumToRename
			if (target != null) {
				AlbumNameDialog(
					initialName = target.name,
					onDismiss = { nameDialog = null },
					onConfirm = { name ->
						nameDialog = null
						viewModel.rename(target, name) { }
					},
				)
			}
		}

		null -> Unit
	}

	albumToDelete?.let { album ->
		AlbumDeleteDialog(
			album = album,
			onDismiss = { albumToDelete = null },
			onConfirm = {
				viewModel.delete(album)
				albumToDelete = null
			},
		)
	}

}

private enum class NameDialogMode { Create, Rename }

@Composable
private fun AlbumCard(
	album: AlbumDto,
	onOpen: () -> Unit,
	onEdit: () -> Unit,
	onRename: () -> Unit,
	onDelete: () -> Unit,
) {
	val context = LocalContext.current
	var menuOpen by remember { mutableStateOf(false) }
	val cover = album.cover
	val model: Any? = cover?.thumbnailUrl
	Card(
		modifier = Modifier
			.fillMaxWidth()
			.height(180.dp)
			.clickable(onClick = onOpen),
		shape = RoundedCornerShape(14.dp),
	) {
		Box(modifier = Modifier.fillMaxSize()) {
			if (model == null) {
				Box(
					modifier = Modifier
						.fillMaxSize()
						.background(MaterialTheme.colorScheme.surfaceContainerHighest),
					contentAlignment = Alignment.Center,
				) {
					Icon(
						imageVector = Icons.Filled.PhotoAlbum,
						contentDescription = null,
						tint = MaterialTheme.colorScheme.onSurfaceVariant,
						modifier = Modifier.size(40.dp),
					)
				}
			} else {
				AsyncImage(
					model = ImageRequest.Builder(context).data(model).crossfade(true).build(),
					contentDescription = album.name,
					contentScale = ContentScale.Crop,
					modifier = Modifier.fillMaxSize(),
				)
			}
			Box(
				modifier = Modifier
					.fillMaxSize()
					.background(
						Brush.verticalGradient(
							colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.54f)),
							startY = 90f,
						),
					),
			)
			Box(
				modifier = Modifier
					.align(Alignment.TopStart)
					.padding(8.dp)
					.background(
						MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.9f),
						RoundedCornerShape(10.dp),
					)
					.padding(horizontal = 8.dp, vertical = 2.dp),
			) {
				Text(
					text = stringResource(
						if (album.isSmart) R.string.album_kind_smart else R.string.album_kind_manual,
					),
					fontSize = 10.sp,
					color = MaterialTheme.colorScheme.onPrimaryContainer,
				)
			}
			Box(modifier = Modifier.align(Alignment.TopEnd)) {
				IconButton(onClick = { menuOpen = true }) {
					Icon(Icons.Filled.MoreVert, contentDescription = null, tint = Color.White)
				}
				DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
					if (album.isSmart) {
						DropdownMenuItem(
							text = { Text(stringResource(R.string.album_edit_rules)) },
							leadingIcon = { Icon(Icons.Filled.Tune, contentDescription = null) },
							onClick = {
								menuOpen = false
								onEdit()
							},
						)
					}
					DropdownMenuItem(
						text = { Text(stringResource(R.string.album_rename)) },
						leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
						onClick = {
							menuOpen = false
							onRename()
						},
					)
					DropdownMenuItem(
						text = { Text(stringResource(R.string.album_delete)) },
						leadingIcon = { Icon(Icons.Filled.DeleteOutline, contentDescription = null) },
						onClick = {
							menuOpen = false
							onDelete()
						},
					)
				}
			}
			Column(
				modifier = Modifier
					.align(Alignment.BottomStart)
					.fillMaxWidth()
					.padding(8.dp),
			) {
				Text(
					text = album.name,
					color = Color.White,
					maxLines = 1,
					overflow = TextOverflow.Ellipsis,
					style = MaterialTheme.typography.bodyMedium,
				)
				Text(
					text = context.getString(R.string.item_count, album.itemCount),
					color = Color.White.copy(alpha = 0.7f),
					fontSize = 11.sp,
				)
			}
		}
	}
}
