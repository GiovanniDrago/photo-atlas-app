package dev.giovannidrago.photoatlas.studio.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R

/** One-time recovery codes dialog: password reset and/or two-factor codes. */
@Composable
fun RecoveryCodesDialog(
	passwordCodes: List<String> = emptyList(),
	mfaCodes: List<String> = emptyList(),
	onDismiss: () -> Unit,
) {
	val clipboard = LocalClipboardManager.current
	val all = passwordCodes + mfaCodes
	AlertDialog(
		onDismissRequest = onDismiss,
		title = { Text(stringResource(R.string.auth_recovery_codes_title)) },
		text = {
			Column(
				modifier = Modifier.verticalScroll(rememberScrollState()),
				verticalArrangement = Arrangement.spacedBy(8.dp),
			) {
				Text(
					text = stringResource(R.string.auth_recovery_codes_body),
					style = MaterialTheme.typography.bodySmall,
				)
				SelectionContainer {
					Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
						if (passwordCodes.isNotEmpty()) {
							Text(
								text = stringResource(R.string.auth_recovery_codes_password_label),
								style = MaterialTheme.typography.titleSmall,
							)
							passwordCodes.forEach { code -> CodeLine(code) }
						}
						if (mfaCodes.isNotEmpty()) {
							Text(
								text = stringResource(R.string.auth_recovery_codes_mfa_label),
								style = MaterialTheme.typography.titleSmall,
							)
							mfaCodes.forEach { code -> CodeLine(code) }
						}
					}
				}
			}
		},
		confirmButton = {
			TextButton(onClick = onDismiss) {
				Text(stringResource(R.string.auth_recovery_codes_done))
			}
		},
		dismissButton = {
			TextButton(
				onClick = {
					clipboard.setText(AnnotatedString(all.joinToString("\n")))
				},
				enabled = all.isNotEmpty(),
			) {
				Text(stringResource(R.string.auth_recovery_codes_copy))
			}
		},
	)
}

@Composable
private fun CodeLine(code: String) {
	Text(
		text = code,
		fontFamily = FontFamily.Monospace,
		style = MaterialTheme.typography.titleMedium,
		modifier = Modifier.padding(vertical = 2.dp),
	)
}
