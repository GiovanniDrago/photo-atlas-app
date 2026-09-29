package dev.giovannidrago.photoatlas.studio.domain.backup

import dev.giovannidrago.photoatlas.studio.data.device.DeviceMedia
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaIndexer
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaSource
import dev.giovannidrago.photoatlas.studio.data.device.DeviceRegistrar
import dev.giovannidrago.photoatlas.studio.data.remote.ApiException
import dev.giovannidrago.photoatlas.studio.data.remote.MediaItemDto
import dev.giovannidrago.photoatlas.studio.data.remote.PatchBackupRunBody
import dev.giovannidrago.photoatlas.studio.data.remote.PendingBackupItemDto
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.data.remote.UploadCancelled
import dev.giovannidrago.photoatlas.studio.data.remote.UploadService
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryActionsService
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import javax.inject.Inject
import javax.inject.Singleton

/** Live counters of a backup run (uploaded/failed/bytes, as Flutter). */
data class BackupProgress(
	val currentName: String? = null,
	val uploaded: Int = 0,
	val failed: Int = 0,
	val bytesUploaded: Long = 0L,
	val seen: Int = 0,
	val fileSent: Long = 0L,
	val fileTotal: Long = 0L,
	val failedName: String? = null,
	val error: String? = null,
)

data class BackupRunResult(
	val uploaded: Int = 0,
	val failed: Int = 0,
	val bytesUploaded: Long = 0L,
	val cancelled: Boolean = false,
	val errors: List<String> = emptyList(),
)

data class VerifyProgress(
	val currentName: String? = null,
	val ok: Int = 0,
	val missing: Int = 0,
	val seen: Int = 0,
	val total: Int = 0,
)

data class VerifyRunResult(
	val ok: Int = 0,
	val missing: Int = 0,
	val cancelled: Boolean = false,
	val errors: List<String> = emptyList(),
)

/**
 * Backup and verification runs over the server queue, ported from the Flutter
 * `backup_service.dart`: the pending endpoint hands out atomic claims, failed
 * items are not retried inside the same run and cancelled claims are released.
 */
