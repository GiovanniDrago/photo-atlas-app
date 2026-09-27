package dev.giovannidrago.photoatlas.studio.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

private val base = Typography()

/// Material 3 typography with slightly tighter titles and semibold headings,
/// for a modern editorial look.
val StudioTypography: Typography = base.copy(
	displaySmall = base.displaySmall.copy(fontWeight = FontWeight.SemiBold),
	headlineMedium = base.headlineMedium.copy(fontWeight = FontWeight.SemiBold),
	headlineSmall = base.headlineSmall.copy(
		fontWeight = FontWeight.SemiBold,
		letterSpacing = (-0.2).sp,
	),
	titleLarge = base.titleLarge.copy(
		fontWeight = FontWeight.SemiBold,
		letterSpacing = (-0.2).sp,
	),
	titleMedium = base.titleMedium.copy(fontWeight = FontWeight.SemiBold),
	labelLarge = base.labelLarge.copy(fontWeight = FontWeight.SemiBold),
)
