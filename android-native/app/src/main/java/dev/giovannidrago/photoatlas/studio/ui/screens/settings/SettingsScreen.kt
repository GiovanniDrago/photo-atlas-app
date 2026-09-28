package dev.giovannidrago.photoatlas.studio.ui.screens.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.Password
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.giovannidrago.photoatlas.studio.BuildConfig
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.remote.AuthUserDto
import dev.giovannidrago.photoatlas.studio.data.remote.EnrollResponseDto
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthRepository
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthState
import dev.giovannidrago.photoatlas.studio.ui.components.QrCode
import dev.giovannidrago.photoatlas.studio.ui.components.RecoveryCodesDialog
import dev.giovannidrago.photoatlas.studio.ui.components.ServerPanel
import dev.giovannidrago.photoatlas.studio.ui.settings.ServerResult
import dev.giovannidrago.photoatlas.studio.ui.settings.SettingsViewModel
import kotlinx.coroutines.launch

/** Settings tab: server, account, security and about. */
@Composable
fun SettingsScreen(
	auth: AuthRepository,
	viewModel: SettingsViewModel,
) {
	val authState by auth.state.collectAsStateWithLifecycle()
	val user = (authState as? AuthState.SignedIn)?.user
	val snackbar = remember { SnackbarHostState() }
	val scope = rememberCoroutineScope()

	val mfaDisabledMessage = stringResource(R.string.security_mfa_disabled_message)
	val passwordUpdatedMessage = stringResource(R.string.security_change_password_done)
	var busy by remember { mutableStateOf(false) }
	var showSignOutEverywhere by remember { mutableStateOf(false) }
	var showChangePassword by remember { mutableStateOf(false) }
	var enrollment by remember { mutableStateOf<EnrollResponseDto?>(null) }
	var recoveryDialog by remember { mutableStateOf<Pair<List<String>, List<String>>?>(null) }

	fun notify(message: String?) {
		if (message.isNullOrBlank()) return
		scope.launch { snackbar.showSnackbar(message) }
	}

	Scaffold(
		containerColor = Color.Transparent,
		topBar = { TopAppBar(title = { Text(stringResource(R.string.tab_settings)) }) },
		snackbarHost = { SnackbarHost(snackbar) },
	) { padding ->
		Column(
			modifier = Modifier
				.fillMaxSize()
				.verticalScroll(rememberScrollState())
				.padding(padding)
				.padding(PaddingValues(16.dp)),
			verticalArrangement = Arrangement.spacedBy(12.dp),
		) {
			AccountCard(
				user = user,
				onLogout = { scope.launch { auth.logout() } },
				onSignOutEverywhere = { showSignOutEverywhere = true },
			)
			SecurityCard(
				user = user,
				busy = busy,
				onEnableMfa = {
					scope.launch {
						busy = true
						try {
							enrollment = auth.startEnrollment()
						} catch (failure: Exception) {
							notify(failure.message)
						} finally {
							busy = false
						}
					}
				},
				onDisableMfa = {
					scope.launch {
						busy = true
						try {
							auth.disableMfa()
							notify(mfaDisabledMessage)
						} catch (failure: Exception) {
							notify(failure.message)
						} finally {
							busy = false
						}
					}
				},
				onRegenerate = {
					scope.launch {
						busy = true
						try {
							val passwordCodes = auth.regenerateRecoveryCodes(null)
							val mfaCodes = if (user?.mfaEnabled == true) {
								auth.regenerateRecoveryCodes("mfa")
							} else {
								emptyList()
							}
							recoveryDialog = passwordCodes to mfaCodes
						} catch (failure: Exception) {
							notify(failure.message)
						} finally {
							busy = false
						}
					}
				},
				onChangePassword = { showChangePassword = true },
			)
			ServerCard(viewModel)
			AboutCard()
		}
	}

	if (showSignOutEverywhere) {
		AlertDialog(
			onDismissRequest = { showSignOutEverywhere = false },
			title = { Text(stringResource(R.string.security_sign_out_everywhere)) },
			text = { Text(stringResource(R.string.security_sign_out_everywhere_body)) },
			confirmButton = {
				TextButton(
					onClick = {
						showSignOutEverywhere = false
						scope.launch { auth.signOutEverywhere() }
					},
				) {
					Text(stringResource(R.string.security_sign_out_everywhere))
				}
			},
			dismissButton = {
				TextButton(onClick = { showSignOutEverywhere = false }) {
					Text(stringResource(R.string.cancel))
				}
			},
		)
	}

	if (showChangePassword) {
		ChangePasswordDialog(
			auth = auth,
			onDismiss = { showChangePassword = false },
			onDone = {
				showChangePassword = false
				notify(passwordUpdatedMessage)
			},
		)
	}

	enrollment?.let { current ->
		EnrollDialog(
			enrollment = current,
			onConfirm = { code ->
				scope.launch {
					busy = true
					try {
						val codes = auth.confirmEnrollment(current.id, code)
						enrollment = null
						recoveryDialog = emptyList<String>() to codes
					} catch (failure: Exception) {
						notify(failure.message)
					} finally {
						busy = false
					}
				}
			},
			onDismiss = {
				scope.launch { auth.cancelEnrollment(current.id) }
				enrollment = null
			},
		)
	}

	recoveryDialog?.let { (passwordCodes, mfaCodes) ->
		RecoveryCodesDialog(
			passwordCodes = passwordCodes,
			mfaCodes = mfaCodes,
			onDismiss = { recoveryDialog = null },
		)
	}
}

