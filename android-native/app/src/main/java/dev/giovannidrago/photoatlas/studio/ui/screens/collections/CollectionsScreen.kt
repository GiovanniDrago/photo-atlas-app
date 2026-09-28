package dev.giovannidrago.photoatlas.studio.ui.screens.collections

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Timeline
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import coil.request.ImageRequest
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.device.DeviceFolder
import dev.giovannidrago.photoatlas.studio.data.device.PhotoPermissions
import dev.giovannidrago.photoatlas.studio.ui.collections.CollectionsViewModel
import dev.giovannidrago.photoatlas.studio.ui.gallery.UiMessage
import dev.giovannidrago.photoatlas.studio.ui.screens.gallery.UploadProgressBar
import dev.giovannidrago.photoatlas.studio.ui.screens.gallery.UploadProgressSheet
import dev.giovannidrago.photoatlas.studio.ui.screens.gallery.formatDate

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CollectionsScreen(
	viewModel: CollectionsViewModel = hiltViewModel(),
	onOpenTimeline: () -> Unit = {},
	onOpenFolder: (DeviceFolder) -> Unit = {},
) {
	val state by viewModel.state.collectAsStateWithLifecycle()
	val uploadState by viewModel.upload.collectAsStateWithLifecycle()
	val snackbar = remember { SnackbarHostState() }
	val context = LocalContext.current
	var showUploadSheet by remember { mutableStateOf(false) }
	val uploadLabel = stringResource(R.string.folder_auto_upload)

	LaunchedEffect(viewModel) {
		viewModel.message?.let { message: UiMessage ->
			val detail = message.detail?.let { ": $it" }.orEmpty()
			val text = when (message.kind) {
				UiMessage.Kind.Uploaded -> context.getString(R.string.uploaded_count, message.count)
				UiMessage.Kind.Failed -> context.getString(R.string.action_failed) + detail
				else -> context.getString(R.string.action_failed) + detail
			}
			snackbar.showSnackbar(text)
			viewModel.dismissMessage()
		}
	}

	Scaffold(
		containerColor = MaterialTheme.colorScheme.background,
		topBar = {
			TopAppBar(
				title = { Text(stringResource(R.string.tab_collections)) },
				actions = {
					IconButton(onClick = { viewModel.refresh() }, enabled = !state.loading) {
						Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.retry))
					}
				},
			)
		},
		snackbarHost = { SnackbarHost(snackbar) },
		bottomBar = {
			val running = uploadState
			if (running != null) {
				UploadProgressBar(state = running, onClick = { showUploadSheet = true })
			}
		},
	) { padding ->
		PullToRefreshBox(
			isRefreshing = state.loading,
			onRefresh = { viewModel.refresh() },
			modifier = Modifier
				.fillMaxSize()
				.padding(padding),
		) {
			val entries = state.folders
			if (entries.isEmpty() && state.loading) {
				CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
			} else {
				LazyColumn(
					modifier = Modifier.fillMaxSize(),
					contentPadding = PaddingValues(12.dp),
					verticalArrangement = Arrangement.spacedBy(10.dp),
				) {
					item {
						TimelineCard(
							entries = state.preview,
							loading = state.loading,
							onClick = onOpenTimeline,
						)
					}
					item {
						Column {
							Text(
								text = stringResource(R.string.collections_folders),
								style = MaterialTheme.typography.titleMedium,
							)
							Text(
								text = stringResource(R.string.collections_folders_hint),
								style = MaterialTheme.typography.bodySmall,
								color = MaterialTheme.colorScheme.onSurfaceVariant,
							)
						}
					}
					if (state.permissionDenied) {
						item {
							PermissionRow(onOpenSettings = { PhotoPermissions.openSettings(context) })
						}
					}
					if (state.folders.isEmpty() && !state.loading) {
						item {
							Text(
								text = stringResource(R.string.collections_empty),
								modifier = Modifier.padding(vertical = 24.dp),
							)
						}
					}
					items(state.folders.size) { index ->
						val folder = state.folders[index]
						FolderCard(
							folder = folder,
							thumbUri = state.thumbs[folder.id]?.uri,
							status = state.statusFor(folder.id),
							autoBackup = state.autoBackup(folder.id),
							preparing = folder.id in viewModel.preparingFolderIds,
							onOpen = { onOpenFolder(folder) },
							onToggle = { enabled ->
								viewModel.toggle(folder, enabled, uploadLabel)
							},
						)
					}
				}
			}
		}
	}

	val sheetUpload = uploadState
	if (showUploadSheet && sheetUpload != null) {
		val sheetState = rememberModalBottomSheetState()
		ModalBottomSheet(
			onDismissRequest = { showUploadSheet = false },
			sheetState = sheetState,
		) {
			UploadProgressSheet(
				state = sheetUpload,
				onStop = { viewModel.cancelUpload() },
				onDismiss = {
					showUploadSheet = false
					viewModel.dismissUpload()
				},
			)
		}
	}
}

