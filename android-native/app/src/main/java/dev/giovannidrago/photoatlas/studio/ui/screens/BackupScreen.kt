package dev.giovannidrago.photoatlas.studio.ui.screens

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.remote.BackupSourceStatusDto
import dev.giovannidrago.photoatlas.studio.ui.backup.BackupScreenState
import dev.giovannidrago.photoatlas.studio.ui.backup.BackupViewModel
import dev.giovannidrago.photoatlas.studio.ui.screens.backup.UploadPickerDialog
import dev.giovannidrago.photoatlas.studio.ui.screens.gallery.formatBytes
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Backup screen: per-folder counters, runs, verification and manual uploads. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackupScreen(
	onBack: () -> Unit,
	viewModel: BackupViewModel = hiltViewModel(),
) {
	val state by viewModel.state.collectAsStateWithLifecycle()
	var showPicker by remember { mutableStateOf(false) }

	Scaffold(
		topBar = {
			TopAppBar(
				title = { Text(stringResource(R.string.backup_title)) },
				navigationIcon = {
					IconButton(onClick = onBack) {
						Icon(
							imageVector = Icons.AutoMirrored.Filled.ArrowBack,
							contentDescription = stringResource(R.string.action_back),
						)
					}
				},
				actions = {
					IconButton(onClick = viewModel::refresh) {
						Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.retry))
					}
				},
			)
		},
	) { padding ->
		Column(
			modifier = Modifier
				.fillMaxSize()
				.verticalScroll(rememberScrollState())
				.padding(padding)
				.padding(PaddingValues(16.dp)),
			verticalArrangement = Arrangement.spacedBy(12.dp),
		) {
			ActionsCard(
				busy = state.runningKind != null,
				onUploadFiles = {
					showPicker = true
					viewModel.loadPicker()
				},
				onBackupAll = { viewModel.startBackup() },
				onVerify = { viewModel.startVerify() },
			)
			if (state.runningKind != null) {
				ProgressCard(state = state, onStop = viewModel::cancel)
			}
			ResultLine(state)
			FoldersCard(
				state = state,
				onBackup = { viewModel.startBackup(it) },
				onVerify = { viewModel.startVerify(it) },
			)
			if (!state.loading && state.sources.isNotEmpty()) {
				Text(
					text = stringResource(
						R.string.backup_totals,
						state.totals.uploaded,
						state.totals.total,
						formatBytes(state.totals.bytesUploaded),
					),
					style = MaterialTheme.typography.bodySmall,
					color = MaterialTheme.colorScheme.onSurfaceVariant,
				)
			}
			state.error?.let { error ->
				Text(
					text = error,
					style = MaterialTheme.typography.bodySmall,
					color = MaterialTheme.colorScheme.error,
				)
			}
		}
	}

	if (showPicker) {
		UploadPickerDialog(
			state = state,
			onDismiss = {
				showPicker = false
				viewModel.dismissPicker()
			},
			onUpload = { entries ->
				showPicker = false
				viewModel.uploadPicked(entries)
			},
		)
	}
}

@Composable
private fun ActionsCard(
	busy: Boolean,
	onUploadFiles: () -> Unit,
	onBackupAll: () -> Unit,
	onVerify: () -> Unit,
) {
	Card(modifier = Modifier.fillMaxWidth()) {
		Column(
			modifier = Modifier.padding(16.dp),
			verticalArrangement = Arrangement.spacedBy(8.dp),
		) {
			FilledTonalButton(onClick = onUploadFiles, enabled = !busy) {
				Icon(Icons.Filled.CloudUpload, contentDescription = null)
				Spacer(Modifier.width(8.dp))
				Text(stringResource(R.string.backup_upload_files))
			}
			Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
				Button(
					onClick = onBackupAll,
					enabled = !busy,
					modifier = Modifier.weight(1f),
				) {
					Text(stringResource(R.string.backup_back_up_all))
				}
				OutlinedButton(
					onClick = onVerify,
					enabled = !busy,
					modifier = Modifier.weight(1f),
				) {
					Text(stringResource(R.string.backup_verify_all))
				}
			}
		}
	}
}

