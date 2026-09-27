package dev.giovannidrago.photoatlas.studio

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import dagger.hilt.android.AndroidEntryPoint
import dev.giovannidrago.photoatlas.studio.ui.AppRoot
import dev.giovannidrago.photoatlas.studio.ui.theme.PhotoAtlasStudioTheme

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
	override fun onCreate(savedInstanceState: Bundle?) {
		enableEdgeToEdge()
		super.onCreate(savedInstanceState)
		setContent {
			PhotoAtlasStudioTheme {
				AppRoot()
			}
		}
	}
}
