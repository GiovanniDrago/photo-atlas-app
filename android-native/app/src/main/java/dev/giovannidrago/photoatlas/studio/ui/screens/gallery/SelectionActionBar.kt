package dev.giovannidrago.photoatlas.studio.ui.screens.gallery

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

data class SelectionAction(
	val icon: ImageVector,
	val label: String,
	val enabled: Boolean = true,
	val onClick: () -> Unit,
)

/** Bottom bar of the selection: up to four actions share the width, more scroll. */
@Composable
fun SelectionActionBar(actions: List<SelectionAction>) {
	val rowModifier = if (actions.size <= 4) {
		Modifier.fillMaxWidth()
	} else {
		Modifier.horizontalScroll(rememberScrollState())
	}
	Row(
		modifier = Modifier
			.fillMaxWidth()
			.background(MaterialTheme.colorScheme.surfaceContainer)
			.padding(horizontal = 8.dp, vertical = 4.dp),
	) {
		Row(modifier = rowModifier) {
			for (action in actions) {
				TextButton(
					onClick = action.onClick,
					enabled = action.enabled,
					modifier = if (actions.size <= 4) Modifier.weight(1f) else Modifier,
				) {
					Icon(action.icon, contentDescription = null, modifier = Modifier.size(18.dp))
					Spacer(Modifier.size(6.dp))
					Text(action.label)
				}
			}
		}
	}
}
