import 'package:flutter_test/flutter_test.dart';
import 'package:photoatlas/models/gallery_entry.dart';
import 'package:photoatlas/models/media_item.dart';
import 'package:photoatlas/services/folder_launcher_io.dart';
import 'package:photoatlas/services/media_merge_service.dart';

MediaItem cloudItem({
  String id = 'cloud-1',
  String name = 'IMG_0001.jpg',
  int? sizeBytes = 100,
  String sourceKind = 'local',
  String? path,
}) {
  return MediaItem.fromJson({
    'id': id,
    'source_id': 'source-1',
    'external_key': 'stale-asset-id',
    'name': name,
    'media_type': 'image',
    'metadata_status': 'full',
    'backup_status': 'uploaded',
    'size_bytes': sizeBytes,
    'has_gps': false,
    'source_kind': sourceKind,
    'path': path,
  });
}

LocalMedia localItem({
  String id = 'device-1',
  String name = 'IMG_0001.jpg',
  int sizeBytes = 100,
  String? relativePath = 'DCIM/Camera',
}) {
  return LocalMedia(
    id: id,
    name: name,
    mediaType: 'image',
    sizeBytes: sizeBytes,
    relativePath: relativePath,
  );
}

void main() {
  test('matches indexed items with the device file by name and size', () {
    final entries = mergeCloudWithIndex(
      [cloudItem()],
      {'IMG_0001.jpg|100': localItem()},
    );
    expect(entries, hasLength(1));
    expect(entries.first.hasLocal, isTrue);
    expect(entries.first.isIndexed, isTrue);
    expect(entries.first.local?.relativePath, 'DCIM/Camera');
  });

  test('keeps items without a match cloud only', () {
    final entries = mergeCloudWithIndex(
      [cloudItem(name: 'other.jpg')],
      {'IMG_0001.jpg|100': localItem()},
    );
    expect(entries, hasLength(1));
    expect(entries.first.isCloudOnly, isTrue);
  });

  test('never matches kDrive items', () {
    final entries = mergeCloudWithIndex(
      [cloudItem(sourceKind: 'kdrive')],
      {'IMG_0001.jpg|100': localItem()},
    );
    expect(entries, hasLength(1));
    expect(entries.first.isCloudOnly, isTrue);
  });

  test('returns cloud only entries when the device index is empty', () {
    final entries = mergeCloudWithIndex([cloudItem()], const {});
    expect(entries, hasLength(1));
    expect(entries.first.isCloudOnly, isTrue);
  });

  test('builds a DocumentsUI folder uri on Android', () {
    final uri = deviceFolderUri(relativePath: 'DCIM/Camera');
    expect(uri.toString(), contains('com.android.externalstorage.documents'));
    expect(uri.toString(), contains('primary%3ADCIM%2FCamera'));
  });

  test('falls back to a file uri and to null', () {
    expect(
      deviceFolderUri(
        absolutePath: '/home/x/Pictures',
        isAndroid: false,
      ).toString(),
      'file:///home/x/Pictures',
    );
    expect(deviceFolderUri(), isNull);
  });
}
