package dev.giovannidrago.photoatlas.studio

import android.app.Application
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.decode.VideoFrameDecoder
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class StudioApplication : Application(), ImageLoaderFactory {
	/** Coil also renders video frames, used by the gallery tiles. */
	override fun newImageLoader(): ImageLoader = ImageLoader.Builder(this)
		.components { add(VideoFrameDecoder.Factory()) }
		.crossfade(150)
		.build()
}
