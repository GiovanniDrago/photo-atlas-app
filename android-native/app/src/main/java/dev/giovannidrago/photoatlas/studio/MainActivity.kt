package dev.giovannidrago.photoatlas.studio

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import dev.giovannidrago.photoatlas.studio.ui.StudioApp
import dev.giovannidrago.photoatlas.studio.ui.theme.PhotoAtlasStudioTheme

class MainActivity : ComponentActivity() {
	override fun onCreate(savedInstanceState: Bundle?) {
		enableEdgeToEdge()
		super.onCreate(savedInstanceState)
		setContent {
			PhotoAtlasStudioTheme {
				StudioApp()
			}
		}
	}
}
