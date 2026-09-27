package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.ui.StudioTab
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StudioTabTest {
	@Test
	fun `tabs have unique routes`() {
		val routes = StudioTab.entries.map { it.route }
		assertEquals(routes.size, routes.toSet().size)
		assertTrue(routes.contains("gallery"))
		assertTrue(routes.contains("albums"))
	}
}
