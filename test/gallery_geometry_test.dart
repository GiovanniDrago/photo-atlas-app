import 'package:flutter_test/flutter_test.dart';
import 'package:photoatlas/screens/gallery/gallery_geometry.dart';

void main() {
  const tile = 100.0;
  int? indexAt(
    double x,
    double y, {
    double scrollOffset = 0,
    int itemCount = 30,
  }) {
    return galleryIndexAt(
      localPosition: Offset(x, y),
      scrollOffset: scrollOffset,
      tileSize: tile,
      crossAxisCount: 3,
      itemCount: itemCount,
    );
  }

  test('maps positions to the first row', () {
    expect(indexAt(20, 20), 0);
    expect(indexAt(20 + 106, 20), 1);
    expect(indexAt(20 + 212, 20), 2);
  });

  test('maps positions to the following rows', () {
    expect(indexAt(20, 20 + 106), 3);
    expect(indexAt(20 + 106, 20 + 212), 7);
  });

  test('accounts for the scroll offset', () {
    expect(indexAt(20, 20, scrollOffset: 106), 3);
    expect(indexAt(20, 20, scrollOffset: 106 * 4), 12);
  });

  test('returns null outside the grid', () {
    expect(indexAt(4, 20), isNull);
    expect(indexAt(20, 4), isNull);
    expect(indexAt(20, 20, scrollOffset: 106 * 10, itemCount: 30), isNull);
    expect(indexAt(20, 20, itemCount: 0), isNull);
  });

  test('handles positions inside the spacing gaps', () {
    expect(indexAt(20 + 100 + 3, 20), 1);
    expect(indexAt(20, 20 + 100 + 3), 3);
  });
}
