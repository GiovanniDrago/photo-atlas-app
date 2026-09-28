package dev.giovannidrago.photoatlas.studio.domain.gallery

import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaIndexer
import dev.giovannidrago.photoatlas.studio.data.device.DeviceRegistrar
import dev.giovannidrago.photoatlas.studio.data.remote.ApiException
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.data.remote.UploadCancelled
import dev.giovannidrago.photoatlas.studio.data.remote.UploadService
import javax.inject.Inject
import javax.inject.Singleton

data class GalleryActionResult(
	val uploaded: Int = 0,
	val failed: Int = 0,
	val localDeleted: Int = 0,
	val cloudDeleted: Int = 0,
	val indexDeleted: Int = 0,
	val reset: Int = 0,
	val shared: Int = 0,
	val errors: List<String> = emptyList(),
) {
	fun merge(other: GalleryActionResult): GalleryActionResult = GalleryActionResult(
		uploaded = uploaded + other.uploaded,
		failed = failed + other.failed,
		localDeleted = localDeleted + other.localDeleted,
		cloudDeleted = cloudDeleted + other.cloudDeleted,
		indexDeleted = indexDeleted + other.indexDeleted,
		reset = reset + other.reset,
		shared = shared + other.shared,
		errors = errors + other.errors,
	)

	/** Deletions the app counted locally (matches the Flutter summary). */
	val deletedCount: Int get() = localDeleted + indexDeleted + reset
}

/** Upload, indexing and server-side deletion pipelines of the gallery. */
@Singleton
class GalleryActionsService @Inject constructor(
	private val api: PhotoAtlasClient,
	private val registrar: DeviceRegistrar,
	private val indexer: DeviceMediaIndexer,
	private val uploader: UploadService,
) {
	suspend fun upload(
		entries: List<GalleryEntry>,
		onProgress: (GalleryActionProgress) -> Unit = {},
		isCancelled: () -> Boolean = { false },
	): GalleryActionResult {
		val targets = entries.filter { it.canUpload }
		var uploaded = 0
		var failed = 0
		val errors = mutableListOf<String>()
		for ((index, entry) in targets.withIndex()) {
			if (isCancelled()) break
			onProgress(
				GalleryActionProgress(
					done = index,
					total = targets.size,
					currentName = entry.name,
				),
			)
			try {
				val local = entry.local ?: throw ApiException(400, "device file missing")
				val mediaId = entry.cloud?.id ?: indexLocal(entry)
				uploader.upload(
					mediaId = mediaId,
					openStream = { indexer.openStream(local) },
					contentLength = local.sizeBytes,
					onProgress = { sent, total ->
						onProgress(
							GalleryActionProgress(
								done = index,
								total = targets.size,
								currentName = entry.name,
								fileSent = sent,
								fileTotal = total,
							),
						)
					},
					isCancelled = isCancelled,
				)
				uploaded += 1
			} catch (_: UploadCancelled) {
				break
			} catch (error: Exception) {
				failed += 1
				errors += "${entry.name}: ${error.message}"
				onProgress(
					GalleryActionProgress(
						done = index,
						total = targets.size,
						currentName = entry.name,
						failedName = entry.name,
						error = error.message,
					),
				)
			}
		}
		onProgress(GalleryActionProgress(done = targets.size, total = targets.size))
		return GalleryActionResult(uploaded = uploaded, failed = failed, errors = errors)
	}

	/** Indexes a device-only entry, attaching it to its album source. */
	suspend fun indexLocal(entry: GalleryEntry): String {
		val local = entry.local ?: throw ApiException(400, "device file missing")
		val deviceId = registrar.ensureRegistered()
		val folder = SourceMatcher.folderName(local.relativePath)
		val source = SourceMatcher.findSource(api.sources(), folder)
			?: api.createSource(
				kind = "local",
				label = folder,
				rootPath = "album:path:$folder",
				deviceId = deviceId,
				albumKey = "path:$folder",
			)
		val response = api.batchMedia(source.id, listOf(indexer.buildItem(local)))
		return response.items.firstOrNull()?.id
			?: throw ApiException(500, "indexing failed")
	}

	/** Applies the server side of a deletion plan (drop / reset / index only). */
	suspend fun applyDelete(plan: DeletePlan): GalleryActionResult {
		var result = GalleryActionResult()
		if (plan.resetIds.isNotEmpty()) {
			result = result.merge(deleteBatch(plan.resetIds, cloud = true, index = false))
		}
		if (plan.dropIds.isNotEmpty()) {
			result = result.merge(deleteBatch(plan.dropIds, cloud = true, index = true))
		}
		if (plan.indexOnlyIds.isNotEmpty()) {
			result = result.merge(deleteBatch(plan.indexOnlyIds, cloud = false, index = true))
		}
		return result
	}

	private suspend fun deleteBatch(
		ids: List<String>,
		cloud: Boolean,
		index: Boolean,
	): GalleryActionResult = try {
		val response = api.deleteMedia(ids = ids, cloud = cloud, index = index)
		GalleryActionResult(
			cloudDeleted = response.cloudDeleted,
			indexDeleted = response.deleted,
			reset = response.reset,
			failed = response.failed.size,
			errors = response.failed.map { "${it.id}: ${it.error}" },
		)
	} catch (error: Exception) {
		GalleryActionResult(
			failed = ids.size,
			errors = listOf(error.message ?: "delete failed"),
		)
	}
}
