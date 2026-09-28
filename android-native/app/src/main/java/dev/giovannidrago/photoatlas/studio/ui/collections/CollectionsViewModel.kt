package dev.giovannidrago.photoatlas.studio.ui.collections

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.giovannidrago.photoatlas.studio.data.device.DeviceFolder
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMedia
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaIndexer
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaSource
import dev.giovannidrago.photoatlas.studio.data.device.DeviceRegistrar
import dev.giovannidrago.photoatlas.studio.data.remote.BackupSourceStatusDto
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryActionsService
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryUploadState
import dev.giovannidrago.photoatlas.studio.domain.gallery.SourceMatcher
import dev.giovannidrago.photoatlas.studio.domain.gallery.UploadRunner
import dev.giovannidrago.photoatlas.studio.domain.gallery.mergeGalleryEntries
import dev.giovannidrago.photoatlas.studio.ui.gallery.UiMessage
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class CollectionsState(
	val folders: List<DeviceFolder> = emptyList(),
	val preview: List<GalleryEntry> = emptyList(),
	val thumbs: Map<String, DeviceMedia> = emptyMap(),
	val sourceIds: Map<String, String> = emptyMap(),
	val statuses: Map<String, BackupSourceStatusDto> = emptyMap(),
	val permissionDenied: Boolean = false,
	val loading: Boolean = true,
) {
	fun statusFor(folderId: String): BackupSourceStatusDto? =
		sourceIds[folderId]?.let { statuses[it] }

	fun autoBackup(folderId: String): Boolean = statusFor(folderId)?.autoBackup == true
}

@HiltViewModel
class CollectionsViewModel @Inject constructor(
	private val api: PhotoAtlasClient,
	private val device: DeviceMediaSource,
	private val actions: GalleryActionsService,
	private val registrar: DeviceRegistrar,
	private val indexer: DeviceMediaIndexer,
	private val runner: UploadRunner,
) : ViewModel() {
	private val _state = MutableStateFlow(CollectionsState())
	val state: StateFlow<CollectionsState> = _state.asStateFlow()
	val upload: StateFlow<GalleryUploadState?> = runner.state

	var preparingFolderIds by mutableStateOf<Set<String>>(emptySet())
		private set
	var message by mutableStateOf<UiMessage?>(null)
		private set

	init {
		refresh()
	}

	fun refresh() {
		viewModelScope.launch {
			_state.value = _state.value.copy(loading = true)
			val foldersResult = runCatching { device.listFolders() }
			val folders = foldersResult.getOrDefault(emptyList())
			val sources = runCatching { api.sources() }.getOrDefault(emptyList())
			val statuses = runCatching { api.backupStatus() }.getOrDefault(emptyList())
			val sourceIds = folders.mapNotNull { folder ->
				SourceMatcher.findSourceForFolder(sources, folder.id, folder.name)
					?.let { folder.id to it.id }
			}.toMap()
			val thumbs = folders.mapNotNull { folder ->
				runCatching {
					device.loadFolderPage(folder.id, 0, 1).items.firstOrNull()
				}.getOrNull()?.let { folder.id to it }
			}.toMap()
			val preview = runCatching {
				val cloud = api.media(limit = 6).items
				val local = device.recent(6)
				mergeGalleryEntries(cloud = cloud, local = local).take(6)
			}.getOrDefault(emptyList())
			_state.value = CollectionsState(
				folders = folders,
				preview = preview,
				thumbs = thumbs,
				sourceIds = sourceIds,
				statuses = statuses.associateBy { it.id },
				permissionDenied = foldersResult.exceptionOrNull() is SecurityException,
				loading = false,
			)
		}
	}

	/**
	 * Folder switch: turning it off only clears the flag; turning it on ensures
	 * the source, indexes the folder and uploads what is missing right away
	 * (the background job arrives with M5).
	 */
	fun toggle(folder: DeviceFolder, enabled: Boolean, uploadLabel: String) {
		if (folder.id in preparingFolderIds) return
		preparingFolderIds = preparingFolderIds + folder.id
		viewModelScope.launch {
			try {
				var source = SourceMatcher.findSourceForFolder(
					sources = api.sources(),
					albumId = folder.id,
					folderName = folder.name,
				)
				if (!enabled) {
					if (source != null) api.updateSource(source.id, autoBackup = false)
				} else {
					if (source == null) {
						val deviceId = registrar.ensureRegistered()
						source = api.createSource(
							kind = "local",
							label = folder.name,
							rootPath = "album:${folder.id}",
							deviceId = deviceId,
							albumKey = "album:${folder.id}",
						)
					}
					api.updateSource(source.id, autoBackup = true)
					indexFolder(folder, source.id)
					uploadMissing(source.id, uploadLabel)
				}
			} catch (error: Exception) {
				message = UiMessage(UiMessage.Kind.Failed, detail = error.message)
			} finally {
				preparingFolderIds = preparingFolderIds - folder.id
				refresh()
			}
		}
	}

	fun cancelUpload() = runner.cancel()

	fun dismissUpload() = runner.dismiss()

	fun dismissMessage() {
		message = null
	}

	private suspend fun indexFolder(folder: DeviceFolder, sourceId: String) {
		var page = 0
		while (true) {
			val pageData = device.loadFolderPage(folder.id, page, IndexBatchSize)
			if (pageData.items.isEmpty()) break
			api.batchMedia(sourceId, pageData.items.map { indexer.buildItem(it) })
			if (!pageData.hasMore) break
			page += 1
		}
		device.invalidate()
	}

	private suspend fun uploadMissing(sourceId: String, label: String) {
		if (runner.isRunning) return
		val pending = api.media(
			sourceId = sourceId,
			backupStatus = "none,pending,uploading,failed",
			limit = 500,
		)
		if (pending.items.isEmpty()) return
		val locals = runCatching { device.resolveForItems(pending.items) }.getOrDefault(emptyMap())
		val targets = pending.items
			.map { GalleryEntry(cloud = it, local = locals[it.externalKey]) }
			.filter { it.canUpload }
		if (targets.isEmpty()) return
		runner.begin(label, targets)
		val result = actions.upload(
			targets,
			onProgress = runner::record,
			isCancelled = runner::isCancelled,
		)
		runner.finish(result)
		message = if (result.errors.isNotEmpty()) {
			UiMessage(UiMessage.Kind.Failed, detail = result.errors.first())
		} else {
			UiMessage(UiMessage.Kind.Uploaded, count = result.uploaded)
		}
	}

	private companion object {
		const val IndexBatchSize = 100
	}
}
