package dev.giovannidrago.photoatlas.studio.ui.screens.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthRepository
import kotlinx.coroutines.launch

@Composable
fun MfaScreen(auth: AuthRepository) {
	val scope = rememberCoroutineScope()
	var code by remember { mutableStateOf("") }
	var loading by remember { mutableStateOf(false) }
	var error by remember { mutableStateOf<String?>(null) }
	var showLostDevice by remember { mutableStateOf(false) }
	val fieldsRequired = stringResource(R.string.auth_fields_required)

	Column(
		modifier = Modifier
			.fillMaxSize()
			.verticalScroll(rememberScrollState())
			.padding(PaddingValues(24.dp)),
		horizontalAlignment = Alignment.CenterHorizontally,
		verticalArrangement = Arrangement.Center,
	) {
		Card(modifier = Modifier.fillMaxWidth()) {
			Column(
				modifier = Modifier.padding(20.dp),
				horizontalAlignment = Alignment.CenterHorizontally,
			) {
				Icon(
					imageVector = Icons.Filled.Lock,
					contentDescription = null,
					tint = MaterialTheme.colorScheme.primary,
					modifier = Modifier.size(48.dp),
				)
				Spacer(Modifier.height(8.dp))
				Text(
					text = stringResource(R.string.auth_mfa_title),
					style = MaterialTheme.typography.headlineSmall,
					textAlign = TextAlign.Center,
				)
				Spacer(Modifier.height(8.dp))
				Text(
					text = stringResource(R.string.auth_mfa_prompt),
					style = MaterialTheme.typography.bodySmall,
					color = MaterialTheme.colorScheme.onSurfaceVariant,
					textAlign = TextAlign.Center,
				)
				Spacer(Modifier.height(20.dp))
				OutlinedTextField(
					value = code,
					onValueChange = { code = it },
					label = { Text(stringResource(R.string.auth_mfa_code)) },
					singleLine = true,
					textStyle = MaterialTheme.typography.titleLarge.copy(
						fontFamily = FontFamily.Monospace,
						textAlign = TextAlign.Center,
					),
					keyboardOptions = KeyboardOptions(
						keyboardType = KeyboardType.NumberPassword,
						imeAction = ImeAction.Done,
					),
					modifier = Modifier.fillMaxWidth(),
				)
				if (error != null) {
					Spacer(Modifier.height(12.dp))
					Text(
						text = error.orEmpty(),
						color = MaterialTheme.colorScheme.error,
						style = MaterialTheme.typography.bodySmall,
						textAlign = TextAlign.Center,
					)
				}
				Spacer(Modifier.height(16.dp))
				Button(
					onClick = {
						if (code.isBlank()) {
							error = fieldsRequired
							return@Button
						}
						loading = true
						error = null
						scope.launch {
							try {
								auth.verifyMfa(code)
							} catch (failure: Exception) {
								error = failure.message
							} finally {
								loading = false
							}
						}
					},
					enabled = !loading,
					modifier = Modifier.fillMaxWidth(),
				) {
					if (loading) {
						CircularProgressIndicator(
							modifier = Modifier.size(18.dp),
							strokeWidth = 2.dp,
						)
					} else {
						Text(stringResource(R.string.auth_mfa_verify))
					}
				}
				TextButton(onClick = { showLostDevice = true }, enabled = !loading) {
					Text(stringResource(R.string.auth_mfa_lost_device))
				}
				TextButton(
					onClick = { scope.launch { auth.cancelMfa() } },
					enabled = !loading,
				) {
					Text(stringResource(R.string.auth_mfa_cancel))
				}
			}
		}
	}

	if (showLostDevice) {
		LostDeviceDialog(
			auth = auth,
			onDismiss = { showLostDevice = false },
		)
	}
}

@Composable
private fun LostDeviceDialog(auth: AuthRepository, onDismiss: () -> Unit) {
	val scope = rememberCoroutineScope()
	var email by remember { mutableStateOf("") }
	var recoveryCode by remember { mutableStateOf("") }
	var loading by remember { mutableStateOf(false) }
	var error by remember { mutableStateOf<String?>(null) }
	val fieldsRequired = stringResource(R.string.auth_fields_required)

	AlertDialog(
		onDismissRequest = { if (!loading) onDismiss() },
		title = { Text(stringResource(R.string.auth_mfa_lost_device)) },
		text = {
			Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
				Text(
					text = stringResource(R.string.auth_mfa_lost_device_body),
					style = MaterialTheme.typography.bodySmall,
				)
				OutlinedTextField(
					value = email,
					onValueChange = { email = it },
					label = { Text(stringResource(R.string.auth_email)) },
					singleLine = true,
					keyboardOptions = KeyboardOptions(
						keyboardType = KeyboardType.Email,
						imeAction = ImeAction.Next,
					),
				)
				OutlinedTextField(
					value = recoveryCode,
					onValueChange = { recoveryCode = it },
					label = { Text(stringResource(R.string.forgot_password_code)) },
					singleLine = true,
					keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
				)
				if (error != null) {
					Text(
						text = error.orEmpty(),
						color = MaterialTheme.colorScheme.error,
						style = MaterialTheme.typography.bodySmall,
					)
				}
			}
		},
		confirmButton = {
			TextButton(
				onClick = {
					if (email.isBlank() || recoveryCode.isBlank()) {
						error = fieldsRequired
						return@TextButton
					}
					loading = true
					error = null
					scope.launch {
						try {
							auth.resetMfaWithCode(email, recoveryCode)
							auth.cancelMfa()
							onDismiss()
						} catch (failure: Exception) {
							error = failure.message
						} finally {
							loading = false
						}
					}
				},
				enabled = !loading,
			) {
				Text(stringResource(R.string.auth_mfa_reset_confirm))
			}
		},
		dismissButton = {
			TextButton(onClick = onDismiss, enabled = !loading) {
				Text(stringResource(R.string.cancel))
			}
		},
	)
}
