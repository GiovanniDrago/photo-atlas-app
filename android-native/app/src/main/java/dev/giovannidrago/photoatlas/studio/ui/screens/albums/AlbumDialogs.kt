package dev.giovannidrago.photoatlas.studio.ui.screens.albums

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.foundation.text.KeyboardOptions
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.remote.AlbumDto

/** Name dialog shared by create and rename. */
@Composable
fun AlbumNameDialog(
	initialName: String = "",
	create: Boolean = false,
	onDismiss: () -> Unit,
	onConfirm: (String) -> Unit,
) {
	var name by remember { mutableStateOf(initialName) }
	AlertDialog(
		onDismissRequest = onDismiss,
		title = {
			Text(stringResource(if (create) R.string.album_create_title else R.string.album_rename))
		},
		text = {
			OutlinedTextField(
				value = name,
				onValueChange = { name = it },
				label = { Text(stringResource(R.string.album_name)) },
				singleLine = true,
				keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
			)
		},
		confirmButton = {
			TextButton(
				onClick = { onConfirm(name.trim()) },
				enabled = name.isNotBlank(),
			) {
				Text(stringResource(R.string.save))
			}
		},
		dismissButton = {
			TextButton(onClick = onDismiss) {
				Text(stringResource(R.string.cancel))
			}
		},
	)
}

@Composable
fun AlbumDeleteDialog(
	album: AlbumDto,
	onDismiss: () -> Unit,
	onConfirm: () -> Unit,
) {
	AlertDialog(
		onDismissRequest = onDismiss,
		title = { Text(stringResource(R.string.album_delete_title)) },
		text = { Text(stringResource(R.string.album_delete_body, album.name)) },
		confirmButton = {
			TextButton(onClick = onConfirm) {
				Text(stringResource(R.string.album_delete))
			}
		},
		dismissButton = {
			TextButton(onClick = onDismiss) {
				Text(stringResource(R.string.cancel))
			}
		},
	)
}
