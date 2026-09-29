package dev.giovannidrago.photoatlas.studio.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.ui.settings.CloudCheckStep
import dev.giovannidrago.photoatlas.studio.ui.settings.CloudCheckViewModel

/**
 * Read-only cloud self check: runs every step of the chain and shows the
 * outcome, so a screenshot is enough to see where the cloud data stops.
 */
@Composable
fun CloudCheckCard(viewModel: CloudCheckViewModel = hiltViewModel()) {
	val state by viewModel.state.collectAsStateWithLifecycle()
	Card(modifier = Modifier.fillMaxWidth()) {
		Column(
			modifier = Modifier.padding(16.dp),
			verticalArrangement = Arrangement.spacedBy(8.dp),
		) {
			Text(
				text = stringResource(R.string.cloud_check_title),
				style = MaterialTheme.typography.titleMedium,
			)
			Text(
				text = stringResource(R.string.cloud_check_hint),
				style = MaterialTheme.typography.bodySmall,
				color = MaterialTheme.colorScheme.onSurfaceVariant,
			)
			Button(onClick = viewModel::run, enabled = !state.running) {
				if (state.running) {
					CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
				} else {
					Text(stringResource(R.string.cloud_check_run))
				}
			}
			state.results.forEach { result ->
				Row(verticalAlignment = Alignment.Top) {
					Icon(
						imageVector = if (result.ok) {
							Icons.Filled.CheckCircle
						} else {
							Icons.Filled.ErrorOutline
						},
						contentDescription = null,
						tint = if (result.ok) {
							MaterialTheme.colorScheme.primary
						} else {
							MaterialTheme.colorScheme.error
						},
						modifier = Modifier.size(18.dp),
					)
					Spacer(Modifier.width(8.dp))
					Column {
						Text(
							text = stringResource(result.step.labelRes()),
							style = MaterialTheme.typography.labelMedium,
						)
						Text(
							text = result.detail,
							style = MaterialTheme.typography.bodySmall,
							color = if (result.ok) {
								MaterialTheme.colorScheme.onSurfaceVariant
							} else {
								MaterialTheme.colorScheme.error
							},
						)
					}
				}
			}
		}
	}
}

private fun CloudCheckStep.labelRes(): Int = when (this) {
	CloudCheckStep.Server -> R.string.cloud_check_step_server
	CloudCheckStep.Account -> R.string.cloud_check_step_account
	CloudCheckStep.KDrive -> R.string.cloud_check_step_kdrive
	CloudCheckStep.Sources -> R.string.cloud_check_step_sources
	CloudCheckStep.Totals -> R.string.cloud_check_step_totals
	CloudCheckStep.Uploaded -> R.string.cloud_check_step_uploaded
	CloudCheckStep.Clusters -> R.string.cloud_check_step_clusters
}
