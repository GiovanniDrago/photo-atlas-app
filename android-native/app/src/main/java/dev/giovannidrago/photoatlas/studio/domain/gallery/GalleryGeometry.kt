package dev.giovannidrago.photoatlas.studio.domain.gallery

/**
 * Maps a position inside the gallery grid viewport to a tile index.
 * [localY] is relative to the viewport (not the scrolled content), so the
 * scroll offset is added back when computing the row.
 */
fun galleryIndexAt(
	localX: Float,
	localY: Float,
	scrollOffset: Float,
	tileSize: Float,
	crossAxisCount: Int,
	itemCount: Int,
	padding: Float = 12f,
	spacing: Float = 6f,
): Int? {
	if (tileSize <= 0f || crossAxisCount <= 0 || itemCount <= 0) return null
	val cell = tileSize + spacing
	val column = ((localX - padding) / cell).toInt()
	val row = ((localY + scrollOffset - padding) / cell).toInt()
	if (column < 0 || column >= crossAxisCount || row < 0) return null
	val index = row * crossAxisCount + column
	if (index < 0 || index >= itemCount) return null
	return index
}
