package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEmptyReason
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryFilter
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryUploadFilter
import dev.giovannidrago.photoatlas.studio.domain.gallery.galleryEmptyReason
import org.junit.Assert.assertEquals
import org.junit.Test

class GalleryFilterTest {
	@Test
	fun `empty reason follows the active filter`() {
		assertEquals(
			GalleryEmptyReason.NoMedia,
			galleryEmptyReason(GalleryFilter()),
		)
		assertEquals(
			GalleryEmptyReason.Uploaded,
			galleryEmptyReason(GalleryFilter(upload = GalleryUploadFilter.Uploaded)),
		)
		assertEquals(
			GalleryEmptyReason.NotUploaded,
			galleryEmptyReason(GalleryFilter(upload = GalleryUploadFilter.Pending)),
		)
		assertEquals(
			GalleryEmptyReason.Filtered,
			galleryEmptyReason(GalleryFilter(type = "video")),
		)
		assertEquals(
			GalleryEmptyReason.Filtered,
			galleryEmptyReason(GalleryFilter(missingOnly = true)),
		)
	}
}
