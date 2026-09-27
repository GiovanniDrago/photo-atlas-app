package dev.giovannidrago.photoatlas.studio.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import dev.giovannidrago.photoatlas.studio.R

/// Full screen route opened by the central action; the real flows (manual
/// uploads, per-folder backup, verification, background job) arrive in M5.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackupScreen(onBack: () -> Unit) {
	Scaffold(
		topBar = {
			TopAppBar(
				title = { Text(stringResource(R.string.backup_title)) },
				navigationIcon = {
					IconButton(onClick = onBack) {
						Icon(
							imageVector = Icons.AutoMirrored.Filled.ArrowBack,
							contentDescription = stringResource(R.string.action_back),
						)
					}
				},
			)
		},
	) { padding ->
		Box(modifier = Modifier.padding(padding)) {
			PlaceholderScreen(
				title = stringResource(R.string.placeholder_backup_title),
				text = stringResource(R.string.placeholder_backup_text),
				icon = Icons.Filled.CloudUpload,
				milestone = "M5",
			)
		}
	}
}
