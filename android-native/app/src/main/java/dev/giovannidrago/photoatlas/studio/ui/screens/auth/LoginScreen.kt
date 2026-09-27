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
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthRepository
import dev.giovannidrago.photoatlas.studio.ui.components.ServerPanel
import dev.giovannidrago.photoatlas.studio.ui.settings.SettingsViewModel
import kotlinx.coroutines.launch

@Composable
fun LoginScreen(
	auth: AuthRepository,
	settingsViewModel: SettingsViewModel,
	onCheckEmail: (String) -> Unit,
	onForgotPassword: () -> Unit,
) {
	val scope = rememberCoroutineScope()
	var email by remember { mutableStateOf("") }
	var password by remember { mutableStateOf("") }
	var displayName by remember { mutableStateOf("") }
	var registerMode by remember { mutableStateOf(false) }
	var passwordVisible by remember { mutableStateOf(false) }
	var loading by remember { mutableStateOf(false) }
	var error by remember { mutableStateOf<String?>(null) }
	var showServerDialog by remember { mutableStateOf(false) }
	val fieldsRequired = stringResource(R.string.auth_fields_required)

	fun submit() {
		val cleanEmail = email.trim()
		if (cleanEmail.isEmpty() || password.isEmpty()) {
			error = fieldsRequired
			return
		}
		error = null
		loading = true
		scope.launch {
			try {
				if (registerMode) {
					val signedIn = auth.register(
						email = cleanEmail,
						password = password,
						displayName = displayName,
						redirectTo = null,
					)
					if (!signedIn) onCheckEmail(cleanEmail)
				} else {
					auth.signIn(cleanEmail, password)
				}
			} catch (failure: Exception) {
				error = failure.message
			} finally {
				loading = false
			}
		}
	}

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
					imageVector = Icons.Filled.Public,
					contentDescription = null,
					tint = MaterialTheme.colorScheme.primary,
					modifier = Modifier.size(48.dp),
				)
				Spacer(Modifier.height(8.dp))
				Text(
					text = stringResource(R.string.app_name),
					style = MaterialTheme.typography.headlineSmall,
					textAlign = TextAlign.Center,
				)
				Spacer(Modifier.height(4.dp))
				Text(
					text = stringResource(R.string.auth_welcome),
					style = MaterialTheme.typography.bodySmall,
					color = MaterialTheme.colorScheme.onSurfaceVariant,
					textAlign = TextAlign.Center,
				)
				Spacer(Modifier.height(20.dp))

				OutlinedTextField(
					value = email,
					onValueChange = { email = it },
					label = { Text(stringResource(R.string.auth_email)) },
					singleLine = true,
					keyboardOptions = KeyboardOptions(
						keyboardType = KeyboardType.EmailAddress,
						imeAction = ImeAction.Next,
					),
					modifier = Modifier.fillMaxWidth(),
				)
				if (registerMode) {
					Spacer(Modifier.height(12.dp))
					OutlinedTextField(
						value = displayName,
						onValueChange = { displayName = it },
						label = { Text(stringResource(R.string.auth_display_name)) },
						singleLine = true,
						keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
						modifier = Modifier.fillMaxWidth(),
					)
				}
				Spacer(Modifier.height(12.dp))
				OutlinedTextField(
					value = password,
					onValueChange = { password = it },
					label = { Text(stringResource(R.string.auth_password)) },
					singleLine = true,
					supportingText = if (registerMode) {
						{ Text(stringResource(R.string.auth_password_min_hint)) }
					} else {
						null
					},
					visualTransformation = if (passwordVisible) {
						VisualTransformation.None
					} else {
						PasswordVisualTransformation()
					},
					trailingIcon = {
						IconButton(onClick = { passwordVisible = !passwordVisible }) {
							Icon(
								imageVector = if (passwordVisible) {
									Icons.Filled.VisibilityOff
								} else {
									Icons.Filled.Visibility
								},
								contentDescription = null,
							)
						}
					},
					keyboardOptions = KeyboardOptions(
						keyboardType = KeyboardType.Password,
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
					onClick = { submit() },
					enabled = !loading,
					modifier = Modifier.fillMaxWidth(),
				) {
					if (loading) {
						CircularProgressIndicator(
							modifier = Modifier.size(18.dp),
							strokeWidth = 2.dp,
						)
					} else {
						Text(
							stringResource(
								if (registerMode) R.string.auth_create_account else R.string.auth_sign_in,
							),
						)
					}
				}
				TextButton(
					onClick = {
						registerMode = !registerMode
						error = null
					},
					enabled = !loading,
				) {
					Text(
						stringResource(
							if (registerMode) R.string.auth_switch_to_login else R.string.auth_switch_to_register,
						),
					)
				}
				if (!registerMode) {
					TextButton(onClick = onForgotPassword, enabled = !loading) {
						Text(stringResource(R.string.forgot_password))
					}
				}
				Spacer(Modifier.height(8.dp))
				TextButton(
					onClick = { showServerDialog = true },
					enabled = !loading,
				) {
					Icon(Icons.Filled.Dns, contentDescription = null)
					Spacer(Modifier.size(8.dp))
					Text(stringResource(R.string.server_settings))
				}
			}
		}
	}

	if (showServerDialog) {
		AlertDialog(
			onDismissRequest = { showServerDialog = false },
			title = { Text(stringResource(R.string.server_settings)) },
			text = {
				ServerPanel(
					url = settingsViewModel.serverUrl,
					onUrlChange = settingsViewModel::onServerUrlChange,
					onSave = settingsViewModel::save,
					onDetect = settingsViewModel::detect,
					detecting = settingsViewModel.detecting,
				)
			},
			confirmButton = {
				TextButton(onClick = { showServerDialog = false }) {
					Text(stringResource(R.string.close))
				}
			},
		)
	}
}
