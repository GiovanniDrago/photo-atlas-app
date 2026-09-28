package dev.giovannidrago.photoatlas.studio.data.remote

import dev.giovannidrago.photoatlas.studio.data.auth.TokenProvider
import dev.giovannidrago.photoatlas.studio.data.local.ApiBaseUrlProvider
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okio.BufferedSink

/** Raised when the user stops an upload mid-flight. */
class UploadCancelled : Exception("upload cancelled")

/**
 * Streams a device file to POST /api/media/:id/upload straight from the
 * ContentResolver (no temp copy), reporting the bytes and honouring the
 * cancellation flag between chunks.
 */
@Singleton
class UploadService @Inject constructor(
	private val settings: ApiBaseUrlProvider,
	private val tokens: TokenProvider,
	@Named("plain") private val client: OkHttpClient,
) {
	suspend fun upload(
		mediaId: String,
		openStream: () -> InputStream?,
		contentLength: Long?,
		onProgress: (sent: Long, total: Long) -> Unit = { _, _ -> },
		isCancelled: () -> Boolean = { false },
	) {
		val baseUrl = settings.currentApiBaseUrl()
		val body = StreamBody(openStream, contentLength, onProgress, isCancelled)
		val request = Request.Builder()
			.url("$baseUrl/api/media/$mediaId/upload")
			.post(body)
			.header("Content-Type", "application/octet-stream")
			.apply {
				val token = tokens.currentToken()
				if (!token.isNullOrBlank()) header("Authorization", "Bearer $token")
			}
			.build()
		val response = try {
			withContext(Dispatchers.IO) {
				client.newBuilder()
					.callTimeout(30, TimeUnit.MINUTES)
					.build()
					.newCall(request)
					.execute()
			}
		} catch (cancelled: UploadCancelled) {
			throw cancelled
		} catch (error: Exception) {
			throw ConnectionException(error.message ?: "network error", error)
		}
		response.use {
			val text = it.body?.string().orEmpty()
			if (!it.isSuccessful) {
				throw ApiException(it.code, errorMessage(text, "HTTP ${it.code}"))
			}
		}
	}

	private class StreamBody(
		private val openStream: () -> InputStream?,
		private val length: Long?,
		private val onProgress: (Long, Long) -> Unit,
		private val isCancelled: () -> Boolean,
	) : RequestBody() {
		override fun contentType() = "application/octet-stream".toMediaType()

		override fun contentLength(): Long = length ?: -1L

		override fun writeTo(sink: BufferedSink) {
			val stream = openStream() ?: throw IOException("cannot read the device file")
			stream.use { input ->
				val buffer = ByteArray(64 * 1024)
				var sent = 0L
				val total = length ?: -1L
				while (true) {
					if (isCancelled()) throw UploadCancelled()
					val read = input.read(buffer)
					if (read == -1) break
					sink.write(buffer, 0, read)
					sent += read
					onProgress(sent, if (total > 0L) total else sent)
				}
			}
		}
	}
}
