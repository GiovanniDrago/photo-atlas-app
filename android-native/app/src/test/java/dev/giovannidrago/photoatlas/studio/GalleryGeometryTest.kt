package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.domain.gallery.galleryIndexAt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GalleryGeometryTest {
	private fun indexAt(
		x: Float,
		y: Float,
		scrollOffset: Float = 0f,
		itemCount: Int = 30,
	): Int? = galleryIndexAt(
		localX = x,
		localY = y,
		scrollOffset = scrollOffset,
		tileSize = 100f,
		crossAxisCount = 3,
		itemCount = itemCount,
	)

	@Test
	fun `maps positions to the first row`() {
		assertEquals(0, indexAt(20f, 20f))
		assertEquals(1, indexAt(20f + 106f, 20f))
		assertEquals(2, indexAt(20f + 212f, 20f))
	}

	@Test
	fun `maps positions to the following rows`() {
		assertEquals(3, indexAt(20f, 20f + 106f))
		assertEquals(7, indexAt(20f + 106f, 20f + 212f))
	}

	@Test
	fun `accounts for the scroll offset`() {
		assertEquals(3, indexAt(20f, 20f, scrollOffset = 106f))
		assertEquals(12, indexAt(20f, 20f, scrollOffset = 106f * 4f))
	}

	@Test
	fun `returns null outside the grid`() {
		assertNull(indexAt(4f, 20f))
		assertNull(indexAt(20f, 4f))
		assertNull(indexAt(20f, 20f, scrollOffset = 106f * 10f, itemCount = 30))
		assertNull(indexAt(20f, 20f, itemCount = 0))
	}

	@Test
	fun `handles positions inside the spacing gaps`() {
		assertEquals(1, indexAt(20f + 100f + 3f, 20f))
		assertEquals(3, indexAt(20f, 20f + 100f + 3f))
	}
}