@Composable
private fun ProgressCard(state: BackupScreenState, onStop: () -> Unit) {
	val verify = state.runningKind == "verify"
	Card(modifier = Modifier.fillMaxWidth()) {
		Column(
			modifier = Modifier.padding(16.dp),
			verticalArrangement = Arrangement.spacedBy(8.dp),
		) {
			Text(
				text = stringResource(
					if (verify) R.string.backup_verify_running else R.string.backup_running,
				),
				style = MaterialTheme.typography.titleSmall,
			)
			if (verify) {
				val progress = state.verifyProgress
				Text(
					text = progress?.currentName.orEmpty(),
					style = MaterialTheme.typography.bodySmall,
					maxLines = 1,
				)
				Text(
					text = stringResource(
						R.string.backup_verify_counters,
						progress?.ok ?: 0,
						progress?.missing ?: 0,
					),
					style = MaterialTheme.typography.bodySmall,
				)
				val total = progress?.total ?: 0
				if (total > 0) {
					LinearProgressIndicator(
						progress = { ((progress?.seen ?: 0).toFloat() / total).coerceIn(0f, 1f) },
						modifier = Modifier.fillMaxWidth(),
					)
				} else {
					LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
				}
			} else {
				val progress = state.backupProgress
				Text(
					text = progress?.currentName.orEmpty(),
					style = MaterialTheme.typography.bodySmall,
					maxLines = 1,
				)
				Text(
					text = stringResource(
						R.string.backup_counters,
						progress?.uploaded ?: 0,
						progress?.failed ?: 0,
					) + " · " + formatBytes(progress?.bytesUploaded ?: 0L),
					style = MaterialTheme.typography.bodySmall,
				)
				val sent = progress?.fileSent ?: 0L
				val total = progress?.fileTotal ?: 0L
				if (total > 0L) {
					LinearProgressIndicator(
						progress = { (sent.toFloat() / total).coerceIn(0f, 1f) },
						modifier = Modifier.fillMaxWidth(),
					)
				} else {
					LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
				}
			}
			TextButton(onClick = onStop) {
				Text(stringResource(R.string.backup_stop))
			}
		}
	}
}

@Composable
private fun ResultLine(state: BackupScreenState) {
	if (state.runningKind != null) return
	val backup = state.lastBackup
	val verify = state.lastVerify
	val text = when {
		backup != null -> stringResource(
			R.string.backup_upload_result,
			backup.uploaded,
			backup.failed,
		)
		verify != null && verify.ok == 0 && verify.missing == 0 ->
			stringResource(R.string.backup_nothing_to_verify)
		verify != null -> stringResource(R.string.backup_verify_counters, verify.ok, verify.missing)
		else -> null
	}
	text?.let {
		Text(
			text = it,
			style = MaterialTheme.typography.bodySmall,
			color = MaterialTheme.colorScheme.onSurfaceVariant,
		)
	}
}

@Composable
private fun FoldersCard(
	state: BackupScreenState,
	onBackup: (String) -> Unit,
	onVerify: (String) -> Unit,
) {
	Card(modifier = Modifier.fillMaxWidth()) {
		Column {
			Text(
				text = stringResource(R.string.backup_folders),
				style = MaterialTheme.typography.titleSmall,
				modifier = Modifier.padding(start = 16.dp, top = 12.dp),
			)
			when {
				state.loading -> Box(
					modifier = Modifier
						.fillMaxWidth()
						.padding(24.dp),
					contentAlignment = Alignment.Center,
				) {
					CircularProgressIndicator(modifier = Modifier.size(24.dp))
				}

				state.sources.isEmpty() -> Text(
					text = stringResource(R.string.backup_no_folders),
					style = MaterialTheme.typography.bodySmall,
					color = MaterialTheme.colorScheme.onSurfaceVariant,
					modifier = Modifier.padding(16.dp),
				)

				else -> state.sources.forEach { source ->
					SourceRow(
						source = source,
						onBackup = { onBackup(source.id) },
						onVerify = { onVerify(source.id) },
					)
				}
			}
		}
	}
}

@Composable
private fun SourceRow(
	source: BackupSourceStatusDto,
	onBackup: () -> Unit,
	onVerify: () -> Unit,
) {
	var menuOpen by remember { mutableStateOf(false) }
	ListItem(
		leadingContent = { Icon(Icons.Filled.Folder, contentDescription = null) },
		headlineContent = { Text(source.label) },
		supportingContent = {
			val parts = mutableListOf(
				stringResource(R.string.backup_uploaded_of, source.uploaded, source.total),
			)
			if (source.failed > 0) {
				parts += stringResource(R.string.backup_failed_count, source.failed)
			}
			source.backupLastRunAt?.let {
				parts += stringResource(R.string.backup_last_run, formatRunDate(it))
			}
			Text(parts.joinToString(" · "))
		},
		trailingContent = {
			Box {
				IconButton(onClick = { menuOpen = true }) {
					Icon(Icons.Filled.MoreVert, contentDescription = null)
				}
				DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
					DropdownMenuItem(
						text = { Text(stringResource(R.string.backup_now)) },
						leadingIcon = { Icon(Icons.Filled.CloudUpload, contentDescription = null) },
						onClick = {
							menuOpen = false
							onBackup()
						},
					)
					DropdownMenuItem(
						text = { Text(stringResource(R.string.backup_verify)) },
						leadingIcon = { Icon(Icons.Filled.CloudDone, contentDescription = null) },
						onClick = {
							menuOpen = false
							onVerify()
						},
					)
				}
			}
		},
	)
}

private fun formatRunDate(iso: String): String = runCatching {
	Instant.parse(iso).atZone(ZoneId.systemDefault()).format(RunDateFormatter)
}.getOrDefault(iso)

private val RunDateFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
