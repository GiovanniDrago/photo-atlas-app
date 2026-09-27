package dev.giovannidrago.photoatlas.studio.domain.auth

import dev.giovannidrago.photoatlas.studio.data.auth.SessionManager
import dev.giovannidrago.photoatlas.studio.data.auth.toSession
import dev.giovannidrago.photoatlas.studio.data.remote.ApiException
import dev.giovannidrago.photoatlas.studio.data.remote.AuthUserDto
import dev.giovannidrago.photoatlas.studio.data.remote.EnrollResponseDto
import dev.giovannidrago.photoatlas.studio.data.remote.GoTrueClient
import dev.giovannidrago.photoatlas.studio.data.remote.GoTrueFactorDto
import dev.giovannidrago.photoatlas.studio.data.remote.MfaRequiredException
import dev.giovannidrago.photoatlas.studio.data.remote.PhotoAtlasClient
import dev.giovannidrago.photoatlas.studio.data.remote.SessionExpiredException
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * All authentication flows: Supabase GoTrue for credentials and MFA, our API
 * for the profile mirror and the recovery codes.
 */
@Singleton
class AuthRepository @Inject constructor(
	private val sessions: SessionManager,
	private val gotrue: GoTrueClient,
	private val api: PhotoAtlasClient,
	private val supabase: dev.giovannidrago.photoatlas.studio.data.remote.SupabaseConfigStore,
) {
	private val _state = MutableStateFlow<AuthState>(AuthState.Unknown)
	val state: StateFlow<AuthState> = _state.asStateFlow()

	/** Restores the stored session at bootstrap (refresh + profile check). */
	suspend fun restore(): AuthState {
		val stored = sessions.session.value ?: return set(AuthState.SignedOut)
		if (stored.isExpired()) sessions.refresh()
		val current = sessions.session.value ?: return set(AuthState.SignedOut)
		return settle(allowRefresh = true)
	}

	suspend fun signIn(email: String, password: String): AuthState {
		sessions.save(gotrue.signInWithPassword(email.trim(), password).toSession())
		return settle(allowRefresh = false)
	}

	/** False when the account still needs the email confirmation. */
	suspend fun register(
		email: String,
		password: String,
		displayName: String?,
		redirectTo: String?,
	): Boolean {
		val redirect = redirectTo ?: supabase.config.value?.emailConfirmRedirectUrl
		val dto = gotrue.signUp(email.trim(), password, displayName, redirect)
		if (dto.accessToken.isBlank() || dto.refreshToken.isBlank()) return false
		sessions.save(dto.toSession())
		settle(allowRefresh = false)
		return true
	}

	suspend fun resendConfirmation(email: String) {
		gotrue.resendSignup(email.trim())
	}

	suspend fun verifyMfa(code: String): AuthState {
		val factor = verifiedFactors().firstOrNull()
			?: throw ApiException(400, "no verified factor")
		val challenge = gotrue.challenge(factor.id)
		sessions.save(gotrue.verifyFactor(factor.id, challenge.id, code.trim()).toSession())
		return settle(allowRefresh = false)
	}

	suspend fun cancelMfa() {
		sessions.clear()
		set(AuthState.SignedOut)
	}

	suspend fun logout() {
		runCatching { gotrue.logout("local") }
		sessions.clear()
		set(AuthState.SignedOut)
	}

	suspend fun signOutEverywhere() {
		runCatching { gotrue.logout("global") }
		sessions.clear()
		set(AuthState.SignedOut)
	}

	suspend fun changePassword(currentPassword: String, newPassword: String) {
		gotrue.updatePassword(newPassword, currentPassword)
	}

	suspend fun refreshProfile(): AuthUserDto? {
		val user = runCatching { api.me() }.getOrNull() ?: return null
		val current = _state.value
		if (current is AuthState.SignedIn) _state.value = current.copy(user = user)
		return user
	}

	// --- MFA management ---

	suspend fun verifiedFactors(): List<GoTrueFactorDto> =
		gotrue.user().factors.orEmpty().filter { it.status == "verified" }

	suspend fun startEnrollment(): EnrollResponseDto = gotrue.enrollTotp("Photo Atlas")

	suspend fun confirmEnrollment(factorId: String, code: String): List<String> {
		val challenge = gotrue.challenge(factorId)
		sessions.save(gotrue.verifyFactor(factorId, challenge.id, code.trim()).toSession())
		runCatching { api.mfaSync() }
		refreshProfile()
		return api.regenerateRecoveryCodes("mfa")
	}

	suspend fun cancelEnrollment(factorId: String) {
		runCatching { gotrue.unenroll(factorId) }
	}

	suspend fun disableMfa() {
		verifiedFactors().forEach { factor -> gotrue.unenroll(factor.id) }
		runCatching { api.mfaSync() }
		refreshProfile()
	}

	// --- Recovery codes ---

	suspend fun recoveryCodeCounts() = api.recoveryCodeCounts()

	suspend fun regenerateRecoveryCodes(kind: String? = null): List<String> =
		api.regenerateRecoveryCodes(kind)

	suspend fun resetPasswordWithCode(identifier: String, recoveryCode: String, newPassword: String) {
		api.resetPasswordWithCode(identifier.trim(), recoveryCode.trim(), newPassword)
	}

	suspend fun resetMfaWithCode(identifier: String, recoveryCode: String) {
		api.resetMfaWithCode(identifier.trim(), recoveryCode.trim())
	}

	fun clearNewRecoveryCodes() {
		val current = _state.value
		if (current is AuthState.SignedIn) _state.value = current.copy(newRecoveryCodes = emptyList())
	}

	private suspend fun settle(allowRefresh: Boolean): AuthState {
		return try {
			signedIn(api.me())
		} catch (_: MfaRequiredException) {
			set(AuthState.MfaRequired)
		} catch (_: SessionExpiredException) {
			if (!allowRefresh) return set(AuthState.SignedOut)
			sessions.refresh() ?: return set(AuthState.SignedOut)
			settle(allowRefresh = false)
		} catch (_: Exception) {
			// The server is unreachable but the session is valid: keep the
			// local profile so the app can still open (like the Flutter app).
			val session = sessions.session.value
				?: return set(AuthState.SignedOut)
			signedIn(
				AuthUserDto(
					id = session.userId,
					email = session.email,
					displayName = session.displayName,
				),
			)
		}
	}

	private suspend fun signedIn(user: AuthUserDto): AuthState {
		val codes = ensureRecoveryCodes()
		val state = AuthState.SignedIn(user, codes)
		_state.value = state
		return state
	}

	/** First login without password reset codes: create and show them once. */
	private suspend fun ensureRecoveryCodes(): List<String> {
		return runCatching {
			if (api.recoveryCodeCounts().passwordRemaining > 0) emptyList()
			else api.regenerateRecoveryCodes(null)
		}.getOrDefault(emptyList())
	}

	private fun set(state: AuthState): AuthState {
		_state.value = state
		return state
	}
}
