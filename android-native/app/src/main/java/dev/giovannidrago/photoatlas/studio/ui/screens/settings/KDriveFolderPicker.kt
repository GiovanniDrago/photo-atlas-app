package dev.giovannidrago.photoatlas.studio.ui.screens.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.remote.KDriveFolderDto
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.ui.settings.KDriveViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Loads every page of a kDrive folder listing for the picker. */
@HiltViewModel
class KDrivePickerViewModel @Inject constructor(
	private val api: PhotoAtlasClient,
) : ViewModel() {
	private val _folders = MutableStateFlow<List<KDriveFolderDto>>(emptyList())
	val folders: StateFlow<List<KDriveFolderDto>> = _folders.asStateFlow()

	private val _loading = MutableStateFlow(false)
	val loading: StateFlow<Boolean> = _loading.asStateFlow()

	private val _error = MutableStateFlow<String?>(null)
	val error: StateFlow<String?> = _error.asStateFlow()

	fun load(parentId: Long) {
		if (_loading.value) return
		viewModelScope.launch {
			_loading.value = true
			_error.value = null
			runCatching {
				val all = mutableListOf<KDriveFolderDto>()
				var cursor: String? = null
				do {
					val page = api.kdriveFolders(parentId, cursor)
					all += page.folders
					cursor = if (page.hasMore) page.cursor else null
				} while (cursor != null)
				all
			}
				.onSuccess { _folders.value = it }
				.onFailure { _error.value = it.message }
			_loading.value = false
		}
	}
}

/**
 * Full screen breadcrumb picker over the kDrive folders; the chosen folder and
 * the include-subfolders flag are returned to the caller.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun KDriveFolderPicker(
	viewModel: KDrivePickerViewModel,
	onDismiss: () -> Unit,
	onSelected: (folderId: Long, path: String, includeSubfolders: Boolean) -> Unit,
) {
	val folders by viewModel.folders.collectAsStateWithLifecycle()
	val loading by viewModel.loading.collectAsStateWithLifecycle()
	val error by viewModel.error.collectAsStateWithLifecycle()
	val rootName = stringResource(R.string.kdrive_root)
	var crumbs by remember { mutableStateOf(listOf(1L to rootName)) }
	var includeSubfolders by remember { mutableStateOf(true) }

	val currentId = crumbs.last().first
	LaunchedEffect(currentId) { viewModel.load(currentId) }

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
						title = { Text(stringResource(R.string.kdrive_add_folder)) },
						navigationIcon = {
							IconButton(onClick = onDismiss) {
								Icon(
									imageVector = Icons.Filled.Close,
									contentDescription = stringResource(R.string.close),
								)
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
					LazyRow(
						modifier = Modifier
							.fillMaxWidth()
							.padding(horizontal = 12.dp),
						horizontalArrangement = Arrangement.spacedBy(6.dp),
					) {
						itemsIndexed(crumbs) { index, crumb ->
							AssistChip(
								onClick = {
									if (index < crumbs.lastIndex) crumbs = crumbs.take(index + 1)
								},
								label = { Text(crumb.second) },
							)
						}
					}
					if (currentId == KDriveViewModel.RootFolderId) {
						Text(
							text = stringResource(R.string.kdrive_root_warning),
							color = MaterialTheme.colorScheme.error,
							style = MaterialTheme.typography.bodySmall,
							modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
						)
					}
					Box(
						modifier = Modifier
							.weight(1f)
							.fillMaxWidth(),
					) {
						when {
							loading -> CircularProgressIndicator(
								modifier = Modifier.align(Alignment.Center),
							)

							error != null -> Column(
								modifier = Modifier.align(Alignment.Center),
								horizontalAlignment = Alignment.CenterHorizontally,
							) {
								Text(
									text = error.orEmpty(),
									color = MaterialTheme.colorScheme.error,
									style = MaterialTheme.typography.bodySmall,
								)
								TextButton(onClick = { viewModel.load(currentId) }) {
									Text(stringResource(R.string.retry))
								}
							}

							folders.isEmpty() -> Text(
								text = stringResource(R.string.kdrive_no_subfolders),
								style = MaterialTheme.typography.bodyMedium,
								color = MaterialTheme.colorScheme.onSurfaceVariant,
								modifier = Modifier.align(Alignment.Center),
							)

							else -> LazyColumn(modifier = Modifier.fillMaxSize()) {
								items(folders, key = { it.id }) { folder ->
									ListItem(
										leadingContent = {
											Icon(Icons.Filled.Folder, contentDescription = null)
										},
										headlineContent = { Text(folder.name) },
										modifier = Modifier.clickable {
											crumbs = crumbs + (folder.id to folder.name)
										},
									)
								}
							}
						}
					}
					Row(
						modifier = Modifier
							.fillMaxWidth()
							.padding(16.dp),
						verticalAlignment = Alignment.CenterVertically,
					) {
						Switch(
							checked = includeSubfolders,
							onCheckedChange = { includeSubfolders = it },
						)
						Spacer(Modifier.width(8.dp))
						Text(
							text = stringResource(R.string.kdrive_subfolders),
							modifier = Modifier.weight(1f),
						)
					}
					Button(
						onClick = {
							val path = crumbs.joinToString("/") { it.second }
							onSelected(currentId, path, includeSubfolders)
						},
						modifier = Modifier
							.fillMaxWidth()
							.padding(horizontal = 16.dp)
							.padding(bottom = 16.dp),
					) {
						Text(stringResource(R.string.kdrive_select_folder))
					}
				}
			}
		}
	}
}
