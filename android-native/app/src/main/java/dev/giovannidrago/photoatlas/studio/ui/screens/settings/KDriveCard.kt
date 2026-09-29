package dev.giovannidrago.photoatlas.studio.ui.screens.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.remote.MediaSourceDto
import dev.giovannidrago.photoatlas.studio.ui.settings.KDriveState
import dev.giovannidrago.photoatlas.studio.ui.settings.KDriveViewModel
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private const val TokenPageUrl = "https://manager.infomaniak.com/v3/ng/accounts/token/list"
private const val WebAppUrl = "https://ksuite.infomaniak.com/all/kdrive/app/drive"

/** Settings → kDrive: connection, folder scans, previews and enrichment. */
@Composable
fun KDriveCard(
	viewModel: KDriveViewModel,
	pickerViewModel: KDrivePickerViewModel = hiltViewModel(),
) {
	val state by viewModel.state.collectAsStateWithLifecycle()
	val context = LocalContext.current
	var token by remember { mutableStateOf("") }
	var driveId by remember { mutableStateOf("") }
	var replaceMode by remember { mutableStateOf(false) }
	var showInfo by remember { mutableStateOf(false) }
	var showPicker by remember { mutableStateOf(false) }
	var advancedOpen by remember { mutableStateOf(false) }
	var advancedFolderId by remember { mutableStateOf("1") }
	var deleteTarget by remember { mutableStateOf<MediaSourceDto?>(null) }

	Card(modifier = Modifier.fillMaxWidth()) {
		Column(
			modifier = Modifier.padding(16.dp),
			verticalArrangement = Arrangement.spacedBy(8.dp),
		) {
			Row(verticalAlignment = Alignment.CenterVertically) {
				Text(
					text = stringResource(R.string.kdrive_section),
					style = MaterialTheme.typography.titleMedium,
					modifier = Modifier.weight(1f),
				)
				IconButton(onClick = { showInfo = true }) {
					Icon(
						imageVector = Icons.Filled.Info,
						contentDescription = stringResource(R.string.kdrive_info_title),
					)
				}
			}

			when {
				state.checking -> Row(
					verticalAlignment = Alignment.CenterVertically,
					horizontalArrangement = Arrangement.spacedBy(8.dp),
				) {
					CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
					Text(
						text = stringResource(R.string.kdrive_checking),
						style = MaterialTheme.typography.bodySmall,
					)
				}

				state.statusError != null -> {
					Text(
						text = stringResource(R.string.kdrive_status_unknown),
						style = MaterialTheme.typography.bodySmall,
					)
					Text(
						text = state.statusError.orEmpty(),
						style = MaterialTheme.typography.bodySmall,
						color = MaterialTheme.colorScheme.error,
					)
					TextButton(onClick = viewModel::refresh) {
						Text(stringResource(R.string.retry))
					}
				}

				state.connected && !replaceMode -> {
					ListItem(
						leadingContent = { Icon(Icons.Filled.Cloud, contentDescription = null) },
						headlineContent = {
							Text(
								stringResource(
									R.string.kdrive_connected,
									state.driveId?.toString().orEmpty(),
								),
							)
						},
						supportingContent = { Text(stringResource(R.string.kdrive_token_saved)) },
						trailingContent = {
							TextButton(onClick = { replaceMode = true }) {
								Text(stringResource(R.string.kdrive_replace_token))
							}
						},
					)
				}

				else -> ConnectForm(
					token = token,
					driveId = driveId,
					connecting = state.connecting,
					error = state.connectError,
					onTokenChange = { token = it },
					onDriveIdChange = { driveId = it },
					canCancel = replaceMode,
					onCancel = { replaceMode = false },
					onConnect = {
						viewModel.connect(token.trim(), driveId.trim())
						token = ""
					},
				)
			}

			if (state.connected) {
				FoldersSection(
					state = state,
					onAdd = { showPicker = true },
					onRescan = viewModel::rescan,
					onToggleSubfolders = viewModel::toggleSubfolders,
					onDelete = { deleteTarget = it },
				)
				state.scanProgress?.let { progress ->
					val failed = progress.error != null || progress.status == "failed"
					Text(
						text = when {
							failed -> stringResource(R.string.kdrive_scan_failed) +
								(progress.error?.let { ": $it" } ?: "")
							progress.running -> stringResource(
								R.string.kdrive_scanning,
								progress.seen,
								progress.indexed,
							)
							progress.status == "completed" ->
								stringResource(R.string.kdrive_scan_complete)
							else -> stringResource(R.string.kdrive_scan_failed)
						},
						style = MaterialTheme.typography.bodySmall,
						color = if (failed) {
							MaterialTheme.colorScheme.error
						} else {
							MaterialTheme.colorScheme.onSurfaceVariant
						},
					)
				}
				MaintenanceSection(state = state, onEnrich = viewModel::enrich, onPreviews = viewModel::generatePreviews)
				AdvancedSection(
					open = advancedOpen,
					folderId = advancedFolderId,
					scanning = state.scanning,
					onOpenChange = { advancedOpen = it },
					onFolderIdChange = { advancedFolderId = it },
					onScan = {
						viewModel.scan(
							folderId = advancedFolderId.toLongOrNull() ?: KDriveViewModel.RootFolderId,
							includeSubfolders = true,
						)
					},
				)
			}
		}
	}

	if (showInfo) {
		AlertDialog(
			onDismissRequest = { showInfo = false },
			title = { Text(stringResource(R.string.kdrive_info_title)) },
			text = { Text(stringResource(R.string.kdrive_info_body)) },
			confirmButton = {
				TextButton(onClick = { openLink(context, TokenPageUrl) }) {
					Text(stringResource(R.string.kdrive_info_token_page))
				}
			},
			dismissButton = {
				Column {
					TextButton(onClick = { openLink(context, WebAppUrl) }) {
						Text(stringResource(R.string.kdrive_info_web_app))
					}
					TextButton(onClick = { showInfo = false }) {
						Text(stringResource(R.string.close))
					}
				}
			},
		)
	}

	deleteTarget?.let { source ->
		AlertDialog(
			onDismissRequest = { deleteTarget = null },
			title = { Text(stringResource(R.string.kdrive_delete_title, source.label)) },
			text = { Text(stringResource(R.string.kdrive_delete_body, source.itemCount)) },
			confirmButton = {
				TextButton(
					onClick = {
						deleteTarget = null
						viewModel.deleteSource(source)
					},
				) {
					Text(stringResource(R.string.kdrive_delete_folder))
				}
			},
			dismissButton = {
				TextButton(onClick = { deleteTarget = null }) {
					Text(stringResource(R.string.cancel))
				}
			},
		)
	}

	if (showPicker) {
		KDriveFolderPicker(
			viewModel = pickerViewModel,
			onDismiss = { showPicker = false },
			onSelected = { folderId, path, includeSubfolders ->
				showPicker = false
				viewModel.scan(
					folderId = folderId,
					includeSubfolders = includeSubfolders,
					label = "kDrive: $path",
				)
			},
		)
	}
}