@Composable
private fun TimelineCard(
	entries: List<dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry>,
	loading: Boolean,
	onClick: () -> Unit,
) {
	val context = LocalContext.current
	Card(
		modifier = Modifier
			.fillMaxWidth()
			.height(200.dp)
			.clickable(onClick = onClick),
		shape = RoundedCornerShape(16.dp),
	) {
		Box(modifier = Modifier.fillMaxSize()) {
			if (entries.isEmpty()) {
				Box(
					modifier = Modifier
						.fillMaxSize()
						.background(MaterialTheme.colorScheme.surfaceContainerHighest),
					contentAlignment = Alignment.Center,
				) {
					if (loading) {
						CircularProgressIndicator()
					} else {
						Icon(
							imageVector = Icons.Filled.Timeline,
							contentDescription = null,
							tint = MaterialTheme.colorScheme.onSurfaceVariant,
							modifier = Modifier.size(42.dp),
						)
					}
				}
			} else {
				Row(modifier = Modifier.fillMaxSize()) {
					for ((index, entry) in entries.take(4).withIndex()) {
						val model: Any? = entry.local?.uri ?: entry.cloud?.thumbnailUrl
						Box(
							modifier = Modifier
								.weight(1f)
								.fillMaxSize()
								.padding(end = if (index < 3) 2.dp else 0.dp),
						) {
							if (model != null) {
								AsyncImage(
									model = ImageRequest.Builder(context).data(model).crossfade(true).build(),
									contentDescription = null,
									contentScale = ContentScale.Crop,
									modifier = Modifier
										.fillMaxSize(),
								)
							}
						}
					}
				}
			}
			Box(
				modifier = Modifier
					.fillMaxSize()
					.background(
						Brush.verticalGradient(
							colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.65f)),
							startY = 120f,
						),
					),
			)
			Row(
				modifier = Modifier
					.align(Alignment.BottomStart)
					.fillMaxWidth()
					.padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
				verticalAlignment = Alignment.CenterVertically,
			) {
				Icon(
					imageVector = Icons.Filled.Timeline,
					contentDescription = null,
					tint = Color.White,
					modifier = Modifier.size(20.dp),
				)
				Spacer(Modifier.width(8.dp))
				Column(modifier = Modifier.weight(1f)) {
					Text(
						text = stringResource(R.string.timeline_title),
						color = Color.White,
						fontSize = 16.sp,
						style = MaterialTheme.typography.titleMedium,
					)
					Text(
						text = stringResource(R.string.timeline_subtitle),
						color = Color.White.copy(alpha = 0.7f),
						fontSize = 11.sp,
						maxLines = 1,
						overflow = TextOverflow.Ellipsis,
					)
				}
				Icon(
					imageVector = Icons.Filled.ChevronRight,
					contentDescription = null,
					tint = Color.White.copy(alpha = 0.7f),
				)
			}
		}
	}
}

