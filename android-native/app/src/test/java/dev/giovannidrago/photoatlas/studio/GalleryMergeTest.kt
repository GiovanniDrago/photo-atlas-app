package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.data.device.DeviceMedia
import dev.giovannidrago.photoatlas.studio.data.remote.Iso
import dev.giovannidrago.photoatlas.studio.data.remote.MediaItemDto
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryFilter
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryUploadFilter
import dev.giovannidrago.photoatlas.studio.domain.gallery.galleryEntryMatches
import dev.giovannidrago.photoatlas.studio.domain.gallery.mergeGalleryEntries
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

internal fun cloudItem(
	id: String = "11111111-1111-1111-1111-111111111111",
	externalKey: String = "asset-1",
	sourceKind: String = "local",
	name: String = "IMG_0001.jpg",
	mediaType: String = "image",
	metadataStatus: String = "full",
	backupStatus: String = "none",
	sizeBytes: Long? = null,
	takenAtMs: Long? = null,
): MediaItemDto = MediaItemDto(
	id = id,
	sourceId = "22222222-2222-2222-2222-222222222222",
	externalKey = externalKey,
	name = name,
	mediaType = mediaType,
	metadataStatus = metadataStatus,
	backupStatus = backupStatus,
	sizeBytes = sizeBytes,
	sourceKind = sourceKind,
	takenAt = Iso.text(takenAtMs),
)

internal fun localItem(
	id: Long = 1L,
	name: String = "IMG_0001.jpg",
	mediaType: String = "image",
	sizeBytes: Long? = null,
	takenAtMs: Long? = null,
): DeviceMedia = DeviceMedia(
	id = id,
	name = name,
	uri = "content://media/$id",
	mime = null,
	mediaType = mediaType,
	sizeBytes = sizeBytes,
	fileCreatedAtMs = null,
	takenAtMs = takenAtMs,
	modifiedAtMs = null,
	durationS = null,
	width = null,
	height = null,
	relativePath = null,
	bucketId = null,
	lat = null,
	lon = null,
)

class GalleryMergeTest {
	@Test
	fun `merge pairs an indexed item with its device file`() {
		val entries = mergeGalleryEntries(
			cloud = listOf(cloudItem(externalKey = "42", backupStatus = "uploaded")),
			local = listOf(localItem(id = 42L)),
		)
		assertEquals(1, entries.size)
		val entry = entries.first()
		assertTrue(entry.isIndexed)
		assertTrue(entry.hasLocal)
		assertTrue(entry.isUploaded)
		assertFalse(entry.isLocalOnly)
		assertFalse(entry.isCloudOnly)
	}

	@Test
	fun `merge keeps local-only and kDrive cloud-only items apart`() {
		val entries = mergeGalleryEntries(
			cloud = listOf(cloudItem(externalKey = "file-1", sourceKind = "kdrive")),
			local = listOf(localItem(id = 7L)),
		)
		assertEquals(2, entries.size)
		assertTrue(entries.any { it.isKDriveSource && it.isCloudOnly })
		assertTrue(entries.any { it.isLocalOnly })
	}

	@Test
	fun `merge sorts by date, newest first, undated last`() {
		val entries = mergeGalleryEntries(
			cloud = listOf(cloudItem(externalKey = "a", takenAtMs = 1_000)),
			local = listOf(
				localItem(id = 2L, name = "new.jpg", takenAtMs = 3_000),
				localItem(id = 3L, name = "undated.jpg"),
			),
		)
		assertEquals(listOf("new.jpg", "IMG_0001.jpg", "undated.jpg"), entries.map { it.name })
	}

	@Test
	fun `merge interleaves cloud and device items by date`() {
		val entries = mergeGalleryEntries(
			cloud = listOf(
				cloudItem(externalKey = "a", name = "cloud-old.jpg", takenAtMs = 1_000),
				cloudItem(externalKey = "b", name = "cloud-new.jpg", takenAtMs = 4_000),
			),
			local = listOf(
				localItem(id = 2L, name = "device-mid.jpg", takenAtMs = 2_000),
			),
		)
		assertEquals(
			listOf("cloud-new.jpg", "device-mid.jpg", "cloud-old.jpg"),
			entries.map { it.name },
		)
	}

