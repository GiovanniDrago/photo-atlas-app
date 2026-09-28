package dev.giovannidrago.photoatlas.studio.data.device

import android.content.Context
import android.net.Uri
import android.os.Build
import android.util.Base64
import android.util.Size
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.giovannidrago.photoatlas.studio.data.remote.BatchItem
import dev.giovannidrago.photoatlas.studio.data.remote.Iso
import java.io.ByteArrayOutputStream
import java.io.InputStream
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Builds the API payload for a device file (metadata + 320 px thumbnail). */
@Singleton
class DeviceMediaIndexer @Inject constructor(
	@ApplicationContext private val context: Context,
) {
	suspend fun buildItem(media: DeviceMedia): BatchItem = withContext(Dispatchers.IO) {
		BatchItem(
			externalKey = media.id.toString(),
			path = media.uri,
			name = media.name,
			mime = media.mime ?: defaultMime(media),
			mediaType = media.mediaType,
			sizeBytes = media.sizeBytes ?: 0L,
			takenAt = Iso.text(media.takenAtMs),
			fileCreatedAt = Iso.text(media.fileCreatedAtMs ?: media.takenAtMs),
			modifiedAt = Iso.text(media.modifiedAtMs),
			lat = media.lat,
			lon = media.lon,
			width = media.width,
			height = media.height,
			durationS = media.durationS,
			thumbnailB64 = thumbnail(media),
		)
	}

	fun openStream(media: DeviceMedia): InputStream? =
		runCatching { context.contentResolver.openInputStream(Uri.parse(media.uri)) }.getOrNull()

	private fun defaultMime(media: DeviceMedia): String =
		if (media.isVideo) "video/mp4" else "image/jpeg"

	/** 320 px JPEG base64, skipped when the platform cannot render it. */
	private fun thumbnail(media: DeviceMedia): String? {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
		val uri = Uri.parse(media.uri)
		val bitmap = runCatching {
			context.contentResolver.loadThumbnail(uri, Size(320, 320), null)
		}.getOrNull() ?: return null
		return runCatching {
			val output = ByteArrayOutputStream()
			bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 75, output)
			bitmap.recycle()
			val bytes = output.toByteArray()
			if (bytes.isEmpty() || bytes.size > MaxThumbnailBytes) {
				null
			} else {
				Base64.encodeToString(bytes, Base64.NO_WRAP)
			}
		}.getOrNull()
	}

	private companion object {
		const val MaxThumbnailBytes = 200 * 1024
	}
}