@Composable
private fun ConnectForm(
	token: String,
	driveId: String,
	connecting: Boolean,
	error: String?,
	onTokenChange: (String) -> Unit,
	onDriveIdChange: (String) -> Unit,
	canCancel: Boolean,
	onCancel: () -> Unit,
	onConnect: () -> Unit,
) {
	Text(
		text = stringResource(R.string.kdrive_how_to),
		style = MaterialTheme.typography.bodySmall,
		color = MaterialTheme.colorScheme.onSurfaceVariant,
	)
	OutlinedTextField(
		value = token,
		onValueChange = onTokenChange,
		label = { Text(stringResource(R.string.kdrive_token)) },
		singleLine = true,
		visualTransformation = PasswordVisualTransformation(),
		keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
		modifier = Modifier.fillMaxWidth(),
	)
	OutlinedTextField(
		value = driveId,
		onValueChange = onDriveIdChange,
		label = { Text(stringResource(R.string.kdrive_drive_id)) },
		singleLine = true,
		keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
		modifier = Modifier.fillMaxWidth(),
	)
	if (error != null) {
		Text(
			text = error,
			style = MaterialTheme.typography.bodySmall,
			color = MaterialTheme.colorScheme.error,
		)
	}
	Row(
		verticalAlignment = Alignment.CenterVertically,
		horizontalArrangement = Arrangement.spacedBy(8.dp),
	) {
		Button(
			onClick = onConnect,
			enabled = token.isNotBlank() && driveId.isNotBlank() && !connecting,
		) {
			if (connecting) {
				CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
			} else {
				Text(stringResource(R.string.kdrive_connect))
			}
		}
		if (canCancel) {
			TextButton(onClick = onCancel) {
				Text(stringResource(R.string.cancel))
			}
		}
	}
}

@Composable
private fun FoldersSection(
	state: KDriveState,
	onAdd: () -> Unit,
	onRescan: (MediaSourceDto) -> Unit,
	onToggleSubfolders: (MediaSourceDto, Boolean) -> Unit,
	onDelete: (MediaSourceDto) -> Unit,
) {
	Text(
		text = stringResource(R.string.kdrive_folders_section),
		style = MaterialTheme.typography.titleSmall,
	)
	if (state.sources.isEmpty()) {
		Text(
			text = stringResource(R.string.kdrive_no_folders),
			style = MaterialTheme.typography.bodySmall,
			color = MaterialTheme.colorScheme.onSurfaceVariant,
		)
	} else {
		state.sources.forEach { source ->
			KDriveSourceRow(
				source = source,
				onRescan = { onRescan(source) },
				onToggleSubfolders = { onToggleSubfolders(source, !source.includeSubfolders) },
				onDelete = { onDelete(source) },
			)
		}
	}
	OutlinedButton(onClick = onAdd, modifier = Modifier.fillMaxWidth()) {
		Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp))
		Spacer(Modifier.width(8.dp))
		Text(stringResource(R.string.kdrive_add_folder))
	}
}

