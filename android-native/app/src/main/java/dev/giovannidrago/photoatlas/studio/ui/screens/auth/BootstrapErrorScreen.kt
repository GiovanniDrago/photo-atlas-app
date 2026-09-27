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
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.NetworkCheck
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.ui.components.ServerPanel
import dev.giovannidrago.photoatlas.studio.ui.settings.ServerResult
import dev.giovannidrago.photoatlas.studio.ui.settings.SettingsViewModel

/**
 * Shown when the API cannot be reached or does not return /api/config: the
 * address can be edited, tested (health probe), detected on the LAN and the
 * bootstrap restarted.
 */
@Composable
fun BootstrapErrorScreen(
	message: String,
	viewModel: SettingsViewModel,
) {
	Column(
		modifier = Modifier
			.fillMaxSize()
			.verticalScroll(rememberScrollState())
			.padding(PaddingValues(24.dp)),
		horizontalAlignment = Alignment.CenterHorizontally,
		verticalArrangement = Arrangement.Center,
	) {
		Icon(
			imageVector = Icons.Filled.CloudOff,
			contentDescription = null,
			tint = MaterialTheme.colorScheme.primary,
			modifier = Modifier.size(48.dp),
		)
		Spacer(Modifier.height(12.dp))
		Text(
			text = stringResource(R.string.bootstrap_error_title),
			style = MaterialTheme.typography.headlineSmall,
			textAlign = TextAlign.Center,
		)
		Spacer(Modifier.height(8.dp))
		Text(
			text = stringResource(R.string.bootstrap_error_body),
			style = MaterialTheme.typography.bodySmall,
			color = MaterialTheme.colorScheme.onSurfaceVariant,
			textAlign = TextAlign.Center,
		)
		Spacer(Modifier.height(8.dp))
		Text(
			text = message,
			style = MaterialTheme.typography.labelSmall,
			color = MaterialTheme.colorScheme.error,
			textAlign = TextAlign.Center,
		)
		Spacer(Modifier.height(20.dp))
		Card(modifier = Modifier.fillMaxWidth()) {
			Column(modifier = Modifier.padding(16.dp)) {
				ServerPanel(
					url = viewModel.serverUrl,
					onUrlChange = viewModel::onServerUrlChange,
					onSave = viewModel::retry,
					onDetect = viewModel::detect,
					detecting = viewModel.detecting,
					primaryLabel = stringResource(R.string.retry),
				)
				Spacer(Modifier.height(8.dp))
				OutlinedButton(
					onClick = viewModel::testConnection,
					enabled = !viewModel.testing && !viewModel.detecting,
				) {
					if (viewModel.testing) {
						CircularProgressIndicator(
							modifier = Modifier.size(16.dp),
							strokeWidth = 2.dp,
						)
					} else {
						Icon(Icons.Filled.NetworkCheck, contentDescription = null)
					}
					Spacer(Modifier.size(8.dp))
					Text(stringResource(R.string.test_connection))
				}
				if (viewModel.candidates.isNotEmpty()) {
					Spacer(Modifier.height(12.dp))
					Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
						for (candidate in viewModel.candidates) {
							SuggestionChip(
								onClick = { viewModel.onServerUrlChange(candidate) },
								label = { Text(candidate) },
							)
						}
					}
				}
				val resultText = resultMessage(viewModel)
				if (resultText != null) {
					Spacer(Modifier.height(12.dp))
					Text(
						text = resultText.first,
						style = MaterialTheme.typography.bodySmall,
						color = if (resultText.second) {
							MaterialTheme.colorScheme.error
						} else {
							MaterialTheme.colorScheme.onSurfaceVariant
						},
						textAlign = TextAlign.Center,
					)
				}
			}
		}
	}
}

/** Message + whether it is a failure, for the last action. */
@Composable
private fun resultMessage(viewModel: SettingsViewModel): Pair<String, Boolean>? {
	viewModel.testResult?.let { online ->
		return if (online) {
			stringResource(R.string.server_test_ok) to false
		} else {
			stringResource(R.string.server_test_failed) to true
		}
	}
	return when (val result = viewModel.result) {
		is ServerResult.Found -> stringResource(R.string.server_found, result.url) to false
		ServerResult.NotFound -> stringResource(R.string.server_not_found) to true
		ServerResult.Saved -> stringResource(R.string.saved) to false
		null -> null
	}
}
