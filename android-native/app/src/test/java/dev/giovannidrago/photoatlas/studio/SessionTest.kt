package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.data.auth.Session
import dev.giovannidrago.photoatlas.studio.data.auth.toSession
import dev.giovannidrago.photoatlas.studio.data.remote.GoTrueSessionDto
import dev.giovannidrago.photoatlas.studio.data.remote.GoTrueUserDto
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionTest {
	@Test
	fun `go true session maps to the stored session`() {
		val dto = GoTrueSessionDto(
			accessToken = "access",
			refreshToken = "refresh",
			expiresIn = 3600,
			user = GoTrueUserDto(
				id = "user-1",
				email = "a@b.c",
				userMetadata = JsonObject(mapOf("display_name" to JsonPrimitive("Alice"))),
			),
		)
		val session = dto.toSession(nowMs = 1_000_000)
		assertEquals("access", session.accessToken)
		assertEquals("refresh", session.refreshToken)
		assertEquals("user-1", session.userId)
		assertEquals("a@b.c", session.email)
		assertEquals("Alice", session.displayName)
		assertEquals(1_000_000 + 3_600_000, session.expiresAtEpochMs)
	}

	@Test
	fun `expiry has a one minute safety margin`() {
		val session = Session(
			accessToken = "a",
			refreshToken = "r",
			expiresAtEpochMs = 1_000_000,
			userId = "u",
		)
		assertTrue(session.isExpired(nowMs = 941_000))
		assertFalse(session.isExpired(nowMs = 930_000))
	}

	@Test
	fun `session survives a json round trip`() {
		val session = Session(
			accessToken = "a",
			refreshToken = "r",
			expiresAtEpochMs = 42,
			userId = "u",
			email = "a@b.c",
			displayName = "Alice",
		)
		val json = Json { ignoreUnknownKeys = true }
		val restored = json.decodeFromString<Session>(json.encodeToString(session))
		assertEquals(session, restored)
	}
}
