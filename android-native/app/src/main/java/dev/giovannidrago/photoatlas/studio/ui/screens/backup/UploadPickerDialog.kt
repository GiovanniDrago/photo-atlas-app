package dev.giovannidrago.photoatlas.studio.ui.screens.backup

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import coil.request.ImageRequest
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMedia
import dev.giovannidrago.photoatlas.studio.data.device.PhotoPermissions
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.ui.backup.BackupScreenState

/** Full screen multi-selection of the device library for manual uploads. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UploadPickerDialog(
	state: BackupScreenState,
	onDismiss: () -> Unit,
	onUpload: (List<GalleryEntry>) -> Unit,
) {
	val selected = remember { mutableStateListOf<Long>() }
	val context = LocalContext.current

	Dialog(
		onDismissRequest = onDismiss,
		properties = DialogProperties(
			usePlatformDefaultWidth = false,
			decorFitsSystemWindows = false,
		),
	) {
		Surface(modifier = Modifier.fillMaxSize()) {
			Scaffold(
				topBar = {
					TopAppBar(
						title = { Text(stringResource(R.string.backup_picker_title)) },
						navigationIcon = {
							IconButton(onClick = onDismiss) {
								Icon(
									imageVector = Icons.Filled.Close,
									contentDescription = stringResource(R.string.close),
								)
							}
						},
						actions = {
							TextButton(
								onClick = {
									val chosen = state.pickerItems.filter { it.id in selected }
									onUpload(chosen.map { GalleryEntry(local = it) })
								},
								enabled = selected.isNotEmpty(),
							) {
								Text(stringResource(R.string.backup_upload_count, selected.size))
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
					when {
						state.pickerLoading -> Box(
							modifier = Modifier.fillMaxSize(),
							contentAlignment = Alignment.Center,
						) {
							CircularProgressIndicator()
						}

						state.pickerDenied -> Column(
							modifier = Modifier
								.fillMaxSize()
								.padding(24.dp),
							horizontalAlignment = Alignment.CenterHorizontally,
							verticalArrangement = Arrangement.Center,
						) {
							Text(
								text = stringResource(R.string.backup_no_permission),
								style = MaterialTheme.typography.bodyMedium,
							)
							Button(
								onClick = { PhotoPermissions.openSettings(context) },
								modifier = Modifier.padding(top = 12.dp),
							) {
								Text(stringResource(R.string.gallery_open_settings))
							}
						}

						state.pickerItems.isEmpty() -> Box(
							modifier = Modifier.fillMaxSize(),
							contentAlignment = Alignment.Center,
						) {
							Text(
								text = stringResource(R.string.gallery_empty),
								style = MaterialTheme.typography.bodyMedium,
								color = MaterialTheme.colorScheme.onSurfaceVariant,
							)
						}

						else -> {
							Row(
								modifier = Modifier
									.fillMaxWidth()
									.padding(horizontal = 12.dp),
								verticalAlignment = Alignment.CenterVertically,
							) {
								Text(
									text = stringResource(
										R.string.backup_selected_count,
										selected.size,
									),
									style = MaterialTheme.typography.bodySmall,
									modifier = Modifier.weight(1f),
								)
								TextButton(
									onClick = {
										if (selected.size == state.pickerItems.size) {
											selected.clear()
										} else {
											selected.clear()
											selected.addAll(state.pickerItems.map { it.id })
										}
									},
								) {
									Text(
										stringResource(
											if (selected.size == state.pickerItems.size) {
												R.string.backup_deselect_all
											} else {
												R.string.backup_select_all
											},
										),
									)
								}
							}
							LazyVerticalGrid(
								columns = GridCells.Adaptive(110.dp),
								modifier = Modifier.fillMaxSize(),
								contentPadding = androidx.compose.foundation.layout.PaddingValues(4.dp),
								horizontalArrangement = Arrangement.spacedBy(4.dp),
								verticalArrangement = Arrangement.spacedBy(4.dp),
							) {
								items(state.pickerItems, key = { it.id }) { media ->
									PickerTile(
										media = media,
										selected = media.id in selected,
										onTap = {
											if (media.id in selected) {
												selected.remove(media.id)
											} else {
												selected.add(media.id)
											}
										},
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

@Composable
private fun PickerTile(media: DeviceMedia, selected: Boolean, onTap: () -> Unit) {
	Box(
		modifier = Modifier
			.aspectRatio(1f)
			.clip(RoundedCornerShape(10.dp))
			.background(MaterialTheme.colorScheme.surfaceContainerHighest)
			.clickable(onClick = onTap),
	) {
		AsyncImage(
			model = ImageRequest.Builder(LocalContext.current)
				.data(media.uri)
				.crossfade(true)
				.build(),
			contentDescription = media.name,
			contentScale = ContentScale.Crop,
			modifier = Modifier.fillMaxSize(),
		)
		if (media.isVideo) {
			Icon(
				imageVector = Icons.Filled.PlayArrow,
				contentDescription = null,
				tint = Color.White,
				modifier = Modifier
					.align(Alignment.BottomStart)
					.padding(4.dp)
					.size(18.dp),
			)
		}
		if (selected) {
			Box(
				modifier = Modifier
					.fillMaxSize()
					.background(MaterialTheme.colorScheme.primary.copy(alpha = 0.25f)),
				contentAlignment = Alignment.TopEnd,
			) {
				Icon(
					imageVector = Icons.Filled.Check,
					contentDescription = null,
					tint = Color.White,
					modifier = Modifier
						.padding(6.dp)
						.size(20.dp),
				)
			}
		}
	}
}