@Composable
private fun KDriveSourceRow(
	source: MediaSourceDto,
	onRescan: () -> Unit,
	onToggleSubfolders: () -> Unit,
	onDelete: () -> Unit,
) {
	var menuOpen by remember { mutableStateOf(false) }
	ListItem(
		leadingContent = { Icon(Icons.Filled.Folder, contentDescription = null) },
		headlineContent = { Text(source.label) },
		supportingContent = {
			val parts = mutableListOf(stringResource(R.string.item_count, source.itemCount))
			parts += stringResource(
				if (source.includeSubfolders) {
					R.string.kdrive_subfolders_on
				} else {
					R.string.kdrive_subfolders_off
				},
			)
			source.lastScanAt?.let { parts += stringResource(R.string.kdrive_last_scan, formatScanDate(it)) }
			Text(parts.joinToString(" · "))
		},
		trailingContent = {
			Box {
				IconButton(onClick = { menuOpen = true }) {
					Icon(Icons.Filled.MoreVert, contentDescription = null)
				}
				DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
					DropdownMenuItem(
						text = { Text(stringResource(R.string.kdrive_scan_again)) },
						leadingIcon = { Icon(Icons.Filled.Refresh, contentDescription = null) },
						onClick = {
							menuOpen = false
							onRescan()
						},
					)
					DropdownMenuItem(
						text = { Text(stringResource(R.string.kdrive_subfolders)) },
						onClick = {
							menuOpen = false
							onToggleSubfolders()
						},
					)
					DropdownMenuItem(
						text = { Text(stringResource(R.string.kdrive_delete_folder)) },
						leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null) },
						onClick = {
							menuOpen = false
							onDelete()
						},
					)
				}
			}
		},
	)
}

@Composable
private fun MaintenanceSection(
	state: KDriveState,
	onEnrich: () -> Unit,
	onPreviews: () -> Unit,
) {
	Row(
		modifier = Modifier.fillMaxWidth(),
		horizontalArrangement = Arrangement.spacedBy(8.dp),
	) {
		OutlinedButton(
			onClick = onPreviews,
			enabled = !state.previewsRunning,
			modifier = Modifier.weight(1f),
		) {
			Text(stringResource(R.string.kdrive_previews))
		}
		OutlinedButton(
			onClick = onEnrich,
			enabled = !state.enrichRunning,
			modifier = Modifier.weight(1f),
		) {
			Text(stringResource(R.string.kdrive_enrich))
		}
	}
	if (state.previewsRunning || state.previewsProcessed > 0) {
		Text(
			text = if (state.previewsRunning) {
				stringResource(R.string.kdrive_previews_running)
			} else {
				stringResource(
					R.string.kdrive_previews_progress,
					state.previewsProcessed,
					state.previewsUpdated,
				)
			},
			style = MaterialTheme.typography.bodySmall,
			color = MaterialTheme.colorScheme.onSurfaceVariant,
		)
	}
	if (state.enrichRunning || state.enrichProcessed > 0) {
		Text(
			text = if (state.enrichRunning) {
				stringResource(
					R.string.kdrive_enrich_running,
					state.enrichProcessed,
					state.enrichUpdated,
				)
			} else {
				stringResource(R.string.kdrive_enrich_done) + " " +
					stringResource(
						R.string.kdrive_enrich_progress,
						state.enrichProcessed,
						state.enrichUpdated,
					)
			},
			style = MaterialTheme.typography.bodySmall,
			color = MaterialTheme.colorScheme.onSurfaceVariant,
		)
	}
}

@Composable
private fun AdvancedSection(
	open: Boolean,
	folderId: String,
	scanning: Boolean,
	onOpenChange: (Boolean) -> Unit,
	onFolderIdChange: (String) -> Unit,
	onScan: () -> Unit,
) {
	TextButton(onClick = { onOpenChange(!open) }) {
		Text(stringResource(R.string.kdrive_advanced))
	}
	if (!open) return
	Row(
		modifier = Modifier.fillMaxWidth(),
		verticalAlignment = Alignment.CenterVertically,
		horizontalArrangement = Arrangement.spacedBy(8.dp),
	) {
		OutlinedTextField(
			value = folderId,
			onValueChange = onFolderIdChange,
			label = { Text(stringResource(R.string.kdrive_folder_id)) },
			singleLine = true,
			keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
			modifier = Modifier.weight(1f),
		)
		Button(onClick = onScan, enabled = !scanning) {
			Text(stringResource(R.string.kdrive_scan))
		}
	}
}

private fun openLink(context: Context, url: String) {
	val opened = runCatching {
		context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
		true
	}.getOrDefault(false)
	if (!opened) {
		Toast.makeText(context, context.getString(R.string.open_link_failed), Toast.LENGTH_SHORT).show()
	}
}

/** ISO timestamp → local `yyyy-MM-dd HH:mm`, the same compact format of the UI. */
private fun formatScanDate(iso: String): String = runCatching {
	Instant.parse(iso).atZone(ZoneId.systemDefault()).format(ScanDateFormatter)
}.getOrDefault(iso)

private val ScanDateFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
