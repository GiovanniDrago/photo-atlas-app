import 'package:flutter_test/flutter_test.dart';
import 'package:photoatlas/models/gallery_entry.dart';
import 'package:photoatlas/models/media_item.dart';

MediaItem cloudItem({
  String id = '11111111-1111-1111-1111-111111111111',
  String externalKey = 'asset-1',
  String sourceKind = 'local',
  String name = 'IMG_0001.jpg',
  String mediaType = 'image',
  String metadataStatus = 'full',
  String backupStatus = 'none',
  DateTime? takenAt,
}) {
  return MediaItem.fromJson({
    'id': id,
    'source_id': '22222222-2222-2222-2222-222222222222',
    'external_key': externalKey,
    'name': name,
    'media_type': mediaType,
    'metadata_status': metadataStatus,
    'backup_status': backupStatus,
    'has_gps': false,
    'source_kind': sourceKind,
    'taken_at': takenAt?.toUtc().toIso8601String(),
  });
}

LocalMedia localItem({
  String id = 'asset-1',
  String name = 'IMG_0001.jpg',
  String mediaType = 'image',
  DateTime? takenAt,
}) {
  return LocalMedia(id: id, name: name, mediaType: mediaType, takenAt: takenAt);
}

void main() {
  test('merge pairs an indexed item with its device file', () {
    final entries = mergeGalleryEntries(
      cloud: [cloudItem(backupStatus: 'uploaded')],
      local: [localItem()],
    );
    expect(entries, hasLength(1));
    expect(entries.first.isIndexed, isTrue);
    expect(entries.first.hasLocal, isTrue);
    expect(entries.first.isUploaded, isTrue);
    expect(entries.first.isCloudOnly, isFalse);
    expect(entries.first.isLocalOnly, isFalse);
  });

  test('merge keeps local-only and cloud-only items apart', () {
    final entries = mergeGalleryEntries(
      cloud: [cloudItem(externalKey: 'asset-9', sourceKind: 'kdrive')],
      local: [localItem(id: 'asset-1')],
    );
    expect(entries, hasLength(2));
    expect(entries.where((entry) => entry.isLocalOnly), hasLength(1));
    expect(entries.where((entry) => entry.isCloudOnly), hasLength(1));
  });

  test('merge sorts by date, newest first, undated last', () {
    final entries = mergeGalleryEntries(
      cloud: [
        cloudItem(
          id: 'cloud-1',
          externalKey: 'asset-a',
          takenAt: DateTime.utc(2024, 1, 1),
        ),
      ],
      local: [
        localItem(id: 'asset-b', takenAt: DateTime.utc(2025, 5, 1)),
        localItem(id: 'asset-c'),
      ],
    );
    expect(entries.map((entry) => entry.name).toList(), isNotEmpty);
    expect(entries.first.local?.id, 'asset-b');
    expect(entries.last.local?.id, 'asset-c');
  });

  test('merge interleaves cloud and device items by date', () {
    final entries = mergeGalleryEntries(
      cloud: [
        cloudItem(
          id: 'cloud-1',
          externalKey: 'asset-a',
          takenAt: DateTime.utc(2025, 1, 10),
        ),
        cloudItem(
          id: 'cloud-2',
          externalKey: 'asset-b',
          takenAt: DateTime.utc(2025, 1, 6),
        ),
      ],
      local: [
        localItem(id: 'asset-c', takenAt: DateTime.utc(2025, 1, 12)),
        localItem(id: 'asset-d', takenAt: DateTime.utc(2025, 1, 8)),
      ],
    );
    expect(entries.map((entry) => entry.sortDate?.toUtc()).toList(), [
      DateTime.utc(2025, 1, 12),
      DateTime.utc(2025, 1, 10),
      DateTime.utc(2025, 1, 8),
      DateTime.utc(2025, 1, 6),
    ]);
  });

  test('filters by media type, upload state and metadata', () {
    final uploaded = GalleryEntry(
      cloud: cloudItem(backupStatus: 'uploaded'),
      local: localItem(),
    );
    final localOnly = GalleryEntry(local: localItem(id: 'asset-2'));
    final video = GalleryEntry(
      cloud: cloudItem(
        id: 'cloud-2',
        externalKey: 'asset-3',
        mediaType: 'video',
        metadataStatus: 'none',
      ),
    );

    expect(
      galleryEntryMatches(uploaded, const GalleryFilter(type: 'video')),
      isFalse,
    );
    expect(
      galleryEntryMatches(video, const GalleryFilter(type: 'video')),
      isTrue,
    );
    expect(
      galleryEntryMatches(
        uploaded,
        const GalleryFilter(upload: GalleryUploadFilter.uploaded),
      ),
      isTrue,
    );
    expect(
      galleryEntryMatches(
        localOnly,
        const GalleryFilter(upload: GalleryUploadFilter.uploaded),
      ),
      isFalse,
    );
    expect(
      galleryEntryMatches(
        localOnly,
        const GalleryFilter(upload: GalleryUploadFilter.pending),
      ),
      isTrue,
    );
    expect(
      galleryEntryMatches(localOnly, const GalleryFilter(missingOnly: true)),
      isFalse,
    );
    expect(
      galleryEntryMatches(video, const GalleryFilter(missingOnly: true)),
      isTrue,
    );
  });

  test('filter maps to the API backup status values', () {
    expect(const GalleryFilter().backupStatus, isNull);
    expect(
      const GalleryFilter(upload: GalleryUploadFilter.uploaded).backupStatus,
      'uploaded',
    );
    expect(
      const GalleryFilter(upload: GalleryUploadFilter.pending).backupStatus,
      'none,pending,uploading,failed',
    );
  });

  test('entry capabilities drive the available actions', () {
    final uploaded = GalleryEntry(
      cloud: cloudItem(backupStatus: 'uploaded'),
      local: localItem(),
    );
    final localOnly = GalleryEntry(local: localItem(id: 'asset-2'));
    final kdrive = GalleryEntry(
      cloud: cloudItem(externalKey: '42', sourceKind: 'kdrive'),
    );

    expect(uploaded.canUpload, isFalse);
    expect(uploaded.canDeleteCloud, isTrue);
    expect(uploaded.canDeleteLocal, isTrue);
    expect(localOnly.canUpload, isTrue);
    expect(localOnly.canDeleteCloud, isFalse);
    expect(kdrive.canDeleteCloud, isTrue);
    expect(kdrive.canDeleteLocal, isFalse);
  });

  test('merge matches a device file with a reindexed cloud row', () {
    final entries = mergeGalleryEntries(
      cloud: [
        cloudItem(
          externalKey: 'stale-asset-id',
          name: 'PXL_20260819_121415527.MP.jpg',
          sizeBytes: 5673031,
          backupStatus: 'uploaded',
        ),
      ],
      local: [
        localItem(
          id: 'fresh-asset-id',
          name: 'PXL_20260819_121415527.MP.jpg',
          sizeBytes: 5673031,
        ),
      ],
    );
    expect(entries, hasLength(1));
    expect(entries.first.hasLocal, isTrue);
    expect(entries.first.isIndexed, isTrue);
    expect(entries.first.isUploaded, isTrue);
  });

  test(
    'merge keeps a second device file with the same name and size apart',
    () {
      final entries = mergeGalleryEntries(
        cloud: [
          cloudItem(externalKey: 'stale', name: 'IMG.jpg', sizeBytes: 100),
        ],
        local: [
          localItem(id: 'new-1', name: 'IMG.jpg', sizeBytes: 100),
          localItem(id: 'new-2', name: 'IMG.jpg', sizeBytes: 100),
        ],
      );
      expect(entries, hasLength(2));
      expect(entries.where((entry) => entry.hasLocal), hasLength(2));
      expect(entries.where((entry) => entry.isIndexed), hasLength(1));
    },
  );

  test('merge never matches kDrive items by name and size', () {
    final entries = mergeGalleryEntries(
      cloud: [
        cloudItem(
          externalKey: '42',
          sourceKind: 'kdrive',
          name: 'IMG.jpg',
          sizeBytes: 100,
        ),
      ],
      local: [localItem(id: 'new-1', name: 'IMG.jpg', sizeBytes: 100)],
    );
    expect(entries, hasLength(2));
    expect(entries.where((entry) => entry.isLocalOnly), hasLength(1));
    expect(entries.where((entry) => entry.isCloudOnly), hasLength(1));
  });
}
