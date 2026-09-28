package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryEntry
import dev.giovannidrago.photoatlas.studio.domain.gallery.planDelete
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DeletePlanTest {
	private val uploadedWithDevice = GalleryEntry(
		cloud = cloudItem(id = "cloud-uploaded", externalKey = "42", backupStatus = "uploaded"),
		local = localItem(id = 42L),
	)
	private val uploadedCloudOnly = GalleryEntry(
		cloud = cloudItem(id = "cloud-only", externalKey = "99", backupStatus = "uploaded"),
	)
	private val pendingWithDevice = GalleryEntry(
		cloud = cloudItem(id = "cloud-pending", externalKey = "7"),
		local = localItem(id = 7L),
	)
	private val kdrive = GalleryEntry(
		cloud = cloudItem(id = "cloud-kdrive", externalKey = "file-1", sourceKind = "kdrive"),
	)

	@Test
	fun `cloud delete with the device copy gone drops the row`() {
		val plan = planDelete(
			entries = listOf(uploadedWithDevice),
			cloud = true,
			local = true,
			deletedLocalIds = setOf(42L),
		)
		assertEquals(listOf("cloud-uploaded"), plan.dropIds)
		assertTrue(plan.resetIds.isEmpty())
		assertTrue(plan.indexOnlyIds.isEmpty())
	}

	@Test
	fun `cloud delete with a surviving device copy resets the upload state`() {
		val plan = planDelete(
			entries = listOf(uploadedWithDevice),
			cloud = true,
			local = false,
			deletedLocalIds = emptySet(),
		)
		assertEquals(listOf("cloud-uploaded"), plan.resetIds)
		assertTrue(plan.dropIds.isEmpty())
	}

	@Test
	fun `cloud-only entries are dropped`() {
		val plan = planDelete(
			entries = listOf(uploadedCloudOnly, kdrive),
			cloud = true,
			local = false,
			deletedLocalIds = emptySet(),
		)
		assertEquals(listOf("cloud-only", "cloud-kdrive"), plan.dropIds)
		assertTrue(plan.resetIds.isEmpty())
	}

	@Test
	fun `device delete of a never uploaded item drops only the index row`() {
		val plan = planDelete(
			entries = listOf(pendingWithDevice),
			cloud = false,
			local = true,
			deletedLocalIds = setOf(7L),
		)
		assertEquals(listOf("cloud-pending"), plan.indexOnlyIds)
		assertTrue(plan.dropIds.isEmpty())
		assertTrue(plan.resetIds.isEmpty())
	}

	@Test
	fun `device delete alone keeps uploaded rows with their cloud copy`() {
		val plan = planDelete(
			entries = listOf(uploadedWithDevice),
			cloud = false,
			local = true,
			deletedLocalIds = setOf(42L),
		)
		assertTrue(plan.isEmpty)
	}

	@Test
	fun `cloud and device together drop uploaded rows`() {
		val plan = planDelete(
			entries = listOf(uploadedWithDevice, pendingWithDevice),
			cloud = true,
			local = true,
			deletedLocalIds = setOf(42L, 7L),
		)
		assertEquals(listOf("cloud-uploaded"), plan.dropIds)
		assertEquals(listOf("cloud-pending"), plan.indexOnlyIds)
	}

	@Test
	fun `nothing selected produces an empty plan`() {
		val plan = planDelete(
			entries = listOf(uploadedWithDevice, uploadedCloudOnly),
			cloud = false,
			local = false,
			deletedLocalIds = emptySet(),
		)
		assertTrue(plan.isEmpty)
	}
}
