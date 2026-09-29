package dev.giovannidrago.photoatlas.studio.ui.screens.timeline

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PlaylistAdd
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Today
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import coil.request.ImageRequest
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.remote.TimelineBucketDto
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.ui.screens.gallery.DeleteMediaDialog
import dev.giovannidrago.photoatlas.studio.ui.screens.gallery.MediaViewerDialog
import dev.giovannidrago.photoatlas.studio.ui.screens.gallery.SelectionAction
import dev.giovannidrago.photoatlas.studio.ui.screens.gallery.SelectionActionBar
import dev.giovannidrago.photoatlas.studio.ui.screens.gallery.durationLabel
import dev.giovannidrago.photoatlas.studio.ui.timeline.TimelineBucketState
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import dev.giovannidrago.photoatlas.studio.ui.timeline.TimelineViewModel
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimelineScreen(
	viewModel: TimelineViewModel = hiltViewModel(),
	albumsViewModel: dev.giovannidrago.photoatlas.studio.ui.albums.AlbumsViewModel? = null,
	onBack: () -> Unit = {},
) {
	val buckets by viewModel.buckets.collectAsStateWithLifecycle()
	val loading by viewModel.loading.collectAsStateWithLifecycle()
	val error by viewModel.error.collectAsStateWithLifecycle()
	val items by viewModel.items.collectAsStateWithLifecycle()
	val outcome by viewModel.outcome.collectAsStateWithLifecycle()
	val context = LocalContext.current
	val scope = rememberCoroutineScope()
	val snackbar = remember { SnackbarHostState() }
	val selected = remember { mutableStateListOf<String>() }
	var selectionMode by remember { mutableStateOf(false) }
	var viewerBucket by remember { mutableStateOf<Int?>(null) }
	var viewerIndex by remember { mutableStateOf(0) }
	var showDeleteDialog by remember { mutableStateOf(false) }
	var showAlbumPicker by remember { mutableStateOf(false) }
	BackHandler { onBack() }

	// Cloud data can change while the screen is in the background (kDrive scans,
	// uploads, server address fixes): refresh when it comes back to the front.
	val lifecycleOwner = LocalLifecycleOwner.current
	var pausedOnce by remember { mutableStateOf(false) }
	DisposableEffect(lifecycleOwner) {
		val observer = LifecycleEventObserver { _, event ->
			when (event) {
				Lifecycle.Event.ON_PAUSE -> pausedOnce = true
				Lifecycle.Event.ON_RESUME -> if (pausedOnce) viewModel.refresh()
				else -> Unit
			}
		}
		lifecycleOwner.lifecycle.addObserver(observer)
		onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
	}

	LaunchedEffect(outcome) {
		val current = outcome ?: return@LaunchedEffect
		val text = when {
			current.error != null ->
				"${context.getString(R.string.action_failed)}: ${current.error}"
			current.deleted > 0 -> context.getString(R.string.deleted_count, current.deleted)
			else -> context.getString(R.string.shared_count, current.shared)
		}
		snackbar.showSnackbar(text)
		viewModel.consumeOutcome()
	}

	fun selectedEntries(): List<GalleryEntry> =
		items.values.flatMap { it.items }.filter { selected.contains(it.key) }

	fun exitSelection() {
		selectionMode = false
		selected.clear()
	}

	Scaffold(
		containerColor = MaterialTheme.colorScheme.background,
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
				)
			} else {
				TopAppBar(
					title = { Text(stringResource(R.string.timeline_title)) },
					navigationIcon = {
						IconButton(onClick = onBack) {
							Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
						}
					},
				)
			}
		},
		bottomBar = {
			if (selectionMode) {
				SelectionActionBar(
					actions = listOf(
						SelectionAction(
							icon = Icons.Filled.Share,
							label = stringResource(R.string.gallery_share),
							onClick = {
								viewModel.share(selectedEntries())
								exitSelection()
							},
						),
						SelectionAction(
							icon = Icons.Filled.Download,
							label = stringResource(R.string.download_original),
							onClick = {
								var failed = 0
								for (entry in selectedEntries()) {
									val url = entry.cloud?.downloadUrl
									if (url.isNullOrBlank() || !openExternally(context, url)) failed += 1
								}
								if (failed > 0) {
									scope.launch {
										snackbar.showSnackbar(context.getString(R.string.download_unavailable))
									}
								}
								exitSelection()
							},
						),
						SelectionAction(
							icon = Icons.Filled.PlaylistAdd,
							label = stringResource(R.string.album_add),
							enabled = albumsViewModel != null,
							onClick = { showAlbumPicker = true },
						),
						SelectionAction(
							icon = Icons.Filled.DeleteOutline,
							label = stringResource(R.string.gallery_delete),
							onClick = { showDeleteDialog = true },
						),
					),
				)
			}
		},
	) { padding ->
		PullToRefreshBox(
			isRefreshing = loading,
			onRefresh = { viewModel.refresh() },
			modifier = Modifier
				.fillMaxSize()
				.padding(padding),
		) {
			when {
				loading && buckets.isEmpty() -> {
					CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
				}

				error != null && buckets.isEmpty() -> {
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

				buckets.isEmpty() -> {
					Text(
						text = stringResource(R.string.timeline_empty),
						modifier = Modifier
							.align(Alignment.Center)
							.padding(24.dp),
					)
				}

				else -> {
					LazyColumn(
						modifier = Modifier.fillMaxSize(),
						contentPadding = PaddingValues(12.dp),
						verticalArrangement = Arrangement.spacedBy(12.dp),
					) {
						itemsIndexed(buckets) { index, bucket ->
							LaunchedEffect(bucket.bucketStart) { viewModel.loadBucket(bucket) }
							BucketCard(
								bucket = bucket,
								state = items[bucket.bucketStart],
								selectionMode = selectionMode,
								selected = selected,
								onTap = { entry, entryIndex ->
									if (selectionMode) {
										if (!selected.remove(entry.key)) selected.add(entry.key)
										if (selected.isEmpty()) selectionMode = false
									} else {
										viewerBucket = index
										viewerIndex = entryIndex
									}
								},
								onLongPress = { entry ->
									selectionMode = true
									if (!selected.contains(entry.key)) selected.add(entry.key)
								},
							)
						}
					}
				}
			}
		}
	}

	if (showDeleteDialog) {
		DeleteMediaDialog(
			entries = selectedEntries(),
			onDismiss = { showDeleteDialog = false },
			onConfirm = { options, _ ->
				viewModel.delete(selectedEntries(), cloud = options.cloud)
				showDeleteDialog = false
				exitSelection()
			},
		)
	}

	if (showAlbumPicker && albumsViewModel != null) {
		val sheetState = rememberModalBottomSheetState()
		ModalBottomSheet(
			onDismissRequest = { showAlbumPicker = false },
			sheetState = sheetState,
		) {
			dev.giovannidrago.photoatlas.studio.ui.screens.albums.AlbumPickerSheet(
				viewModel = albumsViewModel,
				entries = selectedEntries(),
				onDismiss = { showAlbumPicker = false },
				onResult = { outcome ->
					showAlbumPicker = false
					exitSelection()
					if (outcome.failed > 0) {
						context.getString(R.string.action_failed)
					}
				},
			)
		}
	}

	val bucketIndex = viewerBucket
	if (bucketIndex != null) {
		val current = items[buckets.getOrNull(bucketIndex)?.bucketStart ?: ""]?.items.orEmpty()
		if (current.isNotEmpty()) {
			MediaViewerDialog(
				entries = current,
				initialIndex = viewerIndex.coerceIn(0, current.size - 1),
				onDismiss = { viewerBucket = null },
				onSelect = { entry ->
					viewerBucket = null
					selectionMode = true
					if (!selected.contains(entry.key)) selected.add(entry.key)
				},
				onShare = { entry -> viewModel.share(listOf(entry)) },
				onDelete = { entry ->
					viewerBucket = null
					viewModel.delete(listOf(entry), cloud = true)
				},
				loadNext = { viewModel.bucketEntries(bucketIndex + 1) },
				loadPrevious = { viewModel.bucketEntries(bucketIndex - 1) },
			)
		}
	}
}