@Composable
private fun FolderCard(
	folder: DeviceFolder,
	thumbUri: String?,
	status: dev.giovannidrago.photoatlas.studio.data.remote.BackupSourceStatusDto?,
	autoBackup: Boolean,
	preparing: Boolean,
	onOpen: () -> Unit,
	onToggle: (Boolean) -> Unit,
) {
	val context = LocalContext.current
	Card(
		modifier = Modifier
			.fillMaxWidth()
			.clickable(onClick = onOpen),
	) {
		Column(modifier = Modifier.padding(12.dp)) {
			Row(verticalAlignment = Alignment.CenterVertically) {
				Box(
					modifier = Modifier
						.size(56.dp)
						.clip(RoundedCornerShape(10.dp))
						.background(MaterialTheme.colorScheme.surfaceContainerHighest),
					contentAlignment = Alignment.Center,
				) {
					if (thumbUri != null) {
						AsyncImage(
							model = ImageRequest.Builder(context).data(thumbUri).crossfade(true).build(),
							contentDescription = null,
							contentScale = ContentScale.Crop,
							modifier = Modifier.fillMaxSize(),
						)
					} else {
						Icon(
							imageVector = Icons.Filled.Folder,
							contentDescription = null,
							tint = MaterialTheme.colorScheme.onSurfaceVariant,
						)
					}
				}
				Spacer(Modifier.width(12.dp))
				Column(modifier = Modifier.weight(1f)) {
					Text(
						text = folder.name,
						style = MaterialTheme.typography.titleSmall,
						maxLines = 1,
						overflow = TextOverflow.Ellipsis,
					)
					Text(
						text = "${folder.path} · ${context.getString(R.string.item_count, folder.count)}",
						style = MaterialTheme.typography.labelSmall,
						color = MaterialTheme.colorScheme.onSurfaceVariant,
						maxLines = 1,
						overflow = TextOverflow.Ellipsis,
					)
					if (status != null) {
						val parts = mutableListOf(
							context.getString(
								R.string.folder_uploaded_of,
								status.uploaded,
								status.total,
							),
						)
						if (status.failed > 0) {
							parts += context.getString(R.string.failed_count, status.failed)
						}
						formatDate(
							dev.giovannidrago.photoatlas.studio.data.remote.Iso.date(
								status.backupLastRunAt,
							),
						)?.let { moment ->
							parts += context.getString(R.string.folder_last_run, moment)
						}
						Text(
							text = parts.joinToString(" · "),
							style = MaterialTheme.typography.labelSmall,
							color = MaterialTheme.colorScheme.onSurfaceVariant,
						)
					}
				}
				Icon(
					imageVector = Icons.Filled.ChevronRight,
					contentDescription = null,
					tint = MaterialTheme.colorScheme.onSurfaceVariant,
					modifier = Modifier.size(18.dp),
				)
			}
			Spacer(Modifier.height(4.dp))
			Row(verticalAlignment = Alignment.CenterVertically) {
				Text(
					text = stringResource(R.string.folder_auto_upload),
					style = MaterialTheme.typography.bodyMedium,
					modifier = Modifier.weight(1f),
				)
				if (preparing) {
					CircularProgressIndicator(
						modifier = Modifier.size(18.dp),
						strokeWidth = 2.dp,
					)
				} else {
					Switch(checked = autoBackup, onCheckedChange = onToggle)
				}
			}
		}
	}
}

@Composable
private fun PermissionRow(onOpenSettings: () -> Unit) {
	Row(
		modifier = Modifier
			.fillMaxWidth()
			.background(
				color = MaterialTheme.colorScheme.errorContainer,
				shape = MaterialTheme.shapes.small,
			)
			.padding(horizontal = 12.dp, vertical = 8.dp),
		verticalAlignment = Alignment.CenterVertically,
	) {
		Text(
			text = stringResource(R.string.gallery_local_permission_denied),
			modifier = Modifier.weight(1f),
			style = MaterialTheme.typography.bodySmall,
			color = MaterialTheme.colorScheme.onErrorContainer,
		)
		TextButton(onClick = onOpenSettings) {
			Icon(Icons.Filled.Settings, contentDescription = null, modifier = Modifier.size(18.dp))
			Text(stringResource(R.string.gallery_open_settings))
		}
	}
}
