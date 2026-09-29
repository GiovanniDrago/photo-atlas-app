package dev.giovannidrago.photoatlas.studio.data.remote

import dev.giovannidrago.photoatlas.studio.data.local.ApiBaseUrlProvider
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response

/**
 * Typed client for photo-atlas-api. The base URL is read from the settings on
 * every call because the phone hotspot changes the VM address.
 */
@Singleton
class PhotoAtlasClient @Inject constructor(
	private val settings: ApiBaseUrlProvider,
	@Named("api") private val client: OkHttpClient,
	private val json: Json,
) {
	suspend fun health(timeoutMs: Long = 2000): Boolean = runCatching {
		val body = execute("GET", "/health", timeoutMs = timeoutMs)
		json.decodeFromString<HealthResponse>(body).status == "ok"
	}.getOrDefault(false)

	suspend fun config(): ApiConfigDto =
		json.decodeFromString(execute("GET", "/api/config"))

	suspend fun media(
		status: String = "all",
		type: String = "all",
		sourceId: String? = null,
		backupStatus: String? = null,
		west: Double? = null,
		south: Double? = null,
		east: Double? = null,
		north: Double? = null,
		limit: Int = 100,
		offset: Int = 0,
		order: String = "taken_at.desc",
	): MediaPageDto = json.decodeFromString(
		execute(
			"GET",
			"/api/media",
			query = mapOf(
				"status" to status,
				"type" to type,
				"source_id" to sourceId,
				"backup_status" to backupStatus,
				"west" to west?.toString(),
				"south" to south?.toString(),
				"east" to east?.toString(),
				"north" to north?.toString(),
				"limit" to "$limit",
				"offset" to "$offset",
				"order" to order,
			),
		),
	)

	suspend fun clusters(
		west: Double,
		south: Double,
		east: Double,
		north: Double,
		zoom: Int,
	): List<MediaClusterDto> = json.decodeFromString<ClustersResponse>(
		execute(
			"GET",
			"/api/clusters",
			query = mapOf(
				"west" to "$west",
				"south" to "$south",
				"east" to "$east",
				"north" to "$north",
				"zoom" to "$zoom",
			),
		),
	).clusters

	suspend fun registerDevice(
		fingerprint: String,
		name: String,
		platform: String,
	): String = json.decodeFromString<DeviceResponse>(
		execute(
			"POST",
			"/api/devices",
			json.encodeBody(RegisterDeviceBody(fingerprint, name, platform)),
		),
	).device.id

	suspend fun sources(): List<MediaSourceDto> =
		json.decodeFromString<SourcesResponse>(execute("GET", "/api/sources")).sources

	suspend fun deleteSource(id: String) {
		execute("DELETE", "/api/sources/$id")
	}

	suspend fun createSource(
		kind: String,
		label: String,
		rootPath: String? = null,
		deviceId: String? = null,
		albumKey: String? = null,
	): MediaSourceDto = json.decodeFromString<CreateSourceResponse>(
		execute(
			"POST",
			"/api/sources",
			json.encodeBody(
				CreateSourceRequest(
					kind = kind,
					label = label,
					rootPath = rootPath,
					deviceId = deviceId,
					albumKey = albumKey,
				),
			),
		),
	).source

	suspend fun batchMedia(sourceId: String, items: List<BatchItem>): BatchMediaResponse =
		json.decodeFromString(
			execute(
				"POST",
				"/api/media/batch",
				json.encodeBody(BatchMediaRequest(sourceId = sourceId, items = items)),
			),
		)

	suspend fun deleteMedia(
		ids: List<String>,
		cloud: Boolean,
		index: Boolean,
	): DeleteMediaResponse = json.decodeFromString(
		execute(
			"POST",
			"/api/media/delete",
			json.encodeBody(DeleteMediaRequest(ids = ids, cloud = cloud, index = index)),
		),
	)

	suspend fun updateSource(
		id: String,
		autoBackup: Boolean? = null,
		label: String? = null,
		includeSubfolders: Boolean? = null,
		lastScanAt: String? = null,
	) {
		execute(
			"PATCH",
			"/api/sources/$id",
			json.encodeBody(
				UpdateSourceRequest(
					label = label,
					autoBackup = autoBackup,
					includeSubfolders = includeSubfolders,
					lastScanAt = lastScanAt,
				),
			),
		)
	}

	suspend fun kdriveStatus(): KDriveStatusResponse =
		json.decodeFromString(execute("GET", "/api/kdrive/status"))

	suspend fun connectKDrive(
		token: String,
		driveId: String,
		label: String? = null,
	): KDriveAccountDto = json.decodeFromString<ConnectKDriveResponse>(
		execute(
			"POST",
			"/api/kdrive/connect",
			json.encodeBody(ConnectKDriveBody(token = token, driveId = driveId, label = label)),
		),
	).account

	suspend fun kdriveFolders(
		parentId: Long = 1,
		cursor: String? = null,
	): KDriveFoldersResponse = json.decodeFromString(
		execute(
			"GET",
			"/api/kdrive/folders",
			query = mapOf(
				"parent_id" to "$parentId",
				"cursor" to cursor,
			),
		),
	)

	suspend fun kdriveScan(
		folderId: Long,
		includeSubfolders: Boolean,
		label: String? = null,
	): KDriveScanResponse = json.decodeFromString(
		execute(
			"POST",
			"/api/kdrive/scan",
			json.encodeBody(
				KDriveScanBody(
					folderId = folderId,
					includeSubfolders = includeSubfolders,
					label = label,
				),
			),
		),
	)

	suspend fun scanRun(id: String): ScanRunDto =
		json.decodeFromString<ScanRunResponse>(execute("GET", "/api/scan-runs/$id")).scan_run

	suspend fun kdriveEnrich(limit: Int = 50) {
		execute("POST", "/api/kdrive/enrich", json.encodeBody(KDriveEnrichBody(limit)))
	}

	suspend fun kdriveEnrichState(): KDriveEnrichStateDto =
		json.decodeFromString(execute("GET", "/api/kdrive/enrich"))

	suspend fun kdrivePreviews() {
		execute("POST", "/api/kdrive/previews")
	}

	suspend fun kdrivePreviewsState(): KDrivePreviewStateDto =
		json.decodeFromString(execute("GET", "/api/kdrive/previews"))

	suspend fun backupStatus(): List<BackupSourceStatusDto> = backupStatusFull().sources

	suspend fun backupStatusFull(): BackupStatusResponse =
		json.decodeFromString(execute("GET", "/api/backup/status"))

	suspend fun backupPending(
		sourceId: String? = null,
		limit: Int = 5,
	): List<PendingBackupItemDto> = json.decodeFromString<PendingBackupResponse>(
		execute(
			"GET",
			"/api/backup/pending",
			query = mapOf(
				"source_id" to sourceId,
				"limit" to "$limit",
			),
		),
	).items

	suspend fun backupRelease(ids: List<String>): Int = json.decodeFromString<ReleaseClaimsResponse>(
		execute("POST", "/api/backup/release", json.encodeBody(ReleaseClaimsRequest(ids))),
	).released

	suspend fun verifyQueue(
		sourceId: String? = null,
		limit: Int = 20,
	): List<VerifyQueueItemDto> = json.decodeFromString<VerifyQueueResponse>(
		execute(
			"GET",
			"/api/backup/verify-queue",
			query = mapOf(
				"source_id" to sourceId,
				"limit" to "$limit",
			),
		),
	).items

	suspend fun verifyMedia(id: String): VerifyResultDto =
		json.decodeFromString(execute("POST", "/api/media/$id/verify"))

	suspend fun createBackupRun(
		kind: String,
		sourceId: String? = null,
		deviceId: String? = null,
	): BackupRunDto = json.decodeFromString<BackupRunResponse>(
		execute(
			"POST",
			"/api/backup/runs",
			json.encodeBody(
				CreateBackupRunBody(kind = kind, sourceId = sourceId, deviceId = deviceId),
			),
		),
	).run

	suspend fun patchBackupRun(id: String, body: PatchBackupRunBody): BackupRunDto =
		json.decodeFromString<BackupRunResponse>(
			execute("PATCH", "/api/backup/runs/$id", json.encodeBody(body)),
		).run

	suspend fun timeline(): List<TimelineBucketDto> =
		json.decodeFromString<TimelineResponse>(execute("GET", "/api/timeline")).buckets

	suspend fun timelineItems(
		fromIso: String,
		toIso: String,
		limit: Int = 200,
		offset: Int = 0,
	): MediaPageDto = json.decodeFromString(
		execute(
			"GET",
			"/api/timeline/items",
			query = mapOf(
				"from" to fromIso,
				"to" to toIso,
				"limit" to "$limit",
				"offset" to "$offset",
			),
		),
	)

	suspend fun albums(): List<AlbumDto> =
		json.decodeFromString<AlbumsResponse>(execute("GET", "/api/albums")).albums

	suspend fun createAlbum(
		name: String,
		kind: String = "manual",
		rules: AlbumRulesDto? = null,
		mediaIds: List<String>? = null,
	): AlbumDto = json.decodeFromString<CreateAlbumResponse>(
		execute(
			"POST",
			"/api/albums",
			json.encodeBody(
				CreateAlbumRequest(
					name = name,
					kind = kind,
					rules = rules,
					mediaIds = mediaIds?.takeIf { it.isNotEmpty() },
				),
			),
		),
	).album

	suspend fun updateAlbum(
		id: String,
		name: String? = null,
		rules: AlbumRulesDto? = null,
		coverMediaId: String? = null,
		clearCover: Boolean = false,
	): AlbumDto = json.decodeFromString<CreateAlbumResponse>(
		execute(
			"PATCH",
			"/api/albums/$id",
			json.encodeBody(
				UpdateAlbumRequest(
					name = name,
					rules = rules,
					coverMediaId = coverMediaId,
					clearCover = clearCover.takeIf { it },
				),
			),
		),
	).album

	suspend fun deleteAlbum(id: String) {
		execute("DELETE", "/api/albums/$id")
	}

	suspend fun albumMedia(
		id: String,
		limit: Int = 100,
		offset: Int = 0,
		backupStatus: String? = null,
	): MediaPageDto = json.decodeFromString(
		execute(
			"GET",
			"/api/albums/$id/media",
			query = mapOf(
				"limit" to "$limit",
				"offset" to "$offset",
				"backup_status" to backupStatus,
			),
		),
	)

	suspend fun previewAlbumRules(rules: AlbumRulesDto): Int =
		json.decodeFromString<AlbumPreviewResponse>(
			execute("POST", "/api/albums/preview", json.encodeBody(AlbumPreviewRequest(rules))),
		).total

	suspend fun addAlbumItems(albumId: String, mediaIds: List<String>): Int =
		json.decodeFromString<AlbumItemsResponse>(
			execute(
				"POST",
				"/api/albums/$albumId/items",
				json.encodeBody(AlbumItemsRequest(mediaIds)),
			),
		).added

	suspend fun removeAlbumItems(albumId: String, mediaIds: List<String>): Int =
		json.decodeFromString<AlbumRemovedResponse>(
			execute(
				"DELETE",
				"/api/albums/$albumId/items",
				json.encodeBody(AlbumItemsRequest(mediaIds)),
			),
		).removed

	suspend fun me(): AuthUserDto =
		json.decodeFromString<MeResponse>(execute("GET", "/api/auth/me")).user

	suspend fun mfaSync(): AuthUserDto =
		json.decodeFromString<MeResponse>(execute("POST", "/api/auth/mfa/sync", EmptyBody)).user

	suspend fun recoveryCodeCounts(): RecoveryCodeCountsResponse =
		json.decodeFromString(execute("GET", "/api/auth/recovery-codes"))

	suspend fun regenerateRecoveryCodes(kind: String? = null): List<String> {
		val body = execute("POST", "/api/auth/recovery-codes", json.encodeBody(RegenerateCodesBody(kind)))
		return json.decodeFromString<RecoveryCodesResponse>(body).recoveryCodes
	}

	suspend fun resetPasswordWithCode(
		identifier: String,
		recoveryCode: String,
		newPassword: String,
	) {
		execute(
			"POST",
			"/api/auth/password/reset-with-code",
			json.encodeBody(ResetPasswordBody(identifier, recoveryCode, newPassword)),
		)
	}

	suspend fun resetMfaWithCode(identifier: String, recoveryCode: String) {
		execute("POST", "/api/auth/mfa/recovery", json.encodeBody(ResetMfaBody(identifier, recoveryCode)))
	}

	private suspend fun execute(
		method: String,
		path: String,
		body: RequestBody? = null,
		timeoutMs: Long? = null,
		query: Map<String, String?> = emptyMap(),
	): String {
		val baseUrl = settings.currentApiBaseUrl()
		val urlBuilder = "$baseUrl$path".toHttpUrl().newBuilder()
		query.forEach { (key, value) ->
			if (value != null) urlBuilder.addQueryParameter(key, value)
		}
		val request = Request.Builder()
			.url(urlBuilder.build())
			.method(method, if (method == "GET") null else (body ?: EmptyBody))
			.build()
		val http = if (timeoutMs == null) {
			client
		} else {
			client.newBuilder().callTimeout(timeoutMs, TimeUnit.MILLISECONDS).build()
		}
		val response = try {
			withContext(Dispatchers.IO) { http.newCall(request).execute() }
		} catch (error: Exception) {
			throw ConnectionException(error.message ?: "network error", error)
		}
		return response.readBody()
	}
}

private fun Response.readBody(): String {
	use { response ->
		val text = response.body?.string().orEmpty()
		val fallback = "HTTP ${response.code}"
		if (response.code == 403 && errorMessage(text, "") == "mfa_required") {
			throw MfaRequiredException()
		}
		if (response.code == 401) throw SessionExpiredException()
		if (!response.isSuccessful) throw ApiException(response.code, errorMessage(text, fallback))
		return text
	}
}
