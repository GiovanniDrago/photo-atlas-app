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

	@Test
	fun `folder matching prefers the exact album id`() {
		val exact = MediaSourceDto(
			id = "exact",
			kind = "local",
			label = "DCIM/Camera",
			rootPath = "album:42",
			albumKey = "album:42",
		)
		val legacy = MediaSourceDto(
			id = "legacy",
			kind = "local",
			label = "Camera",
			rootPath = "album:path:Camera",
			albumKey = "path:Camera",
		)
		val labelOnly = MediaSourceDto(
			id = "label",
			kind = "local",
			label = "Camera",
			rootPath = "album:path:Other",
		)
		val sources = listOf(labelOnly, legacy, exact)
		assertEquals("exact", SourceMatcher.findSourceForFolder(sources, "42", "Camera")?.id)
		assertEquals("legacy", SourceMatcher.findSourceForFolder(sources, "99", "Camera")?.id)
		assertNull(SourceMatcher.findSourceForFolder(sources, "99", "Pictures"))
	}

	@Test
	fun `folder matching ignores kdrive sources`() {
		val kdrive = MediaSourceDto(
			id = "k",
			kind = "kdrive",
			label = "Camera",
			rootPath = "album:42",
		)
		assertNull(SourceMatcher.findSourceForFolder(listOf(kdrive), "42", "Camera"))
	}
}