@Singleton
class BackupService @Inject constructor(
	private val api: PhotoAtlasClient,
	private val registrar: DeviceRegistrar,
	private val device: DeviceMediaSource,
	private val actions: GalleryActionsService,
	private val indexer: DeviceMediaIndexer,
	private val uploader: UploadService,
) {
	suspend fun runBackup(
		sourceId: String? = null,
		onProgress: (BackupProgress) -> Unit = {},
		isCancelled: () -> Boolean = { false },
	): BackupRunResult {
		val deviceId = registrar.ensureRegistered()
		val run = api.createBackupRun(kind = "backup", sourceId = sourceId, deviceId = deviceId)
		var uploaded = 0
		var failed = 0
		var bytes = 0L
		var seen = 0
		var cancelled = false
		val errors = mutableListOf<String>()
		val failedIds = mutableSetOf<String>()
		try {
			while (true) {
				if (isCancelled()) {
					cancelled = true
					break
				}
				val batch = api.backupPending(sourceId, limit = PendingBatch)
					.filter { it.id !in failedIds }
				if (batch.isEmpty()) break
				val claimed = batch.map { it.id }.toMutableSet()
				for (item in batch) {
					if (isCancelled()) {
						cancelled = true
						break
					}
					onProgress(BackupProgress(item.name, uploaded, failed, bytes, seen))
					val local = resolve(item)
					if (local == null) {
						failed += 1
						failedIds += item.id
						claimed -= item.id
						seen += 1
						errors += "${item.name}: device file missing"
						onProgress(
							BackupProgress(
								currentName = item.name,
								uploaded = uploaded,
								failed = failed,
								bytesUploaded = bytes,
								seen = seen,
								failedName = item.name,
								error = "device file missing",
							),
						)
						continue
					}
					try {
						uploader.upload(
							mediaId = item.id,
							openStream = { indexer.openStream(local) },
							contentLength = local.sizeBytes,
							onProgress = { sent, total ->
								onProgress(
									BackupProgress(
										currentName = item.name,
										uploaded = uploaded,
										failed = failed,
										bytesUploaded = bytes,
										seen = seen,
										fileSent = sent,
										fileTotal = total,
									),
								)
							},
							isCancelled = isCancelled,
						)
						uploaded += 1
						bytes += local.sizeBytes ?: 0L
						claimed -= item.id
					} catch (_: UploadCancelled) {
						cancelled = true
						break
					} catch (error: Exception) {
						failed += 1
						failedIds += item.id
						claimed -= item.id
						errors += "${item.name}: ${error.message}"
						onProgress(
							BackupProgress(
								currentName = item.name,
								uploaded = uploaded,
								failed = failed,
								bytesUploaded = bytes,
								seen = seen,
								failedName = item.name,
								error = error.message,
							),
						)
					}
					seen += 1
					onProgress(BackupProgress(item.name, uploaded, failed, bytes, seen))
				}
				if (claimed.isNotEmpty()) {
					runCatching { api.backupRelease(claimed.toList()) }
				}
				if (cancelled) break
			}
		} finally {
			val status = when {
				cancelled -> "cancelled"
				failed > 0 && uploaded == 0 -> "failed"
				else -> "completed"
			}
			runCatching {
				api.patchBackupRun(
					run.id,
					PatchBackupRunBody(
						status = status,
						filesSeen = seen,
						filesUploaded = uploaded,
						filesFailed = failed,
						bytesUploaded = bytes,
						errors = errors.take(ErrorLimit).takeIf { it.isNotEmpty() },
					),
				)
			}
		}
		return BackupRunResult(
			uploaded = uploaded,
			failed = failed,
			bytesUploaded = bytes,
			cancelled = cancelled,
			errors = errors,
		)
	}

	/**
	 * Verifies the queue page. The endpoint does not claim and successful items
	 * keep their state, so a single page is verified per run (Flutter parity):
	 * run it again to cover the rest.
	 */
	suspend fun runVerify(
		sourceId: String? = null,
		onProgress: (VerifyProgress) -> Unit = {},
		isCancelled: () -> Boolean = { false },
	): VerifyRunResult {
		val deviceId = registrar.ensureRegistered()
		val run = api.createBackupRun(kind = "verify", sourceId = sourceId, deviceId = deviceId)
		var ok = 0
		var missing = 0
		var cancelled = false
		val errors = mutableListOf<String>()
		val queue = runCatching { api.verifyQueue(sourceId, limit = VerifyBatch) }
			.getOrElse { error ->
				errors += error.message ?: "verify queue failed"
				emptyList()
			}
		for ((index, item) in queue.withIndex()) {
			if (isCancelled()) {
				cancelled = true
				break
			}
			onProgress(VerifyProgress(item.name, ok, missing, index, queue.size))
			val result = runCatching { api.verifyMedia(item.id) }
			if (result.getOrNull()?.ok == true) {
				ok += 1
			} else {
				missing += 1
				val reason = result.exceptionOrNull()?.message
					?: result.getOrNull()?.reason
				if (reason != null) errors += "${item.name}: $reason"
			}
		}
		runCatching {
			api.patchBackupRun(
				run.id,
				PatchBackupRunBody(
					status = if (cancelled) "cancelled" else "completed",
					verifiedOk = ok,
					verifiedMissing = missing,
					errors = errors.take(ErrorLimit).takeIf { it.isNotEmpty() },
				),
			)
		}
		return VerifyRunResult(ok = ok, missing = missing, cancelled = cancelled, errors = errors)
	}

	/** Manual uploads from the picker: indexed on the fly, kDrive `Manual` folder. */
	suspend fun uploadPicked(
		entries: List<GalleryEntry>,
		onProgress: (BackupProgress) -> Unit = {},
		isCancelled: () -> Boolean = { false },
	): BackupRunResult {
		val targets = entries.filter { it.canUpload }
		var uploaded = 0
		var failed = 0
		var bytes = 0L
		var cancelled = false
		val errors = mutableListOf<String>()
		for ((index, entry) in targets.withIndex()) {
			if (isCancelled()) {
				cancelled = true
				break
			}
			onProgress(BackupProgress(entry.name, uploaded, failed, bytes, index))
			try {
				val local = entry.local ?: throw ApiException(400, "device file missing")
				val mediaId = entry.cloud?.id ?: actions.indexLocal(entry)
				uploader.upload(
					mediaId = mediaId,
					openStream = { indexer.openStream(local) },
					contentLength = local.sizeBytes,
					destination = "manual",
					onProgress = { _, _ ->
						onProgress(BackupProgress(entry.name, uploaded, failed, bytes, index))
					},
					isCancelled = isCancelled,
				)
				uploaded += 1
				bytes += local.sizeBytes ?: 0L
			} catch (_: UploadCancelled) {
				cancelled = true
				break
			} catch (error: Exception) {
				failed += 1
				errors += "${entry.name}: ${error.message}"
			}
		}
		onProgress(BackupProgress(null, uploaded, failed, bytes, targets.size))
		return BackupRunResult(
			uploaded = uploaded,
			failed = failed,
			bytesUploaded = bytes,
			cancelled = cancelled,
			errors = errors,
		)
	}

	private suspend fun resolve(item: PendingBackupItemDto): DeviceMedia? =
		device.resolveForItems(
			listOf(
				MediaItemDto(
					id = item.id,
					externalKey = item.externalKey,
					sourceKind = "local",
				),
			),
		)[item.externalKey]

	private companion object {
		const val PendingBatch = 5
		const val VerifyBatch = 500
		const val ErrorLimit = 20
	}
}