@Composable
private fun AccountCard(
	user: AuthUserDto?,
	onLogout: () -> Unit,
	onSignOutEverywhere: () -> Unit,
) {
	Card(modifier = Modifier.fillMaxWidth()) {
		Column {
			ListItem(
				leadingContent = { Icon(Icons.Filled.Person, contentDescription = null) },
				headlineContent = {
					Text(user?.email ?: stringResource(R.string.settings_account_section))
				},
				supportingContent = {
					val name = user?.displayName
					Text(
						text = if (name.isNullOrBlank()) {
							stringResource(R.string.settings_signed_in_as, user?.username.orEmpty())
						} else {
							name
						},
					)
				},
			)
			HorizontalDivider()
			ListItem(
				leadingContent = { Icon(Icons.Filled.Logout, contentDescription = null) },
				headlineContent = { Text(stringResource(R.string.settings_logout)) },
				modifier = Modifier.clickable(onClick = onLogout),
			)
			ListItem(
				leadingContent = { Icon(Icons.Filled.Security, contentDescription = null) },
				headlineContent = { Text(stringResource(R.string.security_sign_out_everywhere)) },
				modifier = Modifier.clickable(onClick = onSignOutEverywhere),
			)
		}
	}
}

@Composable
private fun SecurityCard(
	user: AuthUserDto?,
	busy: Boolean,
	onEnableMfa: () -> Unit,
	onDisableMfa: () -> Unit,
	onRegenerate: () -> Unit,
	onChangePassword: () -> Unit,
) {
	val mfaEnabled = user?.mfaEnabled == true
	Card(modifier = Modifier.fillMaxWidth()) {
		Column {
			ListItem(
				leadingContent = { Icon(Icons.Filled.QrCode2, contentDescription = null) },
				headlineContent = { Text(stringResource(R.string.security_mfa_title)) },
				supportingContent = {
					Text(
						stringResource(
							if (mfaEnabled) R.string.security_mfa_on else R.string.security_mfa_off,
						),
					)
				},
				trailingContent = {
					if (busy) {
						CircularProgressIndicator(
							modifier = Modifier.size(20.dp),
							strokeWidth = 2.dp,
						)
					} else if (mfaEnabled) {
						TextButton(onClick = onDisableMfa) {
							Text(stringResource(R.string.security_disable_mfa))
						}
					} else {
						FilledTonalButton(onClick = onEnableMfa) {
							Text(stringResource(R.string.security_enable_mfa))
						}
					}
				},
			)
			HorizontalDivider()
			ListItem(
				leadingContent = { Icon(Icons.Filled.VpnKey, contentDescription = null) },
				headlineContent = { Text(stringResource(R.string.security_regenerate_recovery)) },
				modifier = Modifier.clickable(enabled = !busy, onClick = onRegenerate),
			)
			HorizontalDivider()
			ListItem(
				leadingContent = { Icon(Icons.Filled.Password, contentDescription = null) },
				headlineContent = { Text(stringResource(R.string.security_change_password)) },
				modifier = Modifier.clickable(enabled = !busy, onClick = onChangePassword),
			)
		}
	}
}

@Composable
private fun ServerCard(viewModel: SettingsViewModel) {
	val result = viewModel.result
	Card(modifier = Modifier.fillMaxWidth()) {
		Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
			Text(
				text = stringResource(R.string.settings_server_section),
				style = MaterialTheme.typography.titleMedium,
			)
			ServerPanel(
				url = viewModel.serverUrl,
				onUrlChange = viewModel::onServerUrlChange,
				onSave = viewModel::save,
				onDetect = viewModel::detect,
				detecting = viewModel.detecting,
			)
			when (result) {
				is ServerResult.Found -> Text(
					text = stringResource(R.string.server_found, result.url),
					style = MaterialTheme.typography.bodySmall,
				)
				ServerResult.NotFound -> Text(
					text = stringResource(R.string.server_not_found),
					style = MaterialTheme.typography.bodySmall,
					color = MaterialTheme.colorScheme.error,
				)
				ServerResult.Saved -> Text(
					text = stringResource(R.string.saved),
					style = MaterialTheme.typography.bodySmall,
				)
				null -> Unit
			}
		}
	}
}

