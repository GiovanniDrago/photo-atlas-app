package dev.giovannidrago.photoatlas.studio.ui.albums

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.giovannidrago.photoatlas.studio.data.remote.AlbumDto
import dev.giovannidrago.photoatlas.studio.data.remote.AlbumRulesDto
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryActionsService
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.ui.gallery.UiMessage
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Result of adding entries to an album (localizable by the UI). */
data class AlbumAddOutcome(val added: Int = 0, val failed: Int = 0)

@HiltViewModel
class AlbumsViewModel @Inject constructor(
	private val api: PhotoAtlasClient,
	private val actions: GalleryActionsService,
) : ViewModel() {
	private val _albums = MutableStateFlow<List<AlbumDto>>(emptyList())
	val albums: StateFlow<List<AlbumDto>> = _albums.asStateFlow()

	private val _loading = MutableStateFlow(true)
	val loading: StateFlow<Boolean> = _loading.asStateFlow()

	private val _error = MutableStateFlow<String?>(null)
	val error: StateFlow<String?> = _error.asStateFlow()

	var message by mutableStateOf<UiMessage?>(null)
		private set

	init {
		refresh()
	}

	fun refresh() {
		viewModelScope.launch {
			_loading.value = true
			_error.value = null
			runCatching { api.albums() }
				.onSuccess {
					_albums.value = it
					_loading.value = false
				}
				.onFailure {
					_error.value = it.message
					_loading.value = false
				}
		}
	}

	fun createManual(name: String, onCreated: (AlbumDto) -> Unit) {
		viewModelScope.launch {
			runCatching { api.createAlbum(name = name) }
				.onSuccess {
					refresh()
					onCreated(it)
				}
				.onFailure { message = UiMessage(UiMessage.Kind.Failed, detail = it.message) }
		}
	}

	fun rename(album: AlbumDto, name: String, onRenamed: (AlbumDto) -> Unit) {
		viewModelScope.launch {
			runCatching { api.updateAlbum(album.id, name = name) }
				.onSuccess {
					refresh()
					onRenamed(it)
				}
				.onFailure { message = UiMessage(UiMessage.Kind.Failed, detail = it.message) }
		}
	}

	fun delete(album: AlbumDto) {
		viewModelScope.launch {
			runCatching { api.deleteAlbum(album.id) }
				.onSuccess {
					message = UiMessage(UiMessage.Kind.AlbumDeleted)
					refresh()
				}
				.onFailure { message = UiMessage(UiMessage.Kind.Failed, detail = it.message) }
		}
	}

	/** Resolves the media ids (indexing device-only entries) and adds them. */
	fun addToAlbum(
		albumId: String,
		entries: List<GalleryEntry>,
		onDone: (AlbumAddOutcome) -> Unit,
	) {
		viewModelScope.launch {
			val ids = mutableListOf<String>()
			var failed = 0
			for (entry in entries) {
				val cloud = entry.cloud
				if (cloud != null) {
					ids += cloud.id
					continue
				}
				runCatching { actions.indexLocal(entry) }
					.onSuccess { ids += it }
					.onFailure { failed += 1 }
			}
			if (ids.isEmpty()) {
				onDone(AlbumAddOutcome(failed = failed))
				return@launch
			}
			runCatching { api.addAlbumItems(albumId, ids) }
				.onSuccess { added ->
					refresh()
					onDone(AlbumAddOutcome(added = added, failed = failed + (ids.size - added)))
				}
				.onFailure {
					message = UiMessage(UiMessage.Kind.Failed, detail = it.message)
					onDone(AlbumAddOutcome(failed = failed + ids.size))
				}
		}
	}

	fun createAndAdd(name: String, entries: List<GalleryEntry>, onDone: (AlbumAddOutcome) -> Unit) {
		viewModelScope.launch {
			val ids = mutableListOf<String>()
			var failed = 0
			for (entry in entries) {
				val cloud = entry.cloud
				if (cloud != null) {
					ids += cloud.id
					continue
				}
				runCatching { actions.indexLocal(entry) }
					.onSuccess { ids += it }
					.onFailure { failed += 1 }
			}
			runCatching { api.createAlbum(name = name, mediaIds = ids) }
				.onSuccess {
					refresh()
					onDone(AlbumAddOutcome(added = ids.size, failed = failed))
				}
				.onFailure {
					message = UiMessage(UiMessage.Kind.Failed, detail = it.message)
					onDone(AlbumAddOutcome(failed = failed + ids.size))
				}
		}
	}

	suspend fun previewRules(rules: AlbumRulesDto): Int = api.previewAlbumRules(rules)

	/** Creates or updates an album (rules null → manual). */
	suspend fun save(name: String, rules: AlbumRulesDto?, albumId: String?): AlbumDto? =
		runCatching {
			if (albumId == null) {
				api.createAlbum(
					name = name,
					kind = if (rules != null) "smart" else "manual",
					rules = rules,
				)
			} else {
				api.updateAlbum(albumId, name = name, rules = rules)
			}
		}
			.onSuccess { refresh() }
			.onFailure { message = UiMessage(UiMessage.Kind.Failed, detail = it.message) }
			.getOrNull()

	fun dismissMessage() {
		message = null
	}
}
