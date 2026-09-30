package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.data.discovery.ServerCandidates
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ServerCandidatesTest {
	@Test
	fun `private subnet accepts only private IPv4 addresses`() {
		assertEquals("10.234.121", ServerCandidates.privateSubnetPrefix("10.234.121.225"))
		assertEquals("192.168.1", ServerCandidates.privateSubnetPrefix("192.168.1.7"))
		assertEquals("172.16.4", ServerCandidates.privateSubnetPrefix("172.16.4.9"))
		assertEquals("172.31.255", ServerCandidates.privateSubnetPrefix("172.31.255.1"))
		assertNull(ServerCandidates.privateSubnetPrefix("172.32.0.1"))
		assertNull(ServerCandidates.privateSubnetPrefix("8.8.8.8"))
		assertNull(ServerCandidates.privateSubnetPrefix("100.64.0.1"))
		assertNull(ServerCandidates.privateSubnetPrefix("not-an-address"))
		assertNull(ServerCandidates.privateSubnetPrefix("10.234.121"))
		assertNull(ServerCandidates.privateSubnetPrefix("10.234.121.999"))
	}

	@Test
	fun `candidates list the preferred server before the saved one`() {
		val candidates = ServerCandidates.candidates(
			prefer = "http://10.0.0.5:8787/",
			saved = "http://10.0.0.9:8787",
		)
		assertEquals("http://10.0.0.5:8787", candidates.first())
		assertTrue(candidates.contains("http://10.0.0.9:8787"))
		assertTrue(candidates.contains(ServerCandidates.DefaultApiBaseUrl))
		assertTrue(candidates.contains(ServerCandidates.FallbackApiBaseUrl))
		assertEquals(candidates.size, candidates.toSet().size)
	}

	@Test
	fun `a blank stored value falls back to the default`() {
		assertEquals(ServerCandidates.DefaultApiBaseUrl, ServerCandidates.resolveStored(null))
		assertEquals(ServerCandidates.DefaultApiBaseUrl, ServerCandidates.resolveStored(""))
		assertEquals(ServerCandidates.DefaultApiBaseUrl, ServerCandidates.resolveStored("   "))
		assertEquals(
			"http://10.0.0.9:8787",
			ServerCandidates.resolveStored("http://10.0.0.9:8787/"),
		)
	}

	@Test
	fun `candidates skip empty values`() {
		val candidates = ServerCandidates.candidates(saved = "  ")
		assertEquals(ServerCandidates.DefaultApiBaseUrl, candidates.first())
		assertTrue(candidates.none { it.isEmpty() })
	}

	@Test
	fun `a bare address gets the http scheme`() {
		assertEquals("http://10.0.0.9:8787", ServerCandidates.normalize("10.0.0.9:8787"))
		assertEquals("http://10.0.0.9:8787", ServerCandidates.normalize(" 10.0.0.9:8787/ "))
		assertEquals("https://example.test", ServerCandidates.normalize("https://example.test/"))
		assertEquals("", ServerCandidates.normalize("   "))
	}
}
