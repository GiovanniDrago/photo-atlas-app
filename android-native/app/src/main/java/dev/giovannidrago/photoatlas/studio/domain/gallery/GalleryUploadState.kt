package dev.giovannidrago.photoatlas.studio.domain.gallery

enum class UploadEntryStatus { Pending, Current, Done, Failed }

/** Progress of a single uploaded file or of the whole run. */
data class GalleryActionProgress(
	val done: Int = 0,
	val total: Int = 0,
	val currentName: String? = null,
	val failedName: String? = null,
	val error: String? = null,
	val fileSent: Long? = null,
	val fileTotal: Long? = null,
) {
	val fileFraction: Double?
		get() {
			val sent = fileSent ?: return null
			val total = fileTotal ?: return null
			if (total <= 0L) return null
			return (sent.toDouble() / total.toDouble()).coerceIn(0.0, 1.0)
		}
}

/** State of an in-app upload run, rendered by the bottom bar and the sheet. */
data class GalleryUploadState(
	val label: String,
	val targets: List<GalleryEntry> = emptyList(),
	val done: Int = 0,
	val total: Int = 0,
	val currentName: String? = null,
	val failures: Map<Int, String?> = emptyMap(),
	val running: Boolean = true,
	val stopping: Boolean = false,
	val uploaded: Int = 0,
	val failed: Int = 0,
	val cancelled: Boolean = false,
	val fileSent: Long = 0L,
	val fileTotal: Long = 0L,
) {
	val fileFraction: Double?
		get() = if (fileTotal > 0L) {
			(fileSent.toDouble() / fileTotal.toDouble()).coerceIn(0.0, 1.0)
		} else {
			null
		}

	val overallFraction: Double?
		get() {
			if (total <= 0) return null
			val current = if (running) fileFraction ?: 0.0 else 0.0
			return ((done + current) / total).coerceIn(0.0, 1.0)
		}

	fun statusAt(index: Int): UploadEntryStatus = when {
		failures.containsKey(index) -> UploadEntryStatus.Failed
		index < done -> UploadEntryStatus.Done
		running && index == done -> UploadEntryStatus.Current
		else -> UploadEntryStatus.Pending
	}

	fun record(progress: GalleryActionProgress): GalleryUploadState {
		val failedName = progress.failedName
		return copy(
			done = progress.done,
			total = progress.total,
			currentName = progress.currentName,
			failures = if (failedName == null) {
				failures
			} else {
				failures + (progress.done to progress.error)
			},
			fileSent = progress.fileSent ?: 0L,
			fileTotal = progress.fileTotal ?: 0L,
		)
	}

	fun markStopping(): GalleryUploadState = copy(stopping = true)

	fun finish(uploaded: Int, failed: Int, cancelled: Boolean): GalleryUploadState = copy(
		done = total,
		running = false,
		stopping = false,
		uploaded = uploaded,
		failed = failed,
		cancelled = cancelled,
		currentName = null,
		fileSent = 0L,
		fileTotal = 0L,
	)
}

/** One UI update per percent (plus the last chunk), window per file. */
class FileProgressThrottle {
	private var lastSent = 0L
	private var itemIndex: Int? = null

	fun shouldEmit(progress: GalleryActionProgress): Boolean {
		val sent = progress.fileSent
		val total = progress.fileTotal
		if (sent == null || total == null || total <= 0L) return true
		if (itemIndex != progress.done) {
			itemIndex = progress.done
			lastSent = 0L
		}
		if (sent >= total) {
			lastSent = sent
			return true
		}
		if ((sent - lastSent) * 100L < total) return false
		lastSent = sent
		return true
	}
}
