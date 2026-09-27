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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MarkEmailUnread
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthRepository
import kotlinx.coroutines.launch

@Composable
fun CheckEmailScreen(
	email: String,
	auth: AuthRepository,
	onBack: () -> Unit,
) {
	val scope = rememberCoroutineScope()
	var sending by mutableStateOf(false)
	var message by mutableStateOf<String?>(null)
	val resent = stringResource(R.string.auth_email_resent)

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
					imageVector = Icons.Filled.MarkEmailUnread,
					contentDescription = null,
					tint = MaterialTheme.colorScheme.primary,
					modifier = Modifier.size(48.dp),
				)
				Spacer(Modifier.height(8.dp))
				Text(
					text = stringResource(R.string.auth_check_email_title),
					style = MaterialTheme.typography.headlineSmall,
					textAlign = TextAlign.Center,
				)
				Spacer(Modifier.height(8.dp))
				Text(
					text = stringResource(R.string.auth_check_email_body, email),
					style = MaterialTheme.typography.bodySmall,
					color = MaterialTheme.colorScheme.onSurfaceVariant,
					textAlign = TextAlign.Center,
				)
				if (message != null) {
					Spacer(Modifier.height(12.dp))
					Text(
						text = message.orEmpty(),
						style = MaterialTheme.typography.bodySmall,
						textAlign = TextAlign.Center,
					)
				}
				Spacer(Modifier.height(16.dp))
				Button(
					onClick = {
						sending = true
						message = null
						scope.launch {
							try {
								auth.resendConfirmation(email)
								message = resent
							} catch (failure: Exception) {
								message = failure.message
							} finally {
								sending = false
							}
						}
					},
					enabled = !sending,
					modifier = Modifier.fillMaxWidth(),
				) {
					if (sending) {
						CircularProgressIndicator(
							modifier = Modifier.size(18.dp),
							strokeWidth = 2.dp,
						)
					} else {
						Text(stringResource(R.string.auth_resend_email))
					}
				}
				TextButton(onClick = onBack) {
					Text(stringResource(R.string.auth_back_to_login))
				}
			}
		}
	}
}