@Composable
private fun AboutCard() {
	Card(modifier = Modifier.fillMaxWidth()) {
		Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
			Text(
				text = stringResource(R.string.settings_about_section),
				style = MaterialTheme.typography.titleMedium,
			)
			ListItem(
				leadingContent = { Icon(Icons.Filled.DarkMode, contentDescription = null) },
				headlineContent = { Text(stringResource(R.string.settings_more_soon)) },
			)
			ListItem(
				leadingContent = { Icon(Icons.Filled.Language, contentDescription = null) },
				headlineContent = {
					Text(stringResource(R.string.settings_version, BuildConfig.VERSION_NAME))
				},
			)
		}
	}
}

@Composable
private fun ChangePasswordDialog(
	auth: AuthRepository,
	onDismiss: () -> Unit,
	onDone: () -> Unit,
) {
	val scope = rememberCoroutineScope()
	var current by remember { mutableStateOf("") }
	var newPassword by remember { mutableStateOf("") }
	var loading by remember { mutableStateOf(false) }
	var error by remember { mutableStateOf<String?>(null) }
	val fieldsRequired = stringResource(R.string.auth_fields_required)

	AlertDialog(
		onDismissRequest = { if (!loading) onDismiss() },
		title = { Text(stringResource(R.string.security_change_password)) },
		text = {
			Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
				OutlinedTextField(
					value = current,
					onValueChange = { current = it },
					label = { Text(stringResource(R.string.security_change_password_current)) },
					singleLine = true,
					visualTransformation = PasswordVisualTransformation(),
					keyboardOptions = KeyboardOptions(
						keyboardType = KeyboardType.Password,
						imeAction = ImeAction.Next,
					),
				)
				OutlinedTextField(
					value = newPassword,
					onValueChange = { newPassword = it },
					label = { Text(stringResource(R.string.security_change_password_new)) },
					singleLine = true,
					visualTransformation = PasswordVisualTransformation(),
					supportingText = { Text(stringResource(R.string.auth_password_min_hint)) },
					keyboardOptions = KeyboardOptions(
						keyboardType = KeyboardType.Password,
						imeAction = ImeAction.Done,
					),
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
					if (current.isEmpty() || newPassword.isEmpty()) {
						error = fieldsRequired
						return@TextButton
					}
					loading = true
					error = null
					scope.launch {
						try {
							auth.changePassword(current, newPassword)
							onDone()
						} catch (failure: Exception) {
							error = failure.message
						} finally {
							loading = false
						}
					}
				},
				enabled = !loading,
			) {
				Text(stringResource(R.string.save))
			}
		},
		dismissButton = {
			TextButton(onClick = onDismiss, enabled = !loading) {
				Text(stringResource(R.string.cancel))
			}
		},
	)
}

@Composable
private fun EnrollDialog(
	enrollment: EnrollResponseDto,
	onConfirm: (String) -> Unit,
	onDismiss: () -> Unit,
) {
	var code by remember { mutableStateOf("") }
	val uri = enrollment.totp?.uri.orEmpty()
	val secret = enrollment.totp?.secret.orEmpty()

	AlertDialog(
		onDismissRequest = onDismiss,
		title = { Text(stringResource(R.string.security_mfa_title)) },
		text = {
			Column(
				horizontalAlignment = Alignment.CenterHorizontally,
				verticalArrangement = Arrangement.spacedBy(12.dp),
			) {
				Text(
					text = stringResource(R.string.security_mfa_scan),
					style = MaterialTheme.typography.bodySmall,
				)
				QrCode(data = uri, size = 200.dp)
				Text(
					text = stringResource(R.string.security_mfa_secret_label),
					style = MaterialTheme.typography.labelSmall,
				)
				Text(text = secret, style = MaterialTheme.typography.bodyMedium)
				OutlinedTextField(
					value = code,
					onValueChange = { code = it },
					label = { Text(stringResource(R.string.security_mfa_enter_code)) },
					singleLine = true,
					keyboardOptions = KeyboardOptions(
						keyboardType = KeyboardType.NumberPassword,
						imeAction = ImeAction.Done,
					),
				)
			}
		},
		confirmButton = {
			TextButton(onClick = { onConfirm(code) }, enabled = code.isNotBlank()) {
				Text(stringResource(R.string.security_enable_mfa))
			}
		},
		dismissButton = {
			TextButton(onClick = onDismiss) {
				Text(stringResource(R.string.cancel))
			}
		},
	)
}
