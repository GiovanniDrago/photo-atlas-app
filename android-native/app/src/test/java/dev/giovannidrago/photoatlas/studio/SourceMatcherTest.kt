package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.data.remote.MediaSourceDto
import dev.giovannidrago.photoatlas.studio.domain.gallery.SourceMatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SourceMatcherTest {
	@Test
	fun `folder name is the last path segment with a fallback`() {
		assertEquals("Camera", SourceMatcher.folderName("DCIM/Camera/"))
		assertEquals("Camera", SourceMatcher.folderName("DCIM/Camera"))
		assertEquals("Download", SourceMatcher.folderName("Download"))
		assertEquals("Manual", SourceMatcher.folderName(null))
		assertEquals("Manual", SourceMatcher.folderName(""))
		assertEquals("Manual", SourceMatcher.folderName("///"))
	}

	@Test
	fun `finds a source by label or legacy album key`() {
		val byLabel = MediaSourceDto(id = "1", kind = "local", label = "Camera")
		val byKey = MediaSourceDto(
			id = "2",
			kind = "local",
			label = "DCIM/Camera",
			albumKey = "path:Camera",
		)
		val kdrive = MediaSourceDto(id = "3", kind = "kdrive", label = "Camera")
		val sources = listOf(kdrive, byLabel, byKey)
		assertEquals(byLabel, SourceMatcher.findSource(sources, "Camera"))
		assertNull(SourceMatcher.findSource(sources, "Screenshots"))
	}

	@Test
	fun `matches only local sources`() {
		val kdrive = MediaSourceDto(id = "1", kind = "kdrive", label = "Camera")
		assertNull(SourceMatcher.findSource(listOf(kdrive), "Camera"))
	}
}
