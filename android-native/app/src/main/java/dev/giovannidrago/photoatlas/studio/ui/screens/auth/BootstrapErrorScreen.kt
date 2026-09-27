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
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.ui.components.ServerPanel
import dev.giovannidrago.photoatlas.studio.ui.settings.SettingsViewModel

/** Shown when the API cannot be reached or does not return /api/config. */
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
			ServerPanel(
				url = viewModel.serverUrl,
				onUrlChange = viewModel::onServerUrlChange,
				onSave = viewModel::save,
				onDetect = viewModel::detect,
				detecting = viewModel.detecting,
				modifier = Modifier.padding(16.dp),
			)
		}
	}
}