@Composable
private fun BucketCard(
	bucket: TimelineBucketDto,
	state: TimelineBucketState?,
	selectionMode: Boolean,
	selected: List<String>,
	onTap: (GalleryEntry, Int) -> Unit,
	onLongPress: (GalleryEntry) -> Unit,
) {
	val context = LocalContext.current
	val icon = when (bucket.granularity) {
		"day" -> Icons.Filled.Today
		"week" -> Icons.Filled.DateRange
		else -> Icons.Filled.CalendarMonth
	}
	Card(modifier = Modifier.fillMaxWidth()) {
		Column(modifier = Modifier.padding(12.dp)) {
			Row(verticalAlignment = Alignment.CenterVertically) {
				Icon(
					imageVector = icon,
					contentDescription = null,
					tint = MaterialTheme.colorScheme.primary,
					modifier = Modifier.size(18.dp),
				)
				Spacer(Modifier.width(8.dp))
				Text(
					text = bucketLabel(bucket),
					style = MaterialTheme.typography.titleSmall,
				)
				Spacer(Modifier.weight(1f))
				Text(
					text = context.getString(R.string.item_count, bucket.count),
					style = MaterialTheme.typography.labelMedium,
				)
			}
			Spacer(Modifier.height(10.dp))
			Box(
				modifier = Modifier.height(110.dp),
				contentAlignment = Alignment.CenterStart,
			) {
				when {
					state == null || state.loading -> {
						CircularProgressIndicator(
							modifier = Modifier.size(22.dp),
							strokeWidth = 2.dp,
						)
					}

					state.error != null -> {
						Text(
							text = stringResource(R.string.error_loading_short),
							style = MaterialTheme.typography.bodySmall,
						)
					}

					state.items.isEmpty() -> {
						Text(
							text = stringResource(R.string.timeline_bucket_empty),
							style = MaterialTheme.typography.bodySmall,
						)
					}

					else -> {
						LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
							itemsIndexed(state.items) { index, entry ->
								val model: Any? = entry.local?.uri ?: entry.cloud?.thumbnailUrl
								Box(
									modifier = Modifier
										.size(110.dp)
										.clip(RoundedCornerShape(14.dp))
										.background(MaterialTheme.colorScheme.surfaceContainerHighest)
										.clickable { onTap(entry, index) },
								) {
									if (model != null) {
										AsyncImage(
											model = ImageRequest.Builder(context).data(model).crossfade(true).build(),
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
													Color.Black.copy(alpha = 0.54f),
													RoundedCornerShape(8.dp),
												)
												.padding(horizontal = 6.dp, vertical = 2.dp),
											verticalAlignment = Alignment.CenterVertically,
										) {
											Text(
												text = durationLabel(entry.durationS),
												color = Color.White,
												style = MaterialTheme.typography.labelSmall,
											)
										}
									}
									if (selectionMode) {
										Box(
											modifier = Modifier
												.align(Alignment.TopStart)
												.padding(6.dp)
												.size(20.dp)
												.background(
													if (selected.contains(entry.key)) {
														MaterialTheme.colorScheme.primary
													} else {
														MaterialTheme.colorScheme.surface.copy(alpha = 0.85f)
													},
													RoundedCornerShape(10.dp),
												),
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

/** `YYYY-MM-DD`, `YYYY-MM-DD / MM-DD` and `YYYY-MM` labels (Flutter parity). */
internal fun bucketLabel(bucket: TimelineBucketDto): String {
	val zone = ZoneId.systemDefault()
	val start = bucket.startMs?.let { Instant.ofEpochMilli(it).atZone(zone).toLocalDate() }
	val end = bucket.endMs?.let { Instant.ofEpochMilli(it).atZone(zone).toLocalDate() }
	return when (bucket.granularity) {
		"day" -> start?.format(DateTimeFormatter.ISO_LOCAL_DATE) ?: bucket.bucketStart
		"week" -> {
			val lastDay = end?.minusDays(1)
			if (start != null && lastDay != null) {
				"${start.format(DateTimeFormatter.ISO_LOCAL_DATE)} / " +
					lastDay.format(DateTimeFormatter.ofPattern("MM-dd"))
			} else {
				bucket.bucketStart
			}
		}

		else -> start?.let { DateTimeFormatter.ofPattern("yyyy-MM").format(it) }
			?: bucket.bucketStart
	}
}

private fun openExternally(context: Context, url: String): Boolean = try {
	context.startActivity(
		Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
	)
	true
} catch (_: ActivityNotFoundException) {
	false
}
