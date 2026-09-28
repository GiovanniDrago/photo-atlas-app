package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.domain.gallery.FileProgressThrottle
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryActionProgress
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryUploadState
import dev.giovannidrago.photoatlas.studio.domain.gallery.UploadEntryStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GalleryUploadStateTest {
	private fun state(): GalleryUploadState = GalleryUploadState(
		label = "Uploading",
		targets = listOf(
			dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry(
				local = localItem(id = 1L, name = "a.jpg"),
			),
			dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry(
				local = localItem(id = 2L, name = "b.jpg"),
			),
			dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry(
				local = localItem(id = 3L, name = "c.jpg"),
			),
		),
		total = 3,
	)

	@Test
	fun `records the current file, completed items and failures`() {
		var current = state()
		assertEquals(UploadEntryStatus.Current, current.statusAt(0))
		assertEquals(UploadEntryStatus.Pending, current.statusAt(1))

		current = current.record(GalleryActionProgress(done = 0, total = 3, currentName = "a.jpg"))
		assertEquals(UploadEntryStatus.Current, current.statusAt(0))

		current = current.record(GalleryActionProgress(done = 1, total = 3, currentName = "b.jpg"))
		assertEquals(UploadEntryStatus.Done, current.statusAt(0))
		assertEquals(UploadEntryStatus.Current, current.statusAt(1))
		assertEquals(1, current.done)

		current = current.record(
			GalleryActionProgress(
				done = 1,
				total = 3,
				currentName = "b.jpg",
				failedName = "b.jpg",
				error = "boom",
			),
		)
		assertEquals(UploadEntryStatus.Failed, current.statusAt(1))
		assertEquals("boom", current.failures[1])

		current = current.record(GalleryActionProgress(done = 2, total = 3, currentName = "c.jpg"))
		assertEquals(UploadEntryStatus.Failed, current.statusAt(1))
		assertEquals(UploadEntryStatus.Current, current.statusAt(2))
	}

	@Test
	fun `records single file bytes and clears them on the next item`() {
		var current = state()
		current = current.record(
			GalleryActionProgress(
				done = 0,
				total = 3,
				currentName = "a.jpg",
				fileSent = 50L,
				fileTotal = 200L,
			),
		)
		assertEquals(0.25, current.fileFraction ?: 0.0, 0.0001)
		assertEquals((0.0 + 0.25) / 3.0, current.overallFraction ?: 0.0, 0.0001)

		current = current.record(GalleryActionProgress(done = 1, total = 3, currentName = "b.jpg"))
		assertNull(current.fileFraction)
		assertEquals(1.0 / 3.0, current.overallFraction ?: 0.0, 0.0001)
	}

	@Test
	fun `finish closes the run with the counters`() {
		val finished = state()
			.record(
				GalleryActionProgress(
					done = 1,
					total = 3,
					currentName = "b.jpg",
					failedName = "b.jpg",
					error = "nope",
				),
			)
			.finish(uploaded = 2, failed = 1, cancelled = false)
		assertFalse(finished.running)
		assertFalse(finished.stopping)
		assertEquals(3, finished.done)
		assertNull(finished.currentName)
		assertEquals(2, finished.uploaded)
		assertEquals(1, finished.failed)
		assertEquals(UploadEntryStatus.Done, finished.statusAt(0))
		assertEquals(UploadEntryStatus.Failed, finished.statusAt(1))
	}

	@Test
	fun `markStopping flags the run and keeps the progress`() {
		val stopping = state().markStopping()
		assertTrue(stopping.stopping)
		assertTrue(stopping.running)
		assertEquals(UploadEntryStatus.Current, stopping.statusAt(0))
	}

	@Test
	fun `throttle emits at most once per percent and the last chunk`() {
		val throttle = FileProgressThrottle()
		assertTrue(throttle.shouldEmit(GalleryActionProgress(done = 0, total = 1)))
		assertFalse(
			throttle.shouldEmit(
				GalleryActionProgress(done = 0, total = 1, fileSent = 1L, fileTotal = 1000L),
			),
		)
		assertTrue(
			throttle.shouldEmit(
				GalleryActionProgress(done = 0, total = 1, fileSent = 10L, fileTotal = 1000L),
			),
		)
		assertFalse(
			throttle.shouldEmit(
				GalleryActionProgress(done = 0, total = 1, fileSent = 15L, fileTotal = 1000L),
			),
		)
		assertTrue(
			throttle.shouldEmit(
				GalleryActionProgress(done = 0, total = 1, fileSent = 1000L, fileTotal = 1000L),
			),
		)
		// The next item restarts the window.
		assertTrue(
			throttle.shouldEmit(
				GalleryActionProgress(done = 1, total = 2, fileSent = 10L, fileTotal = 1000L),
			),
		)
	}
}
