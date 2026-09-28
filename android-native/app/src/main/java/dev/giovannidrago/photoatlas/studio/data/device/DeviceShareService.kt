package dev.giovannidrago.photoatlas.studio.data.device

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryActionResult
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.domain.gallery.MetadataExport
import java.io.File
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Sharing through the system sheet: device files go out as content URIs,
 * cloud-only items are downloaded once per share into a batch folder.
 */
@Singleton
class DeviceShareService @Inject constructor(
	@ApplicationContext private val context: Context,
	@Named("plain") private val client: OkHttpClient,
) {
	suspend fun shareEntries(entries: List<GalleryEntry>): GalleryActionResult {
		val uris = mutableListOf<Uri>()
		val errors = mutableListOf<String>()
		for (entry in entries) {
			val local = entry.local ?: continue
			uris += Uri.parse(local.uri)
		}
		val cloudOnly = entries.filter { entry ->
			entry.local == null && !entry.cloud?.downloadUrl.isNullOrBlank()
		}
		if (cloudOnly.isNotEmpty()) {
			val batchDir = File(context.cacheDir, "share/${System.currentTimeMillis()}")
			batchDir.mkdirs()
			for (entry in cloudOnly) {
				val url = entry.cloud?.downloadUrl ?: continue
				try {
					val file = downloadTo(url, batchDir, entry.name)
					uris += FileProvider.getUriForFile(context, authority(), file)
				} catch (error: Exception) {
					errors += "${entry.name}: ${error.message}"
				}
			}
		}
		if (uris.isEmpty()) {
			return GalleryActionResult(errors = errors)
		}
		shareUris(uris, shareMime(entries))
		return GalleryActionResult(
			shared = uris.size,
			failed = errors.size,
			errors = errors,
		)
	}

	/** Writes the metadata JSON of the selected cloud items to the app folder. */
	suspend fun exportMetadata(entries: List<GalleryEntry>): File = withContext(Dispatchers.IO) {
		val items = entries.mapNotNull { it.cloud }
		val stamp = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss").format(LocalDateTime.now())
		val directory = File(context.getExternalFilesDir(null), "exports")
		directory.mkdirs()
		val file = File(directory, "photo-atlas-metadata-$stamp.json")
		file.writeText(MetadataExport.build(items, System.currentTimeMillis()))
		file
	}

	fun shareFile(file: File, mime: String = "application/json") {
		val uri = FileProvider.getUriForFile(context, authority(), file)
		val intent = Intent(Intent.ACTION_SEND).apply {
			type = mime
			putExtra(Intent.EXTRA_STREAM, uri)
			addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
		}
		context.startActivity(
			Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
		)
	}

	private suspend fun downloadTo(url: String, directory: File, name: String): File =
		withContext(Dispatchers.IO) {
			val safeName = name.replace(Regex("[/\\\\]"), "_").ifBlank { "photo-atlas" }
			val target = File(directory, safeName)
			val request = Request.Builder().url(url).get().build()
			client.newCall(request).execute().use { response ->
				if (!response.isSuccessful) {
					throw IllegalStateException("download failed (${response.code})")
				}
				val body = response.body ?: throw IllegalStateException("empty download")
				target.outputStream().use { output -> body.byteStream().copyTo(output) }
			}
			return@withContext target
		}

	private fun shareUris(uris: List<Uri>, mime: String) {
		val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
			type = mime
			putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
			addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
		}
		context.startActivity(
			Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
		)
	}

	private fun shareMime(entries: List<GalleryEntry>): String = when {
		entries.all { it.isVideo } -> "video/*"
		entries.all { !it.isVideo } -> "image/*"
		else -> "*/*"
	}

	private fun authority(): String = "${context.packageName}.files"
}
