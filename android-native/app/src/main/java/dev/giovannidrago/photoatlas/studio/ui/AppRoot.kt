package dev.giovannidrago.photoatlas.studio.ui

import androidx.activity.compose.BackHandler
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthRepository
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthState
import dev.giovannidrago.photoatlas.studio.ui.bootstrap.BootstrapState
import dev.giovannidrago.photoatlas.studio.ui.components.RecoveryCodesDialog
import dev.giovannidrago.photoatlas.studio.ui.components.ServerPanel
import dev.giovannidrago.photoatlas.studio.ui.screens.SplashScreen
import dev.giovannidrago.photoatlas.studio.ui.screens.auth.BootstrapErrorScreen
import dev.giovannidrago.photoatlas.studio.ui.screens.auth.CheckEmailScreen
import dev.giovannidrago.photoatlas.studio.ui.screens.auth.ForgotPasswordScreen
import dev.giovannidrago.photoatlas.studio.ui.screens.auth.LoginScreen
import dev.giovannidrago.photoatlas.studio.ui.screens.auth.MfaScreen
import dev.giovannidrago.photoatlas.studio.ui.settings.SettingsViewModel
import kotlinx.coroutines.delay

private sealed interface AuthRoute {
	data object Login : AuthRoute

	data object CheckEmail : AuthRoute

	data object ForgotPassword : AuthRoute
}

/** Root state machine: bootstrap, auth gate and the signed-in shell. */
@Composable
fun AppRoot() {
	val root: RootViewModel = hiltViewModel()
	val settingsViewModel: SettingsViewModel = hiltViewModel()
	val bootstrapState by root.bootstrap.state.collectAsStateWithLifecycle()
	val authState by root.auth.state.collectAsStateWithLifecycle()
	var slow by remember { mutableStateOf(false) }
	var showServerDialog by remember { mutableStateOf(false) }

	LaunchedEffect(Unit) {
		delay(6000)
		slow = true
	}

	Surface(color = androidx.compose.material3.MaterialTheme.colorScheme.background) {
		when (val bootstrap = bootstrapState) {
			is BootstrapState.Error -> BootstrapErrorScreen(
				message = bootstrap.message,
				viewModel = settingsViewModel,
			)

			BootstrapState.Loading -> SplashScreen(
				slow = slow,
				onServerSettings = { showServerDialog = true },
			)

			BootstrapState.Ready -> when (val auth = authState) {
				AuthState.Unknown -> SplashScreen()

				AuthState.MfaRequired -> MfaScreen(root.auth)

				AuthState.SignedOut -> AuthFlow(
					auth = root.auth,
					settingsViewModel = settingsViewModel,
				)

				is AuthState.SignedIn -> {
					StudioApp(auth = root.auth)
					if (auth.newRecoveryCodes.isNotEmpty()) {
						RecoveryCodesDialog(
							passwordCodes = auth.newRecoveryCodes,
							onDismiss = { root.auth.clearNewRecoveryCodes() },
						)
					}
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

@Composable
private fun AuthFlow(
	auth: AuthRepository,
	settingsViewModel: SettingsViewModel,
) {
	var route by remember { mutableStateOf<AuthRoute>(AuthRoute.Login) }
	var email by remember { mutableStateOf("") }

	when (route) {
		AuthRoute.Login -> LoginScreen(
			auth = auth,
			settingsViewModel = settingsViewModel,
			onCheckEmail = { value ->
				email = value
				route = AuthRoute.CheckEmail
			},
			onForgotPassword = { route = AuthRoute.ForgotPassword },
		)

		AuthRoute.CheckEmail -> {
			BackHandler { route = AuthRoute.Login }
			CheckEmailScreen(
				email = email,
				auth = auth,
				onBack = { route = AuthRoute.Login },
			)
		}

		AuthRoute.ForgotPassword -> {
			BackHandler { route = AuthRoute.Login }
			ForgotPasswordScreen(
				auth = auth,
				onDone = { route = AuthRoute.Login },
				onBack = { route = AuthRoute.Login },
			)
		}
	}
}
