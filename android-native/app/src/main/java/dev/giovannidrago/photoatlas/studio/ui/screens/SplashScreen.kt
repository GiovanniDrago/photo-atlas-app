package dev.giovannidrago.photoatlas.studio.ui.screens

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Public
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R

/** Startup screen while the API is discovered and the session restored. */
@Composable
fun SplashScreen(
	slow: Boolean = false,
	onServerSettings: (() -> Unit)? = null,
) {
	val scale by animateFloatAsState(
		targetValue = 1f,
		animationSpec = tween(600),
		label = "splash-scale",
	)
	Column(
		modifier = Modifier
			.fillMaxSize()
			.padding(32.dp),
		horizontalAlignment = Alignment.CenterHorizontally,
		verticalArrangement = Arrangement.Center,
	) {
		Icon(
			imageVector = Icons.Filled.Public,
			contentDescription = null,
			tint = MaterialTheme.colorScheme.primary,
			modifier = Modifier
				.size(64.dp)
				.scale(scale),
		)
		Spacer(Modifier.height(16.dp))
		Text(
			text = stringResource(R.string.app_name),
			style = MaterialTheme.typography.headlineSmall,
		)
		Spacer(Modifier.height(24.dp))
		CircularProgressIndicator()
		if (slow && onServerSettings != null) {
			Spacer(Modifier.height(24.dp))
			Text(
				text = stringResource(R.string.bootstrap_slow_hint),
				style = MaterialTheme.typography.bodySmall,
				color = MaterialTheme.colorScheme.onSurfaceVariant,
				textAlign = TextAlign.Center,
			)
			Spacer(Modifier.height(8.dp))
			TextButton(onClick = onServerSettings) {
				Text(stringResource(R.string.server_settings))
			}
		}
	}
}
