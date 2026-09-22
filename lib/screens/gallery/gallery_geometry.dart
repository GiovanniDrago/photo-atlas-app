import 'dart:ui' show Offset;

/// Maps a position inside the gallery grid viewport to a tile index.
///
/// [localPosition] is relative to the grid viewport (not to the scrolled
/// content), so the scroll offset is added back when computing the row.
int? galleryIndexAt({
  required Offset localPosition,
  required double scrollOffset,
  required double tileSize,
  required int crossAxisCount,
  required int itemCount,
  double padding = 12,
  double spacing = 6,
}) {
  if (tileSize <= 0 || crossAxisCount <= 0 || itemCount <= 0) return null;
  final cell = tileSize + spacing;
  final column = ((localPosition.dx - padding) / cell).floor();
  final row = ((localPosition.dy + scrollOffset - padding) / cell).floor();
  if (column < 0 || column >= crossAxisCount || row < 0) return null;
  final index = row * crossAxisCount + column;
  if (index < 0 || index >= itemCount) return null;
  return index;
}
