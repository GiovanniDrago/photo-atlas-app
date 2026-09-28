package dev.giovannidrago.photoatlas.studio.data.device

import android.content.Context
import android.content.IntentSender
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Device file deletion: system trash on Android 11+, permanent below. */
@Singleton
class DeviceTrashService @Inject constructor(
	@ApplicationContext private val context: Context,
) {
	/**
	 * PendingIntent of the system "move to trash" confirmation (Android 11+).
	 * The caller launches it with an ActivityResultLauncher; on success the
	 * files are already in the system trash.
	 */
	fun trashRequest(uris: List<Uri>): IntentSender? {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || uris.isEmpty()) return null
		return runCatching {
			MediaStore.createTrashRequest(context.contentResolver, uris, true).intentSender
		}.getOrNull()
	}

	/** Permanent delete (Android 10 and older, where there is no trash). */
	suspend fun deletePermanently(uris: List<Uri>): Set<Long> = withContext(Dispatchers.IO) {
		val deleted = mutableSetOf<Long>()
		for (uri in uris) {
			val rows = runCatching {
				context.contentResolver.delete(uri, null, null)
			}.getOrDefault(0)
			if (rows > 0) {
				uri.lastPathSegment?.toLongOrNull()?.let { deleted += it }
			}
		}
		deleted
	}
}
