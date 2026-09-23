import 'package:photo_manager/photo_manager.dart';

import 'media_item.dart';

/// A file present on the device: an Android media-library asset or a local
/// file on disk.
class LocalMedia {
  final String id;
  final String name;
  final String? path;

  /// Folder of the file on the device (for example `DCIM/Camera`).
  final String? relativePath;
  final String mediaType;
  final int? sizeBytes;
  final DateTime? takenAt;
  final DateTime? modifiedAt;
  final double? durationS;
  final int? width;
  final int? height;
  final AssetEntity? asset;
  final String? sourceLabel;

  const LocalMedia({
    required this.id,
    required this.name,
    required this.mediaType,
    this.path,
    this.relativePath,
    this.sizeBytes,
    this.takenAt,
    this.modifiedAt,
    this.durationS,
    this.width,
    this.height,
    this.asset,
    this.sourceLabel,
  });

  bool get isVideo => mediaType == 'video';
}

enum GalleryUploadFilter { all, uploaded, pending }

/// Gallery filters: media type, metadata completeness and backup state.
class GalleryFilter {
  final String type;
  final bool missingOnly;
  final GalleryUploadFilter upload;

  const GalleryFilter({
    this.type = 'all',
    this.missingOnly = false,
    this.upload = GalleryUploadFilter.all,
  });

  /// Value for the API `backup_status` filter, `null` when not restricted.
  String? get backupStatus => switch (upload) {
    GalleryUploadFilter.uploaded => 'uploaded',
    GalleryUploadFilter.pending => 'none,pending,uploading,failed',
    GalleryUploadFilter.all => null,
  };

  GalleryFilter copyWith({
    String? type,
    bool? missingOnly,
    GalleryUploadFilter? upload,
  }) {
    return GalleryFilter(
      type: type ?? this.type,
      missingOnly: missingOnly ?? this.missingOnly,
      upload: upload ?? this.upload,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GalleryFilter &&
      other.type == type &&
      other.missingOnly == missingOnly &&
      other.upload == upload;

  @override
  int get hashCode => Object.hash(type, missingOnly, upload);
}

/// One gallery tile: the indexed record, the device file, or both.
class GalleryEntry {
  final MediaItem? cloud;
  final LocalMedia? local;

  const GalleryEntry({this.cloud, this.local});

  /// Key used to match indexed items with device files. Local sources use the
  /// device asset id (Android) or the absolute path (desktop) as external key.
  static String cloudKey(MediaItem item) => item.sourceKind == 'kdrive'
      ? 'kdrive:${item.externalKey}'
      : 'local:${item.externalKey}';

  static String localKey(LocalMedia media) => 'local:${media.id}';

  String get key => cloud != null ? cloudKey(cloud!) : localKey(local!);

  String get name => cloud?.name ?? local?.name ?? '';
  String get mediaType => cloud?.mediaType ?? local?.mediaType ?? 'image';
  bool get isVideo => mediaType == 'video';
  String? get sourceLabel => cloud?.sourceLabel ?? local?.sourceLabel;
  int? get sizeBytes => cloud?.sizeBytes ?? local?.sizeBytes;
  String? get thumbnailUrl => cloud?.thumbnailUrl;
  String? get backupError => cloud?.backupError;

  DateTime? get sortDate =>
      cloud?.takenAt ??
      local?.takenAt ??
      cloud?.fileCreatedAt ??
      local?.modifiedAt;

  bool get isIndexed => cloud != null;
  bool get isUploaded => cloud?.isBackedUp ?? false;
  bool get isBackupFailed => cloud?.isBackupFailed ?? false;
  bool get hasLocal => local != null;
  bool get isCloudOnly => cloud != null && local == null;
  bool get isLocalOnly => cloud == null && local != null;
  bool get isKDriveSource => cloud?.sourceKind == 'kdrive';
  bool get canUpload => hasLocal && !isUploaded;
  bool get canDeleteCloud => isUploaded || isKDriveSource;
  bool get canDeleteLocal => hasLocal;

  bool get isMetadataMissing => cloud != null && !(cloud!.hasFullMetadata);
}

/// Merges indexed items with device files, newest first.
List<GalleryEntry> mergeGalleryEntries({
  required List<MediaItem> cloud,
  required List<LocalMedia> local,
}) {
  final entries = <String, GalleryEntry>{};
  final byNameSize = <String, String>{};
  for (final item in cloud) {
    final key = GalleryEntry.cloudKey(item);
    entries[key] = GalleryEntry(cloud: item);
    // Rebuilding the device media library assigns new asset ids, so indexed
    // items are matched by name and size as well to avoid showing a photo
    // twice (once from the cloud, once from the device).
    if (item.sourceKind != 'kdrive') {
      final size = item.sizeBytes;
      if (size != null && size > 0 && item.name.isNotEmpty) {
        byNameSize.putIfAbsent('${item.name}|$size', () => key);
      }
    }
  }
  for (final media in local) {
    var key = GalleryEntry.localKey(media);
    if (!entries.containsKey(key)) {
      final size = media.sizeBytes;
      if (size != null && size > 0 && media.name.isNotEmpty) {
        final candidate = byNameSize['${media.name}|$size'];
        final candidateEntry = candidate == null ? null : entries[candidate];
        if (candidate != null &&
            candidateEntry != null &&
            candidateEntry.local == null) {
          key = candidate;
        }
      }
    }
    final existing = entries[key];
    entries[key] = GalleryEntry(cloud: existing?.cloud, local: media);
  }
  final merged = entries.values.toList()
    ..sort((a, b) {
      final left = a.sortDate;
      final right = b.sortDate;
      if (left == null && right == null) return a.name.compareTo(b.name);
      if (left == null) return 1;
      if (right == null) return -1;
      final byDate = right.compareTo(left);
      return byDate != 0 ? byDate : a.name.compareTo(b.name);
    });
  return merged;
}

bool galleryEntryMatches(GalleryEntry entry, GalleryFilter filter) {
  if (filter.type != 'all' && entry.mediaType != filter.type) return false;
  final uploadOk = switch (filter.upload) {
    GalleryUploadFilter.uploaded => entry.isUploaded,
    GalleryUploadFilter.pending => !entry.isUploaded,
    GalleryUploadFilter.all => true,
  };
  if (!uploadOk) return false;
  if (filter.missingOnly) {
    final cloud = entry.cloud;
    if (cloud == null || cloud.hasFullMetadata) return false;
  }
  return true;
}
