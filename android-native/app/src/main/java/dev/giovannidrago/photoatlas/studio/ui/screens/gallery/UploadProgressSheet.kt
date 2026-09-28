package dev.giovannidrago.photoatlas.studio.ui.screens.gallery

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.domain.gallery.GalleryUploadState
import dev.giovannidrago.photoatlas.studio.domain.gallery.UploadEntryStatus
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Sync

/** Live detail of the running upload: overall progress, per-file rows, Stop. */
@Composable
fun UploadProgressSheet(
	state: GalleryUploadState,
	onStop: () -> Unit,
	onDismiss: () -> Unit,
) {
	Column(
		modifier = Modifier
			.fillMaxWidth()
			.padding(horizontal = 16.dp)
			.padding(bottom = 12.dp),
	) {
		Text(
			text = state.label,
			style = MaterialTheme.typography.titleMedium,
		)
		Spacer(Modifier.height(6.dp))
		Row(verticalAlignment = Alignment.CenterVertically) {
			Text(
				text = if (state.running) {
					state.currentName.orEmpty()
				} else {
					summary(state)
				},
				style = MaterialTheme.typography.bodySmall,
				maxLines = 1,
				overflow = TextOverflow.Ellipsis,
				modifier = Modifier.weight(1f),
			)
			Text(
				text = "${state.done}/${state.total}",
				style = MaterialTheme.typography.labelSmall,
			)
		}
		Spacer(Modifier.height(6.dp))
		LinearProgressIndicator(
			value = state.overallFraction?.toFloat(),
			modifier = Modifier.fillMaxWidth(),
		)
		if (state.running && state.failures.isNotEmpty()) {
			Spacer(Modifier.height(4.dp))
			Text(
				text = stringResource(R.string.failed_count, state.failures.size),
				style = MaterialTheme.typography.labelSmall,
				color = MaterialTheme.colorScheme.error,
			)
		}
		Spacer(Modifier.height(8.dp))
		LazyColumn(
			modifier = Modifier.heightIn(max = 320.dp),
			verticalArrangement = Arrangement.spacedBy(2.dp),
		) {
			itemsIndexed(state.targets) { index, entry ->
				UploadRow(
					name = entry.name,
					status = state.statusAt(index),
					error = state.failures[index],
					fileFraction = if (state.statusAt(index) == UploadEntryStatus.Current) {
						state.fileFraction
					} else {
						null
					},
					fileSent = state.fileSent,
					fileTotal = state.fileTotal,
				)
			}
		}
		Spacer(Modifier.height(10.dp))
		if (state.running) {
			OutlinedButton(
				onClick = onStop,
				enabled = !state.stopping,
				modifier = Modifier.fillMaxWidth(),
			) {
				Icon(Icons.Filled.Stop, contentDescription = null, modifier = Modifier.size(18.dp))
				Spacer(Modifier.size(8.dp))
				Text(
					stringResource(
						if (state.stopping) R.string.upload_stopping else R.string.upload_stop,
					),
				)
			}
		} else {
			TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) {
				Text(stringResource(R.string.close))
			}
		}
	}
}

@Composable
private fun UploadRow(
	name: String,
	status: UploadEntryStatus,
	error: String?,
	fileFraction: Double?,
	fileSent: Long,
	fileTotal: Long,
) {
	val scheme = MaterialTheme.colorScheme
	Row(verticalAlignment = Alignment.CenterVertically) {
		when (status) {
			UploadEntryStatus.Done -> Icon(
				Icons.Filled.CheckCircle,
				contentDescription = null,
				tint = scheme.primary,
				modifier = Modifier.size(18.dp),
			)
			UploadEntryStatus.Current -> Icon(
				Icons.Filled.Sync,
				contentDescription = null,
				tint = scheme.primary,
				modifier = Modifier.size(18.dp),
			)
			UploadEntryStatus.Failed -> Icon(
				Icons.Filled.ErrorOutline,
				contentDescription = null,
				tint = scheme.error,
				modifier = Modifier.size(18.dp),
			)
			UploadEntryStatus.Pending -> Icon(
				Icons.Filled.Schedule,
				contentDescription = null,
				tint = scheme.onSurfaceVariant,
				modifier = Modifier.size(18.dp),
			)
		}
		Spacer(Modifier.size(8.dp))
		Column(modifier = Modifier.weight(1f)) {
			Text(
				text = name,
				style = MaterialTheme.typography.bodySmall,
				maxLines = 1,
				overflow = TextOverflow.Ellipsis,
			)
			if (status == UploadEntryStatus.Failed && error != null) {
				Text(
					text = error,
					style = MaterialTheme.typography.labelSmall,
					color = scheme.error,
					maxLines = 1,
					overflow = TextOverflow.Ellipsis,
				)
			}
			if (status == UploadEntryStatus.Current && fileFraction != null) {
				Text(
					text = "${formatBytes(fileSent)} / ${formatBytes(fileTotal)}",
					style = MaterialTheme.typography.labelSmall,
					color = scheme.onSurfaceVariant,
				)
			}
		}
		if (status == UploadEntryStatus.Current && fileFraction != null) {
			Text(
				text = "${(fileFraction * 100).toInt()}%",
				style = MaterialTheme.typography.labelMedium,
			)
		}
	}
}

private fun summary(state: GalleryUploadState): String = when {
	state.cancelled -> "${state.uploaded}/${state.total}"
	state.failed > 0 -> "${state.uploaded} ok · ${state.failed} failed"
	else -> "${state.uploaded} ok"
}
