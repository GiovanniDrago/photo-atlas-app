package dev.giovannidrago.photoatlas.studio.domain.auth

import dev.giovannidrago.photoatlas.studio.data.remote.AuthUserDto

sealed interface AuthState {
	/** The stored session has not been checked yet. */
	data object Unknown : AuthState

	data object SignedOut : AuthState

	/** Password accepted, but the account has a verified TOTP factor (aal1). */
	data object MfaRequired : AuthState

	data class SignedIn(
		val user: AuthUserDto,
		val newRecoveryCodes: List<String> = emptyList(),
	) : AuthState
}
