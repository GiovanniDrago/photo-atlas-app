import 'package:flutter_test/flutter_test.dart';
import 'package:photoatlas/models/source.dart';

MediaSource source({
  String id = 'source-1',
  String kind = 'local',
  String label = 'Camera',
  String? rootPath = 'album:123',
  String? albumKey,
}) {
  return MediaSource(
    id: id,
    kind: kind,
    label: label,
    itemCount: 0,
    rootPath: rootPath,
    albumKey: albumKey,
  );
}

void main() {
  test('matches a folder by album id', () {
    final match = matchSourceForFolder(
      albumId: '123',
      folderName: 'Camera',
      sources: [source(rootPath: 'album:123', albumKey: 'album:123')],
    );
    expect(match?.id, 'source-1');
  });

  test('matches a legacy source by name', () {
    final match = matchSourceForFolder(
      albumId: '999',
      folderName: 'Camera',
      sources: [source(rootPath: 'album:path:Camera', albumKey: 'path:Camera')],
    );
    expect(match?.id, 'source-1');
  });

  test('matches a legacy source by label as a last resort', () {
    final match = matchSourceForFolder(
      albumId: '999',
      folderName: 'Camera',
      sources: [source(rootPath: 'album:other-id', label: 'Camera')],
    );
    expect(match?.id, 'source-1');
  });

  test('ignores kDrive sources and other folders', () {
    final match = matchSourceForFolder(
      albumId: '123',
      folderName: 'Camera',
      sources: [
        source(id: 'kdrive-1', kind: 'kdrive', label: 'Camera', rootPath: null),
        source(id: 'other', rootPath: 'album:456', label: 'Screenshots'),
      ],
    );
    expect(match, isNull);
  });

  test('prefers the exact album id over a legacy name match', () {
    final match = matchSourceForFolder(
      albumId: '123',
      folderName: 'Camera',
      sources: [
        source(id: 'legacy', rootPath: 'album:path:Camera'),
        source(id: 'exact', rootPath: 'album:123'),
      ],
    );
    expect(match?.id, 'exact');
  });
}
