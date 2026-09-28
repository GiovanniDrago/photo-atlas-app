package dev.giovannidrago.photoatlas.studio.data.device

import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.giovannidrago.photoatlas.studio.data.remote.MediaItemDto
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Reads the whole device library with an explicit, stable order (the platform
 * default order is arbitrary and makes paged reads repeat or skip items) and
 * keeps it for a couple of minutes so invalidations do not re-read thousands
 * of rows.
 */
@Singleton
class MediaStoreDeviceMediaSource @Inject constructor(
	@ApplicationContext private val context: Context,
) : DeviceMediaSource {
	private val mutex = Mutex()
	private var cached: List<DeviceMedia> = emptyList()
	private var cachedAtMs = 0L

	override suspend fun loadLibrary(forceRefresh: Boolean): List<DeviceMedia> = mutex.withLock {
		val now = System.currentTimeMillis()
		if (!forceRefresh && cachedAtMs != 0L && now - cachedAtMs < CacheTtlMs) {
			return cached
		}
		val items = withContext(Dispatchers.IO) {
			queryAll().sortedWith(newestFirst)
		}
		cached = items
		cachedAtMs = now
		return items
	}

	override suspend fun listFolders(): List<DeviceFolder> = withContext(Dispatchers.IO) {
		val folders = LinkedHashMap<Long, FolderAccumulator>()
		queryCollections(
			selection = null,
			selectionArgs = null,
			sortOrder = null,
		) { media, cursor ->
			val bucketId = cursor.bucketId()
			if (bucketId == null) return@queryCollections
			val accumulator = folders.getOrPut(bucketId) { FolderAccumulator() }
			accumulator.count += 1
			if (accumulator.path == null) {
				accumulator.path = media.relativePath
			}
			if (accumulator.name == null) {
				accumulator.name = media.relativePath?.substringAfterLast('/')
			}
		}
		folders.mapNotNull { (id, accumulator) ->
			val name = accumulator.name?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
			DeviceFolder(
				id = id.toString(),
				name = name,
				path = accumulator.path ?: name,
				count = accumulator.count,
			)
		}.sortedByDescending { it.count }
	}

	override suspend fun loadFolderPage(albumId: String, page: Int, size: Int): DevicePage =
		withContext(Dispatchers.IO) {
			val bucketId = albumId.toLongOrNull()
				?: return@withContext DevicePage(emptyList(), 0, false)
			val all = mutableListOf<DeviceMedia>()
			queryCollections(
				selection = "${MediaStore.MediaColumns.BUCKET_ID} = ?",
				selectionArgs = arrayOf(bucketId.toString()),
				sortOrder = null,
			) { media, _ -> all += media }
			val ordered = all.sortedWith(newestFirst)
			val start = page * size
			if (start >= ordered.size) {
				return@withContext DevicePage(emptyList(), ordered.size, false)
			}
			val end = (start + size).coerceAtMost(ordered.size)
			DevicePage(
				items = ordered.subList(start, end),
				total = ordered.size,
				hasMore = end < ordered.size,
			)
		}

	override suspend fun recent(limit: Int): List<DeviceMedia> = withContext(Dispatchers.IO) {
		val items = mutableListOf<DeviceMedia>()
		queryCollections(
			selection = null,
			selectionArgs = null,
			sortOrder = "${MediaStore.MediaColumns.DATE_ADDED} DESC, ${MediaStore.MediaColumns._ID} DESC",
			limit = limit,
		) { media, _ -> items += media }
		items.take(limit)
	}

	override suspend fun resolveForItems(items: List<MediaItemDto>): Map<String, DeviceMedia> =
		withContext(Dispatchers.IO) {
			val targets = items.filter { it.sourceKind != "kdrive" && it.externalKey.isNotBlank() }
			if (targets.isEmpty()) return@withContext emptyMap()
			val byId = mutableMapOf<Long, DeviceMedia>()
			val ids = targets.mapNotNull { it.externalKey.toLongOrNull() }.distinct()
			for (chunk in ids.chunked(400)) {
				val placeholders = chunk.joinToString(",") { "?" }
				queryCollections(
					selection = "${MediaStore.MediaColumns._ID} IN ($placeholders)",
					selectionArgs = chunk.map { it.toString() }.toTypedArray(),
					sortOrder = null,
				) { media, _ -> byId[media.id] = media }
			}
			val resolved = mutableMapOf<String, DeviceMedia>()
			for (item in targets) {
				val media = item.externalKey.toLongOrNull()?.let { byId[it] }
				if (media != null) resolved[item.externalKey] = media
			}
			// Rebuilt media library: fall back to name + size (Flutter parity).
			val missing = targets.filter { !resolved.containsKey(it.externalKey) }
			if (missing.isNotEmpty()) {
				val library = if (cachedAtMs != 0L) cached else loadLibrary()
				val byNameSize = mutableMapOf<String, DeviceMedia>()
				for (media in library) {
					val size = media.sizeBytes
					if (size != null && size > 0L && media.name.isNotEmpty()) {
						byNameSize.putIfAbsent("${media.name}|$size", media)
					}
				}
				for (item in missing) {
					val size = item.sizeBytes ?: continue
					if (size <= 0L || item.name.isEmpty()) continue
					val candidate = byNameSize["${item.name}|$size"] ?: continue
					resolved[item.externalKey] = candidate
				}
			}
			resolved
		}

	override fun invalidate() {
		cached = emptyList()
		cachedAtMs = 0L
	}

	private fun queryAll(): List<DeviceMedia> {
		val items = mutableListOf<DeviceMedia>()
		queryCollections(selection = null, selectionArgs = null, sortOrder = null) { media, _ ->
			items += media
		}
		return items
	}

	/** Runs the project-specific query on images and videos. */
	private fun queryCollections(
		selection: String?,
		selectionArgs: Array<String>?,
		sortOrder: String?,
		limit: Int? = null,
		onRow: (DeviceMedia, Cursor) -> Unit,
	) {
		val order = sortOrder
			?: "${MediaStore.MediaColumns.DATE_ADDED} DESC, ${MediaStore.MediaColumns._ID} DESC"
		queryCollection(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, video = false, selection, selectionArgs, order, limit, onRow)
		queryCollection(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, video = true, selection, selectionArgs, order, limit, onRow)
	}

	private fun queryCollection(
		collection: Uri,
		video: Boolean,
		selection: String?,
		selectionArgs: Array<String>?,
		sortOrder: String,
		limit: Int?,
		onRow: (DeviceMedia, Cursor) -> Unit,
	) {
		val columns = mutableListOf(
			MediaStore.MediaColumns._ID,
			MediaStore.MediaColumns.DISPLAY_NAME,
			MediaStore.MediaColumns.MIME_TYPE,
			MediaStore.MediaColumns.SIZE,
			MediaStore.MediaColumns.DATE_ADDED,
			MediaStore.MediaColumns.DATE_TAKEN,
			MediaStore.MediaColumns.DATE_MODIFIED,
			MediaStore.MediaColumns.WIDTH,
			MediaStore.MediaColumns.HEIGHT,
			MediaStore.MediaColumns.BUCKET_ID,
			MediaStore.MediaColumns.BUCKET_DISPLAY_NAME,
		)
		// Latitude/longitude live in the type-specific columns and need API 29.
		val latColumn = when {
			Build.VERSION.SDK_INT < Build.VERSION_CODES.Q -> null
			video -> MediaStore.Video.VideoColumns.LATITUDE
			else -> MediaStore.Images.ImageColumns.LATITUDE
		}
		val lonColumn = when {
			Build.VERSION.SDK_INT < Build.VERSION_CODES.Q -> null
			video -> MediaStore.Video.VideoColumns.LONGITUDE
			else -> MediaStore.Images.ImageColumns.LONGITUDE
		}
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
			columns += MediaStore.MediaColumns.RELATIVE_PATH
			if (latColumn != null) columns += latColumn
			if (lonColumn != null) columns += lonColumn
		}
		if (video) {
			columns += MediaStore.Video.VideoColumns.DURATION
		}

		val cursor = runCatching {
			context.contentResolver.query(
				collection,
				columns.toTypedArray(),
				selection,
				selectionArgs,
				sortOrder,
			)
		}.getOrNull() ?: return

		cursor.use { rows ->
			val idIndex = rows.getColumnIndex(MediaStore.MediaColumns._ID)
			val nameIndex = rows.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
			val mimeIndex = rows.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
			val sizeIndex = rows.getColumnIndex(MediaStore.MediaColumns.SIZE)
			val addedIndex = rows.getColumnIndex(MediaStore.MediaColumns.DATE_ADDED)
			val takenIndex = rows.getColumnIndex(MediaStore.MediaColumns.DATE_TAKEN)
			val modifiedIndex = rows.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
			val widthIndex = rows.getColumnIndex(MediaStore.MediaColumns.WIDTH)
			val heightIndex = rows.getColumnIndex(MediaStore.MediaColumns.HEIGHT)
			val bucketIndex = rows.getColumnIndex(MediaStore.MediaColumns.BUCKET_ID)
			val bucketNameIndex = rows.getColumnIndex(MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)
			val relativeIndex = rows.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
			val latIndex = latColumn?.let { rows.getColumnIndex(it) } ?: -1
			val lonIndex = lonColumn?.let { rows.getColumnIndex(it) } ?: -1
			val durationIndex = if (video) {
				rows.getColumnIndex(MediaStore.Video.VideoColumns.DURATION)
			} else {
				-1
			}
			var read = 0
			while (rows.moveToNext()) {
				if (idIndex < 0) continue
				if (limit != null && read >= limit) break
				read += 1
				val id = rows.getLong(idIndex)
				val addedS = if (addedIndex >= 0 && !rows.isNull(addedIndex)) {
					rows.getLong(addedIndex)
				} else {
					0L
				}
				val taken = if (takenIndex >= 0 && !rows.isNull(takenIndex)) {
					rows.getLong(takenIndex).takeIf { it > 0L }
				} else {
					null
				}
				val lat = if (latIndex >= 0 && !rows.isNull(latIndex)) rows.getDouble(latIndex) else 0.0
				val lon = if (lonIndex >= 0 && !rows.isNull(lonIndex)) rows.getDouble(lonIndex) else 0.0
				val durationMs = if (durationIndex >= 0 && !rows.isNull(durationIndex)) {
					rows.getLong(durationIndex)
				} else {
					0L
				}
				val relative = if (relativeIndex >= 0 && !rows.isNull(relativeIndex)) {
					rows.getString(relativeIndex)?.trimEnd('/')?.takeIf { it.isNotBlank() }
				} else {
					null
				}
				val bucketName = if (bucketNameIndex >= 0 && !rows.isNull(bucketNameIndex)) {
					rows.getString(bucketNameIndex)
				} else {
					null
				}
				val media = DeviceMedia(
					id = id,
					name = if (nameIndex >= 0 && !rows.isNull(nameIndex)) {
						rows.getString(nameIndex) ?: "media-$id"
					} else {
						"media-$id"
					},
					uri = ContentUris.withAppendedId(collection, id).toString(),
					mime = if (mimeIndex >= 0 && !rows.isNull(mimeIndex)) {
						rows.getString(mimeIndex)
					} else {
						null
					},
					mediaType = if (video) "video" else "image",
					sizeBytes = if (sizeIndex >= 0 && !rows.isNull(sizeIndex)) {
						rows.getLong(sizeIndex).takeIf { it > 0L }
					} else {
						null
					},
					fileCreatedAtMs = (addedS * 1000L).takeIf { it > 0L },
					takenAtMs = taken ?: (addedS * 1000L).takeIf { it > 0L },
					modifiedAtMs = if (modifiedIndex >= 0 && !rows.isNull(modifiedIndex)) {
						rows.getLong(modifiedIndex) * 1000L
					} else {
						null
					},
					durationS = if (video && durationMs > 0L) durationMs / 1000.0 else null,
					width = if (widthIndex >= 0 && !rows.isNull(widthIndex)) {
						rows.getInt(widthIndex).takeIf { it > 0 }
					} else {
						null
					},
					height = if (heightIndex >= 0 && !rows.isNull(heightIndex)) {
						rows.getInt(heightIndex).takeIf { it > 0 }
					} else {
						null
					},
					relativePath = relative ?: bucketName?.takeIf { it.isNotBlank() },
					bucketId = if (bucketIndex >= 0 && !rows.isNull(bucketIndex)) {
						rows.getLong(bucketIndex)
					} else {
						null
					},
					lat = lat.takeIf { it != 0.0 },
					lon = lon.takeIf { it != 0.0 },
				)
				onRow(media, rows)
			}
		}
	}

	private fun Cursor.bucketId(): Long? {
		val index = getColumnIndex(MediaStore.MediaColumns.BUCKET_ID)
		if (index < 0 || isNull(index)) return null
		return getLong(index)
	}

	private class FolderAccumulator {
		var count: Int = 0
		var name: String? = null
		var path: String? = null
	}

	private companion object {
		const val CacheTtlMs = 2 * 60 * 1000L
		val newestFirst: Comparator<DeviceMedia> =
			compareByDescending<DeviceMedia> { it.takenAtMs ?: 0L }
				.thenByDescending { it.id }
	}
}
