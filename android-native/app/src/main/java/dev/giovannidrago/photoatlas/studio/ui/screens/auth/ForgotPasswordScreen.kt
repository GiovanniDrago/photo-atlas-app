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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthRepository
import kotlinx.coroutines.launch

/** Reset with a one-time recovery code (no email involved). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ForgotPasswordScreen(
	auth: AuthRepository,
	onDone: () -> Unit,
	onBack: () -> Unit,
) {
	val scope = rememberCoroutineScope()
	var identifier by remember { mutableStateOf("") }
	var code by remember { mutableStateOf("") }
	var newPassword by remember { mutableStateOf("") }
	var loading by remember { mutableStateOf(false) }
	var error by remember { mutableStateOf<String?>(null) }
	val fieldsRequired = stringResource(R.string.auth_fields_required)

	Scaffold(
		topBar = {
			TopAppBar(
				title = { Text(stringResource(R.string.forgot_password_title)) },
				navigationIcon = {
					IconButton(onClick = onBack) {
						Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
					}
				},
			)
		},
	) { padding ->
		Column(
			modifier = Modifier
				.fillMaxSize()
				.verticalScroll(rememberScrollState())
				.padding(padding)
				.padding(PaddingValues(24.dp)),
			horizontalAlignment = Alignment.CenterHorizontally,
			verticalArrangement = Arrangement.Center,
		) {
			Card(modifier = Modifier.fillMaxWidth()) {
				Column(modifier = Modifier.padding(20.dp)) {
					Text(
						text = stringResource(R.string.forgot_password_hint),
						style = MaterialTheme.typography.bodySmall,
						color = MaterialTheme.colorScheme.onSurfaceVariant,
					)
					Spacer(Modifier.height(16.dp))
					OutlinedTextField(
						value = identifier,
						onValueChange = { identifier = it },
						label = { Text(stringResource(R.string.auth_email)) },
						singleLine = true,
						keyboardOptions = KeyboardOptions(
							keyboardType = KeyboardType.EmailAddress,
							imeAction = ImeAction.Next,
						),
						modifier = Modifier.fillMaxWidth(),
					)
					Spacer(Modifier.height(12.dp))
					OutlinedTextField(
						value = code,
						onValueChange = { code = it },
						label = { Text(stringResource(R.string.forgot_password_code)) },
						singleLine = true,
						keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
						modifier = Modifier.fillMaxWidth(),
					)
					Spacer(Modifier.height(12.dp))
					OutlinedTextField(
						value = newPassword,
						onValueChange = { newPassword = it },
						label = { Text(stringResource(R.string.forgot_password_new_password)) },
						singleLine = true,
						supportingText = { Text(stringResource(R.string.auth_password_min_hint)) },
						visualTransformation = PasswordVisualTransformation(),
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
						)
					}
					Spacer(Modifier.height(16.dp))
					Button(
						onClick = {
							if (identifier.isBlank() || code.isBlank() || newPassword.isEmpty()) {
								error = fieldsRequired
								return@Button
							}
							loading = true
							error = null
							scope.launch {
								try {
									auth.resetPasswordWithCode(identifier, code, newPassword)
									onDone()
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
							Text(stringResource(R.string.forgot_password_submit))
						}
					}
				}
			}
		}
	}
}
