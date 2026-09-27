package dev.giovannidrago.photoatlas.studio.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

// --- Our API (photo-atlas-api) ---

@Serializable
data class ApiConfigDto(
	@SerialName("supabase_url") val supabaseUrl: String = "",
	@SerialName("supabase_publishable_key") val supabasePublishableKey: String = "",
	@SerialName("email_confirm_redirect_url") val emailConfirmRedirectUrl: String? = null,
)

@Serializable
data class AuthUserDto(
	val id: String = "",
	val email: String? = null,
	@SerialName("display_name") val displayName: String? = null,
	@SerialName("mfa_enabled") val mfaEnabled: Boolean = false,
	@SerialName("created_at") val createdAt: String? = null,
) {
	val username: String get() = email?.substringBefore('@') ?: ""
}

@Serializable
data class MeResponse(val user: AuthUserDto = AuthUserDto())

@Serializable
data class HealthResponse(val status: String = "", val database: String = "")

@Serializable
data class RecoveryCodeCountsResponse(
	@SerialName("password_remaining") val passwordRemaining: Int = 0,
	@SerialName("mfa_remaining") val mfaRemaining: Int = 0,
)

@Serializable
data class RecoveryCodesResponse(
	@SerialName("recovery_codes") val recoveryCodes: List<String> = emptyList(),
)

@Serializable
data class RegenerateCodesBody(val kind: String? = null)

@Serializable
data class ResetPasswordBody(
	val identifier: String,
	@SerialName("recovery_code") val recoveryCode: String,
	@SerialName("new_password") val newPassword: String,
)

@Serializable
data class ResetMfaBody(
	val identifier: String,
	@SerialName("recovery_code") val recoveryCode: String,
)

@Serializable
data class OkResponse(val ok: Boolean = false)

// --- Supabase GoTrue ---

@Serializable
data class GoTrueSessionDto(
	@SerialName("access_token") val accessToken: String = "",
	@SerialName("refresh_token") val refreshToken: String = "",
	@SerialName("expires_in") val expiresIn: Long? = null,
	@SerialName("token_type") val tokenType: String? = null,
	val user: GoTrueUserDto? = null,
)

@Serializable
data class GoTrueUserDto(
	val id: String = "",
	val email: String? = null,
	@SerialName("user_metadata") val userMetadata: JsonObject? = null,
	val factors: List<GoTrueFactorDto>? = null,
)

@Serializable
data class GoTrueFactorDto(
	val id: String = "",
	@SerialName("friendly_name") val friendlyName: String? = null,
	@SerialName("factor_type") val factorType: String? = null,
	val status: String? = null,
)

@Serializable
data class EnrollResponseDto(
	val id: String = "",
	val type: String? = null,
	val totp: TotpDto? = null,
)

@Serializable
data class TotpDto(
	@SerialName("qr_code") val qrCode: String? = null,
	val secret: String? = null,
	val uri: String? = null,
)

@Serializable
data class ChallengeResponseDto(
	val id: String = "",
	@SerialName("expires_at") val expiresAt: Long? = null,
)

@Serializable
data class PasswordGrantBody(val email: String, val password: String)

@Serializable
data class RefreshTokenBody(@SerialName("refresh_token") val refreshToken: String)

@Serializable
data class SignupBody(
	val email: String,
	val password: String,
	val data: SignupMetadata? = null,
)

@Serializable
data class SignupMetadata(@SerialName("display_name") val displayName: String)

@Serializable
data class ResendBody(val type: String, val email: String)

@Serializable
data class UpdateUserBody(
	val password: String? = null,
	@SerialName("current_password") val currentPassword: String? = null,
)

@Serializable
data class EnrollFactorBody(
	@SerialName("factor_type") val factorType: String,
	@SerialName("friendly_name") val friendlyName: String,
)

@Serializable
data class VerifyFactorBody(
	@SerialName("challenge_id") val challengeId: String,
	val code: String,
)
