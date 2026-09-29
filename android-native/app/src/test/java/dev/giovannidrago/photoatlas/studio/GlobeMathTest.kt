package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.domain.map.ClusterQuery
import dev.giovannidrago.photoatlas.studio.domain.map.GlobeMath
import dev.giovannidrago.photoatlas.studio.domain.map.LocationPicker
import dev.giovannidrago.photoatlas.studio.domain.map.MapThresholds
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class GlobeMathTest {
	@Test
	fun `projection maps known points`() {
		val center = GlobeMath.project(0.0, 0.0, 0.0, 0.0, 100f, 100f, 50f)
		assertNotNull(center)
		assertEquals(100f, center!!.first, 0.001f)
		assertEquals(100f, center.second, 0.001f)

		// North pole, seen from the equator: straight up.
		val north = GlobeMath.project(90.0, 0.0, 0.0, 0.0, 100f, 100f, 50f)!!
		assertEquals(100f, north.first, 0.001f)
		assertEquals(50f, north.second, 0.001f)

		// 90 degrees east: to the right of the center.
		val east = GlobeMath.project(0.0, 90.0, 0.0, 0.0, 100f, 100f, 50f)!!
		assertEquals(150f, east.first, 0.001f)
		assertEquals(100f, east.second, 0.001f)
	}

	@Test
	fun `points beyond the horizon are culled`() {
		// Center (0,0): the far side of the planet is hidden.
		assertNull(GlobeMath.project(0.0, 180.0, 0.0, 0.0, 100f, 100f, 50f))
		// Center (0,0) and 90 degrees away is on the rim (cosc = 0 > -0.03).
		assertNotNull(GlobeMath.project(0.0, 90.0, 0.0, 0.0, 100f, 100f, 50f))
		// Seen from lon 180 the antipode (0,0) is hidden.
		assertNull(GlobeMath.project(0.0, 0.0, 0.0, 180.0, 100f, 100f, 50f))
	}

	@Test
	fun `drag rotates, clamps latitude and wraps longitude`() {
		val scale = 1.0
		val (lat, lon) = GlobeMath.dragTo(
			centerLat = 0.0,
			centerLon = 0.0,
			deltaX = 100f,
			deltaY = 100f,
			scale = scale,
		)
		assertEquals(-35.0, lon, 0.001)
		assertEquals(35.0, lat, 0.001)

		val (clamped, _) = GlobeMath.dragTo(80.0, 0.0, 0f, 1000f, scale)
		assertEquals(75.0, clamped, 0.001)

		// Dragging left by 1000 px adds 350 degrees: 179 -> 529 -> 169.
		val (_, wrapped) = GlobeMath.dragTo(0.0, 179.0, -1000f, 0f, scale)
		assertEquals(169.0, wrapped, 0.001)
	}

	@Test
	fun `drag sensitivity scales with the zoom`() {
		val (lat, _) = GlobeMath.dragTo(0.0, 0.0, 0f, 100f, scale = 2.0)
		assertEquals(17.5, lat, 0.001)
	}

	@Test
	fun `cluster radius grows with the square root of the count`() {
		val small = GlobeMath.clusterRadius(100f, count = 1, maxCount = 100)
		val medium = GlobeMath.clusterRadius(100f, count = 25, maxCount = 100)
		val big = GlobeMath.clusterRadius(100f, count = 100, maxCount = 100)
		assertEquals((100f * (0.025 + 0.075 * 0.1) + 3f).toFloat(), small, 0.01f)
		assertEquals((100f * (0.025 + 0.075 * 0.5) + 3f).toFloat(), medium, 0.01f)
		assertEquals((100f * (0.025 + 0.075) + 3f).toFloat(), big, 0.01f)
		assertEquals(0f, GlobeMath.clusterLabelSize(0f), 0.001f)
		assertEquals(13f, GlobeMath.clusterLabelSize(100f), 0.001f)
	}

	@Test
	fun `hit test picks the nearest cluster within 32 pixels`() {
		val points = listOf(10f to 10f, 100f to 100f, 104f to 100f)
		assertEquals(0, GlobeMath.hitTest(points, 12f, 12f))
		assertEquals(2, GlobeMath.hitTest(points, 106f, 100f))
		assertNull(GlobeMath.hitTest(points, 500f, 500f))
	}

	@Test
	fun `zoom buckets and mode thresholds match the flutter app`() {
		assertEquals(1, MapThresholds.globeZoom(1.0))
		assertEquals(1, MapThresholds.globeZoom(1.39))
		assertEquals(2, MapThresholds.globeZoom(1.4))
		assertEquals(2, MapThresholds.globeZoom(1.79))
		assertEquals(3, MapThresholds.globeZoom(1.8))
		assertEquals(2.5, MapThresholds.GlobeToMapScale, 0.0001)
		assertEquals(2.6, MapThresholds.MapToGlobeZoom, 0.0001)
		assertEquals(4, MapThresholds.mapZoom(4.5))
		assertEquals(0, MapThresholds.mapZoom(-1.0))
		assertEquals(18, MapThresholds.mapZoom(30.0))
	}

	@Test
	fun `cluster query equality drives the cache`() {
		assertEquals(ClusterQuery.World, ClusterQuery.World)
		assertEquals(
			ClusterQuery.World.hashCode(),
			ClusterQuery(-180.0, -90.0, 90.0, 180.0, 1).hashCode(),
		)
		assertEquals(false, ClusterQuery.World == ClusterQuery.World.copy(zoom = 2))
	}

	@Test
	fun `picker radius helpers`() {
		assertEquals(5000.0, LocationPicker.clampRadius(null), 0.001)
		assertEquals(100.0, LocationPicker.clampRadius(10.0), 0.001)
		assertEquals(200000.0, LocationPicker.clampRadius(1_000_000.0), 0.001)
		assertEquals("5", LocationPicker.radiusKmLabel(5000.0))
		assertEquals("1.5", LocationPicker.radiusKmLabel(1500.0))
		assertEquals("200", LocationPicker.radiusKmLabel(200000.0))
		assertEquals(11.0, LocationPicker.zoomFor(hasCenter = true), 0.001)
		assertEquals(5.0, LocationPicker.zoomFor(hasCenter = false), 0.001)
	}
}
