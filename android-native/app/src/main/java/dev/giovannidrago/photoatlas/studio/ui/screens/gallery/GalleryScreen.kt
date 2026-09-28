package dev.giovannidrago.photoatlas.studio.ui.screens.gallery

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.scrollBy
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SelectAll
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.device.PhotoPermissions
import dev.giovannidrago.photoatlas.studio.domain.gallery.DeleteOptions
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryFilter
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryUploadFilter
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryUploadState
import dev.giovannidrago.photoatlas.studio.domain.gallery.galleryIndexAt
import dev.giovannidrago.photoatlas.studio.ui.gallery.GalleryViewModel
import dev.giovannidrago.photoatlas.studio.ui.gallery.UiMessage
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private data class PendingTrash(
	val entries: List<GalleryEntry>,
	val options: DeleteOptions,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GalleryScreen(viewModel: GalleryViewModel = hiltViewModel()) {
	val state by viewModel.state.collectAsStateWithLifecycle()
	val uploadState by viewModel.upload.collectAsStateWithLifecycle()
	val context = LocalContext.current
	val scope = rememberCoroutineScope()
	val listState = rememberLazyGridState()
	val entries = rememberUpdatedState(state.entries)
	val snackbar = remember { SnackbarHostState() }

	val selected = remember { mutableStateListOf<String>() }
	var selectionMode by remember { mutableStateOf(false) }
	var viewerIndex by remember { mutableStateOf<Int?>(null) }
	var showDeleteDialog by remember { mutableStateOf(false) }
	var deleteTargets by remember { mutableStateOf<List<GalleryEntry>>(emptyList()) }
	var pendingTrash by remember { mutableStateOf<PendingTrash?>(null) }
	var showUploadSheet by remember { mutableStateOf(false) }

	// Drag selection state.
	var dragActive by remember { mutableStateOf(false) }
	var dragValue by remember { mutableStateOf(true) }
	var lastIndex by remember { mutableStateOf<Int?>(null) }
	var pendingScroll by remember { mutableStateOf(0) }

	val widthDp = LocalConfiguration.current.screenWidthDp
	val tileSize = ((widthDp - 36) / 3).dp
	val density = LocalDensity.current
	val tilePx = with(density) { tileSize.toPx() }
	val spacingPx = with(density) { 6.dp.toPx() }

	val uploadLabel = stringResource(R.string.gallery_uploading)

	val permissionLauncher = rememberLauncherForActivityResult(
		ActivityResultContracts.RequestMultiplePermissions(),
	) { grants ->
		if (grants.values.all { it }) viewModel.refresh()
	}
	val trashLauncher = rememberLauncherForActivityResult(
		ActivityResultContracts.StartIntentSenderForResult(),
	) { result ->
		val pending = pendingTrash
		pendingTrash = null
		if (pending == null) return@rememberLauncherForActivityResult
		if (result.resultCode == Activity.RESULT_OK) {
			val ids = pending.entries.mapNotNull { it.local?.id }.toSet()
			viewModel.applyDelete(pending.entries, pending.options, ids)
		} else {
			scope.launch { snackbar.showSnackbar(context.getString(R.string.delete_cancelled)) }
		}
	}

	LaunchedEffect(Unit) {
		if (!PhotoPermissions.has(context)) {
			permissionLauncher.launch(PhotoPermissions.required().toTypedArray())
		}
	}

	LaunchedEffect(viewModel) {
		snapshotFlow { viewModel.message }.collect { message ->
			val current = message ?: return@collect
			val detail = current.detail?.let { ": $it" }.orEmpty()
			val text = when (current.kind) {
				UiMessage.Kind.Uploaded -> context.getString(R.string.uploaded_count, current.count)
				UiMessage.Kind.Deleted -> context.getString(R.string.deleted_count, current.count)
				UiMessage.Kind.Shared -> context.getString(R.string.shared_count, current.count)
				UiMessage.Kind.Exported -> context.getString(R.string.export_done) + detail
				UiMessage.Kind.Failed -> context.getString(R.string.action_failed) + detail
			}
			snackbar.showSnackbar(text)
			viewModel.consumeMessage()
		}
	}

	// Load the next cloud page near the end of the grid.
	LaunchedEffect(listState) {
		snapshotFlow { listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }
			.collect { lastVisible ->
				if (state.hasMore && lastVisible >= state.entries.size - 12) viewModel.loadMore()
			}
	}

	// Auto-scroll while dragging near the edges (like the Flutter gallery).
	LaunchedEffect(dragActive) {
		while (dragActive) {
			if (pendingScroll != 0) listState.scrollBy(pendingScroll * 26f)
			delay(60)
		}
	}

	fun scrollOffsetPx(): Float {
		val row = listState.firstVisibleItemIndex / 3
		return row * (tilePx + spacingPx) + listState.firstVisibleItemScrollOffset
	}

	fun applyIndex(index: Int?) {
		val list = entries.value
		if (index == null) return
		val entry = list.getOrNull(index) ?: return
		if (dragValue) {
			if (!selected.contains(entry.key)) selected.add(entry.key)
		} else {
			selected.remove(entry.key)
		}
	}

	fun extendSelection(index: Int?) {
		val last = lastIndex ?: return
		if (index == null) return
		for (position in min(last, index)..max(last, index)) {
			applyIndex(position)
		}
		lastIndex = index
	}

	fun exitSelection() {
		selectionMode = false
		selected.clear()
	}

	fun selectedEntries(): List<GalleryEntry> =
		state.entries.filter { selected.contains(it.key) }

	fun runUpload(entriesToUpload: List<GalleryEntry>) {
		viewModel.startUpload(entriesToUpload, uploadLabel)
		exitSelection()
	}

	fun runShare(entriesToShare: List<GalleryEntry>) {
		viewModel.share(entriesToShare)
		exitSelection()
	}

	fun runDelete(entriesToDelete: List<GalleryEntry>) {
		if (entriesToDelete.isEmpty()) return
		deleteTargets = entriesToDelete
		showDeleteDialog = true
	}

	fun confirmDelete(options: DeleteOptions) {
		val targets = deleteTargets
		showDeleteDialog = false
		if (targets.isEmpty() || (!options.cloud && !options.local)) return
		exitSelection()
		if (!options.local) {
			viewModel.applyDelete(targets, options, emptySet())
			return
		}
		scope.launch {
			val sender = viewModel.trashRequest(targets)
			if (sender != null) {
				pendingTrash = PendingTrash(targets, options)
				trashLauncher.launch(IntentSenderRequest.Builder(sender).build())
			} else {
				val deleted = viewModel.deleteDeviceFiles(targets)
				viewModel.applyDelete(targets, options, deleted)
			}
		}
	}

	Scaffold(
		containerColor = Color.Transparent,
		snackbarHost = { SnackbarHost(snackbar) },
		topBar = {
			if (selectionMode) {
				TopAppBar(
					title = { Text(stringResource(R.string.selected_count, selected.size)) },
					navigationIcon = {
						IconButton(onClick = { exitSelection() }) {
							Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close))
						}
					},
					actions = {
						IconButton(
							onClick = { viewModel.exportMetadata(selectedEntries()) },
							enabled = selected.isNotEmpty(),
						) {
							Icon(
								imageVector = Icons.Filled.Download,
								contentDescription = stringResource(R.string.export_metadata),
							)
						}
						IconButton(
							onClick = {
								if (selected.size == state.entries.size) {
									selected.clear()
								} else {
									selected.clear()
									selected.addAll(state.entries.map { it.key })
								}
							},
						) {
							Icon(
								imageVector = Icons.Filled.SelectAll,
								contentDescription = stringResource(R.string.select_all),
							)
						}
					},
				)
			} else {
				TopAppBar(
					title = { Text(stringResource(R.string.tab_gallery)) },
					actions = {
						IconButton(
							onClick = { viewModel.refresh() },
							enabled = !state.cloudLoading,
						) {
							Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.retry))
						}
					},
				)
			}
		},
		bottomBar = {
			val running = uploadState
			if (running != null) {
				UploadBar(
					state = running,
					onClick = { showUploadSheet = true },
				)
			} else if (selectionMode) {
				SelectionActionBar(
					canUpload = selectedEntries().any { it.canUpload },
					canShare = selectedEntries().any {
						it.hasLocal || !it.cloud?.downloadUrl.isNullOrBlank()
					},
					canDelete = selectedEntries().any { it.canDeleteCloud || it.canDeleteLocal },
					onUpload = { runUpload(selectedEntries()) },
					onShare = { runShare(selectedEntries()) },
					onDelete = { runDelete(selectedEntries()) },
				)
			}
		},
	) { padding ->
		Column(modifier = Modifier.padding(padding)) {
			LazyRow(
				contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
				horizontalArrangement = Arrangement.spacedBy(8.dp),
			) {
				item {
					FilterChip(
						selected = state.filter == GalleryFilter(),
						onClick = { exitSelection(); viewModel.setFilter(GalleryFilter()) },
						label = { Text(stringResource(R.string.all_images)) },
					)
				}
				item {
					FilterChip(
						selected = state.filter.type == "image",
						onClick = { exitSelection(); viewModel.setFilter(GalleryFilter(type = "image")) },
						label = { Text(stringResource(R.string.photos_only)) },
					)
				}
				item {
					FilterChip(
						selected = state.filter.type == "video",
						onClick = { exitSelection(); viewModel.setFilter(GalleryFilter(type = "video")) },
						label = { Text(stringResource(R.string.videos_only)) },
					)
				}
				item {
					FilterChip(
						selected = state.filter.upload == GalleryUploadFilter.Pending,
						onClick = {
							exitSelection()
							viewModel.setFilter(GalleryFilter(upload = GalleryUploadFilter.Pending))
						},
						label = { Text(stringResource(R.string.gallery_not_uploaded)) },
					)
				}
				item {
					FilterChip(
						selected = state.filter.upload == GalleryUploadFilter.Uploaded,
						onClick = {
							exitSelection()
							viewModel.setFilter(GalleryFilter(upload = GalleryUploadFilter.Uploaded))
						},
						label = { Text(stringResource(R.string.gallery_uploaded)) },
					)
				}
				item {
					FilterChip(
						selected = state.filter.missingOnly,
						onClick = {
							exitSelection()
							viewModel.setFilter(GalleryFilter(missingOnly = true))
						},
						label = { Text(stringResource(R.string.missing_metadata_only)) },
					)
				}
			}
			Text(
				text = if (state.deviceLoading) {
					stringResource(R.string.gallery_device_loading)
				} else {
					stringResource(R.string.gallery_counts, state.deviceTotal, state.cloudTotal)
				},
				style = MaterialTheme.typography.labelSmall,
				color = MaterialTheme.colorScheme.onSurfaceVariant,
				modifier = Modifier.padding(horizontal = 12.dp, vertical = 2.dp),
			)
			if (state.permissionDenied) {
				PermissionBanner(onOpenSettings = { PhotoPermissions.openSettings(context) })
			}
			Box(modifier = Modifier.weight(1f)) {
				when {
					state.cloudLoading && state.entries.isEmpty() -> {
						CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
					}

					state.error != null && state.entries.isEmpty() -> {
						Column(
							modifier = Modifier.align(Alignment.Center),
							horizontalAlignment = Alignment.CenterHorizontally,
						) {
							Text(text = state.error.orEmpty())
							Spacer(Modifier.height(8.dp))
							TextButton(onClick = { viewModel.refresh() }) {
								Text(stringResource(R.string.retry))
							}
						}
					}

					state.entries.isEmpty() -> {
						Text(
							text = stringResource(R.string.gallery_empty),
							modifier = Modifier
								.align(Alignment.Center)
								.padding(24.dp),
						)
					}

					else -> {
						PullToRefreshBox(
							isRefreshing = state.cloudLoading,
							onRefresh = { viewModel.refresh() },
							modifier = Modifier.fillMaxSize(),
						) {
							LazyVerticalGrid(
								columns = GridCells.Fixed(3),
								state = listState,
								contentPadding = PaddingValues(12.dp),
								verticalArrangement = Arrangement.spacedBy(6.dp),
								horizontalArrangement = Arrangement.spacedBy(6.dp),
								modifier = Modifier
									.fillMaxSize()
									.pointerInput(tilePx) {
										detectDragGesturesAfterLongPress(
											onDragStart = { offset ->
												val index = galleryIndexAt(
													localX = offset.x,
													localY = offset.y,
													scrollOffset = scrollOffsetPx(),
													tileSize = tilePx,
													crossAxisCount = 3,
													itemCount = entries.value.size,
												)
												val entry = index?.let { entries.value.getOrNull(it) }
													?: return@detectDragGesturesAfterLongPress
												dragValue = !selected.contains(entry.key)
												selectionMode = true
												applyIndex(index)
												lastIndex = index
												dragActive = true
											},
											onDrag = { change, _ ->
												change.consume()
												val index = galleryIndexAt(
													localX = change.position.x,
													localY = change.position.y,
													scrollOffset = scrollOffsetPx(),
													tileSize = tilePx,
													crossAxisCount = 3,
													itemCount = entries.value.size,
												)
												extendSelection(index)
												pendingScroll = when {
													change.position.y < 72f -> -1
													change.position.y > size.height - 72f -> 1
													else -> 0
												}
											},
											onDragEnd = {
												dragActive = false
												pendingScroll = 0
												lastIndex = null
												if (selected.isEmpty()) selectionMode = false
											},
											onDragCancel = {
												dragActive = false
												pendingScroll = 0
												lastIndex = null
												if (selected.isEmpty()) selectionMode = false
											},
										)
									},
							) {
								items(state.entries, key = { it.key }) { entry ->
									GalleryTile(
										entry = entry,
										size = tileSize,
										selectionMode = selectionMode,
										selected = selected.contains(entry.key),
										onTap = {
											if (selectionMode) {
												if (!selected.remove(entry.key)) selected.add(entry.key)
												if (selected.isEmpty()) selectionMode = false
											} else {
												viewerIndex = state.entries.indexOf(entry)
											}
										},
									)
								}
								if (state.loadingMore) {
									item(span = { GridItemSpan(3) }) {
										Box(
											modifier = Modifier
												.fillMaxWidth()
												.padding(12.dp),
											contentAlignment = Alignment.Center,
										) {
											CircularProgressIndicator(
												modifier = Modifier.size(22.dp),
												strokeWidth = 2.dp,
											)
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}

	if (showDeleteDialog) {
		DeleteMediaDialog(
			entries = deleteTargets,
			onDismiss = { showDeleteDialog = false },
			onConfirm = { options -> confirmDelete(options) },
		)
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

	val index = viewerIndex
	if (index != null && index in state.entries.indices) {
		MediaViewerDialog(
			entries = state.entries,
			initialIndex = index,
			onDismiss = { viewerIndex = null },
			onSelect = { entry ->
				viewerIndex = null
				selectionMode = true
				if (!selected.contains(entry.key)) selected.add(entry.key)
			},
			onShare = { entry -> viewModel.share(listOf(entry)) },
			onUpload = { entry ->
				viewerIndex = null
				viewModel.startUpload(listOf(entry), uploadLabel)
			},
			onDelete = { entry ->
				viewerIndex = null
				runDelete(listOf(entry))
			},
		)
	}
}

@Composable
private fun UploadBar(state: GalleryUploadState, onClick: () -> Unit) {
	Column(
		modifier = Modifier
			.fillMaxWidth()
			.background(MaterialTheme.colorScheme.surfaceContainer)
			.padding(horizontal = 16.dp, vertical = 8.dp),
	) {
		Row(verticalAlignment = Alignment.CenterVertically) {
			Text(
				text = state.currentName ?: state.label,
				style = MaterialTheme.typography.bodySmall,
				maxLines = 1,
				modifier = Modifier.weight(1f),
			)
			Text(
				text = "${state.done}/${state.total}",
				style = MaterialTheme.typography.labelSmall,
			)
		}
		Spacer(Modifier.height(4.dp))
		LinearProgressIndicator(
			value = state.overallFraction?.toFloat(),
			modifier = Modifier.fillMaxWidth(),
		)
		Spacer(Modifier.height(2.dp))
		TextButton(onClick = onClick, modifier = Modifier.align(Alignment.End)) {
			Text(stringResource(R.string.upload_details))
		}
	}
}

@Composable
private fun SelectionActionBar(
	canUpload: Boolean,
	canShare: Boolean,
	canDelete: Boolean,
	onUpload: () -> Unit,
	onShare: () -> Unit,
	onDelete: () -> Unit,
) {
	Row(
		modifier = Modifier
			.fillMaxWidth()
			.background(MaterialTheme.colorScheme.surfaceContainer)
			.padding(horizontal = 8.dp, vertical = 4.dp),
	) {
		TextButton(
			onClick = onUpload,
			enabled = canUpload,
			modifier = Modifier.weight(1f),
		) {
			Icon(Icons.Filled.Upload, contentDescription = null, modifier = Modifier.size(18.dp))
			Spacer(Modifier.size(6.dp))
			Text(stringResource(R.string.gallery_upload))
		}
		TextButton(
			onClick = onShare,
			enabled = canShare,
			modifier = Modifier.weight(1f),
		) {
			Icon(Icons.Filled.Share, contentDescription = null, modifier = Modifier.size(18.dp))
			Spacer(Modifier.size(6.dp))
			Text(stringResource(R.string.gallery_share))
		}
		TextButton(
			onClick = onDelete,
			enabled = canDelete,
			modifier = Modifier.weight(1f),
		) {
			Icon(Icons.Filled.DeleteOutline, contentDescription = null, modifier = Modifier.size(18.dp))
			Spacer(Modifier.size(6.dp))
			Text(stringResource(R.string.gallery_delete))
		}
	}
}

@Composable
private fun PermissionBanner(onOpenSettings: () -> Unit) {
	Row(
		modifier = Modifier
			.fillMaxWidth()
			.padding(horizontal = 12.dp, vertical = 4.dp)
			.background(
				color = MaterialTheme.colorScheme.errorContainer,
				shape = MaterialTheme.shapes.small,
			)
			.padding(horizontal = 12.dp, vertical = 8.dp),
		verticalAlignment = Alignment.CenterVertically,
	) {
		Icon(
			imageVector = Icons.Filled.PhotoLibrary,
			contentDescription = null,
			tint = MaterialTheme.colorScheme.onErrorContainer,
			modifier = Modifier.size(20.dp),
		)
		Text(
			text = stringResource(R.string.gallery_local_permission_denied),
			modifier = Modifier
				.weight(1f)
				.padding(horizontal = 8.dp),
			style = MaterialTheme.typography.bodySmall,
			color = MaterialTheme.colorScheme.onErrorContainer,
		)
		TextButton(onClick = onOpenSettings) {
			Icon(Icons.Filled.Settings, contentDescription = null, modifier = Modifier.size(18.dp))
			Text(text = stringResource(R.string.gallery_open_settings))
		}
	}
}
