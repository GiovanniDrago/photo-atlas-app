package dev.giovannidrago.photoatlas.studio.data.map

import android.content.Context
import java.io.File
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.OnlineTileSourceBase

/** osmdroid setup and the CARTO raster tile sources (same look as Flutter). */
object OsmSupport {
	const val Attribution = "© OpenStreetMap · CARTO"

	fun configure(context: Context) {
		val configuration = Configuration.getInstance()
		configuration.userAgentValue = context.packageName
		val base = File(context.cacheDir, "osmdroid").apply { mkdirs() }
		configuration.osmdroidBasePath = base
		configuration.osmdroidTileCache = File(base, "tiles").apply { mkdirs() }
	}

	/** CARTO light basemap, 512 px @2x tiles (crisper on high density screens). */
	object CartoLightTileSource : OnlineTileSourceBase(
		"CARTO Light",
		2,
		20,
		512,
		"@2x.png",
		"https://a.basemaps.cartocdn.com/light_all/",
		"https://b.basemaps.cartocdn.com/light_all/",
		"https://c.basemaps.cartocdn.com/light_all/",
		"https://d.basemaps.cartocdn.com/light_all/",
	)

	object CartoDarkTileSource : OnlineTileSourceBase(
		"CARTO Dark",
		2,
		20,
		512,
		"@2x.png",
		"https://a.basemaps.cartocdn.com/dark_all/",
		"https://b.basemaps.cartocdn.com/dark_all/",
		"https://c.basemaps.cartocdn.com/dark_all/",
		"https://d.basemaps.cartocdn.com/dark_all/",
	)

	fun tileSource(dark: Boolean): OnlineTileSourceBase =
		if (dark) CartoDarkTileSource else CartoLightTileSource
}
