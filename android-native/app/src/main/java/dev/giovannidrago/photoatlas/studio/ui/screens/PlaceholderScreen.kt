package dev.giovannidrago.photoatlas.studio.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R

/// Modern empty state used while a milestone is still being built.
@Composable
fun PlaceholderScreen(
	title: String,
	text: String,
	icon: ImageVector,
	milestone: String,
	footer: String? = null,
) {
	Column(
		modifier = Modifier
			.fillMaxSize()
			.padding(horizontal = 32.dp),
		horizontalAlignment = Alignment.CenterHorizontally,
		verticalArrangement = Arrangement.Center,
	) {
		Surface(
			shape = CircleShape,
			color = MaterialTheme.colorScheme.primaryContainer,
			modifier = Modifier.size(96.dp),
		) {
			Box(contentAlignment = Alignment.Center) {
				Icon(
					imageVector = icon,
					contentDescription = null,
					modifier = Modifier.size(44.dp),
					tint = MaterialTheme.colorScheme.onPrimaryContainer,
				)
			}
		}
		Spacer(Modifier.height(24.dp))
		Text(
			text = title,
			style = MaterialTheme.typography.headlineSmall,
			textAlign = TextAlign.Center,
		)
		Spacer(Modifier.height(8.dp))
		Text(
			text = text,
			style = MaterialTheme.typography.bodyMedium,
			color = MaterialTheme.colorScheme.onSurfaceVariant,
			textAlign = TextAlign.Center,
		)
		Spacer(Modifier.height(20.dp))
		SuggestionChip(
			onClick = {},
			label = { Text(stringResource(R.string.milestone_chip, milestone)) },
		)
		if (footer != null) {
			Spacer(Modifier.height(12.dp))
			Text(
				text = footer,
				style = MaterialTheme.typography.labelSmall,
				color = MaterialTheme.colorScheme.outline,
			)
		}
	}
}
