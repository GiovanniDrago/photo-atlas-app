package dev.giovannidrago.photoatlas.studio.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R

/** Editable API address with Save and Detect (LAN scan). */
@Composable
fun ServerPanel(
	url: String,
	onUrlChange: (String) -> Unit,
	onSave: () -> Unit,
	onDetect: () -> Unit,
	detecting: Boolean,
	modifier: Modifier = Modifier,
) {
	Column(
		modifier = modifier,
		verticalArrangement = Arrangement.spacedBy(8.dp),
	) {
		OutlinedTextField(
			value = url,
			onValueChange = onUrlChange,
			singleLine = true,
			label = { Text(stringResource(R.string.api_base_url)) },
			placeholder = { Text(stringResource(R.string.api_base_url_hint)) },
			keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
			modifier = Modifier.fillMaxWidth(),
		)
		Row(
			horizontalArrangement = Arrangement.spacedBy(8.dp),
			verticalAlignment = Alignment.CenterVertically,
		) {
			FilledTonalButton(onClick = onSave) {
				Text(stringResource(R.string.save))
			}
			OutlinedButton(onClick = onDetect, enabled = !detecting) {
				if (detecting) {
					CircularProgressIndicator(
						modifier = Modifier.size(16.dp),
						strokeWidth = 2.dp,
					)
				} else {
					Icon(Icons.Filled.Search, contentDescription = null)
				}
				Spacer(Modifier.width(8.dp))
				Text(stringResource(R.string.detect_server))
			}
		}
	}
}