	@Test
	fun `filters by media type, upload state and metadata`() {
		val video = GalleryEntry(cloud = cloudItem(mediaType = "video"))
		val uploaded = GalleryEntry(cloud = cloudItem(backupStatus = "uploaded"))
		val localOnly = GalleryEntry(local = localItem(id = 9L))
		val partial = GalleryEntry(cloud = cloudItem(metadataStatus = "partial"))
		val noMetadata = GalleryEntry(cloud = cloudItem(metadataStatus = "none"))

		assertFalse(galleryEntryMatches(video, GalleryFilter(type = "image")))
		assertTrue(galleryEntryMatches(video, GalleryFilter(type = "video")))

		assertFalse(galleryEntryMatches(uploaded, GalleryFilter(upload = GalleryUploadFilter.Pending)))
		assertTrue(galleryEntryMatches(uploaded, GalleryFilter(upload = GalleryUploadFilter.Uploaded)))

		assertFalse(galleryEntryMatches(localOnly, GalleryFilter(upload = GalleryUploadFilter.Uploaded)))
		assertTrue(galleryEntryMatches(localOnly, GalleryFilter(upload = GalleryUploadFilter.Pending)))

		assertFalse(galleryEntryMatches(localOnly, GalleryFilter(missingOnly = true)))
		assertTrue(galleryEntryMatches(partial, GalleryFilter(missingOnly = true)))
		assertTrue(galleryEntryMatches(noMetadata, GalleryFilter(missingOnly = true)))
		assertFalse(galleryEntryMatches(uploaded, GalleryFilter(missingOnly = true)))
	}

	@Test
	fun `filter maps to the API backup status values`() {
		assertNull(GalleryFilter().backupStatus)
		assertEquals("uploaded", GalleryFilter(upload = GalleryUploadFilter.Uploaded).backupStatus)
		assertEquals(
			"none,pending,uploading,failed",
			GalleryFilter(upload = GalleryUploadFilter.Pending).backupStatus,
		)
	}

	@Test
	fun `capabilities drive the available actions`() {
		val uploaded = GalleryEntry(
			cloud = cloudItem(backupStatus = "uploaded"),
			local = localItem(id = 42L),
		)
		assertFalse(uploaded.canUpload)
		assertTrue(uploaded.canDeleteCloud)
		assertTrue(uploaded.canDeleteLocal)

		val localOnly = GalleryEntry(local = localItem(id = 9L))
		assertTrue(localOnly.canUpload)
		assertFalse(localOnly.canDeleteCloud)
		assertTrue(localOnly.canDeleteLocal)

		val kdrive = GalleryEntry(cloud = cloudItem(sourceKind = "kdrive"))
		assertFalse(kdrive.canUpload)
		assertTrue(kdrive.canDeleteCloud)
		assertFalse(kdrive.canDeleteLocal)
	}

	@Test
	fun `merge matches a device file with a reindexed cloud row`() {
		val entries = mergeGalleryEntries(
			cloud = listOf(cloudItem(externalKey = "old-asset-id", name = "IMG.jpg", sizeBytes = 100)),
			local = listOf(localItem(id = 99L, name = "IMG.jpg", sizeBytes = 100)),
		)
		assertEquals(1, entries.size)
		assertTrue(entries.first().isIndexed)
		assertTrue(entries.first().hasLocal)
	}

	@Test
	fun `merge keeps a second device file with the same name and size apart`() {
		val entries = mergeGalleryEntries(
			cloud = listOf(cloudItem(externalKey = "42", name = "IMG.jpg", sizeBytes = 100)),
			local = listOf(
				localItem(id = 42L, name = "IMG.jpg", sizeBytes = 100),
				localItem(id = 43L, name = "IMG.jpg", sizeBytes = 100),
			),
		)
		assertEquals(2, entries.size)
		assertEquals(2, entries.count { it.hasLocal })
		assertEquals(1, entries.count { it.isIndexed })
	}

	@Test
	fun `merge never matches kDrive items by name and size`() {
		val entries = mergeGalleryEntries(
			cloud = listOf(
				cloudItem(sourceKind = "kdrive", externalKey = "file-1", name = "IMG.jpg", sizeBytes = 100),
			),
			local = listOf(localItem(id = 5L, name = "IMG.jpg", sizeBytes = 100)),
		)
		assertEquals(2, entries.size)
	}
}
