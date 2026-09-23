import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

import '../models/gallery_entry.dart';
import 'api_client.dart';
import 'local_media_service.dart';
import 'scan_models.dart';
import 'scan_service.dart';

bool get isSupported => true;

const _cacheTtl = Duration(minutes: 5);

/// The full device list is reused for a short while so provider invalidations
/// (for example after a backup) do not re-read thousands of assets.
const _assetsCacheTtl = Duration(minutes: 2);

List<LocalMedia>? _cachedAssets;
DateTime? _cachedAssetsAt;
List<LocalMedia>? _cachedFiles;
DateTime? _cachedAt;

/// Loads the whole device library once, newest first and without duplicates.
Future<LocalMediaPage> loadAll({required ApiClient client}) async {
  final cached = _cachedAssets;
  final cachedAt = _cachedAssetsAt;
  if (cached != null &&
      cachedAt != null &&
      DateTime.now().difference(cachedAt) < _assetsCacheTtl) {
    return LocalMediaPage(items: cached, total: cached.length, hasMore: false);
  }
  if (ScanService.isAlbumBased) {
    final assets = await ScanService.listAllAssetsOnce();
    final items = _mapAssets(assets);
    items.sort(_newestFirst);
    _cachedAssets = items;
    _cachedAssetsAt = DateTime.now();
    return LocalMediaPage(items: items, total: items.length, hasMore: false);
  }
  final files = await _localFiles(client);
  return LocalMediaPage(items: files, total: files.length, hasMore: false);
}

/// One page of a single folder: a MediaStore bucket on Android, a local
/// folder on desktop. Loaded incrementally so memory stays bounded.
Future<LocalMediaPage> loadFolderPage({
  required ApiClient client,
  String? albumId,
  String? rootPath,
  required int page,
  int size = 120,
}) async {
  if (albumId != null && albumId.isNotEmpty) {
    final result = await ScanService.folderPage(
      albumId: albumId,
      page: page,
      size: size,
    );
    final items = _mapAssets(result.assets);
    return LocalMediaPage(
      items: items,
      total: result.total,
      hasMore: page * size + items.length < result.total,
    );
  }
  final files = await _localFiles(client);
  final root = rootPath;
  final filtered = (root == null || root.isEmpty)
      ? files
      : [
          for (final file in files)
            if ((file.path ?? '').startsWith(root)) file,
        ];
  final start = page * size;
  if (start >= filtered.length) {
    return LocalMediaPage(
      items: const [],
      total: filtered.length,
      hasMore: false,
    );
  }
  final end = start + size > filtered.length ? filtered.length : start + size;
  return LocalMediaPage(
    items: filtered.sublist(start, end),
    total: filtered.length,
    hasMore: end < filtered.length,
  );
}

/// The newest device files (collections preview).
Future<List<LocalMedia>> recent({int limit = 6}) async {
  if (!ScanService.isAlbumBased) return const [];
  final assets = await ScanService.recentAssets(limit: limit);
  return _mapAssets(assets);
}

List<LocalMedia> _mapAssets(List<AssetEntity> assets) {
  final items = <LocalMedia>[];
  final seen = <String>{};
  for (final asset in assets) {
    if (asset.type == AssetType.audio || asset.type == AssetType.other) {
      continue;
    }
    if (!seen.add(asset.id)) continue;
    final isVideo = asset.type == AssetType.video;
    items.add(
      LocalMedia(
        id: asset.id,
        name: asset.title ?? asset.id,
        mediaType: isVideo ? 'video' : 'image',
        takenAt: asset.createDateTime,
        modifiedAt: asset.modifiedDateTime,
        width: asset.width,
        height: asset.height,
        durationS: isVideo ? asset.duration.toDouble() : null,
        asset: asset,
      ),
    );
  }
  return items;
}

int _newestFirst(LocalMedia a, LocalMedia b) {
  final left = a.takenAt ?? a.modifiedAt;
  final right = b.takenAt ?? b.modifiedAt;
  if (left == null && right == null) return a.id.compareTo(b.id);
  if (left == null) return 1;
  if (right == null) return -1;
  final byDate = right.compareTo(left);
  return byDate != 0 ? byDate : a.id.compareTo(b.id);
}

Future<List<LocalMedia>> _localFiles(ApiClient client) async {
  final cached = _cachedFiles;
  final cachedAt = _cachedAt;
  if (cached != null &&
      cachedAt != null &&
      DateTime.now().difference(cachedAt) < _cacheTtl) {
    return cached;
  }
  final sources = await client.sources();
  final files = <LocalMedia>[];
  for (final source in sources) {
    if (source.kind != 'local') continue;
    final root = source.rootPath;
    if (root == null || root.isEmpty || root.startsWith('album:')) continue;
    final directory = Directory(root);
    if (!await directory.exists()) continue;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final mediaType = mediaTypeForExtension(extensionOf(name));
      if (mediaType == null) continue;
      try {
        final stat = await entity.stat();
        files.add(
          LocalMedia(
            id: entity.path,
            name: name,
            path: entity.path,
            mediaType: mediaType,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
            sourceLabel: source.label,
          ),
        );
      } catch (_) {
        continue;
      }
    }
  }
  files.sort((a, b) {
    final left = a.modifiedAt;
    final right = b.modifiedAt;
    if (left == null && right == null) return a.name.compareTo(b.name);
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  });
  _cachedFiles = files;
  _cachedAt = DateTime.now();
  return files;
}

Future<String?> localPath(LocalMedia media) async {
  if (!ScanService.isAlbumBased) return media.path;
  return ScanService.localFilePath(externalKey: media.id, path: media.path);
}

Future<({double lat, double lon})?> location(LocalMedia media) async {
  final asset = media.asset;
  if (asset == null) return null;
  try {
    final position = await asset.latlngAsync();
    final lat = position?.latitude;
    final lon = position?.longitude;
    if (lat == null || lon == null || (lat == 0.0 && lon == 0.0)) return null;
    return (lat: lat, lon: lon);
  } catch (_) {
    return null;
  }
}

Future<List<String>> deleteAll(List<LocalMedia> media) async {
  if (media.isEmpty) return const [];
  if (!ScanService.isAlbumBased) {
    final deleted = <String>[];
    for (final item in media) {
      final path = item.path;
      if (path == null || path.isEmpty) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
        deleted.add(item.id);
      } catch (_) {
        continue;
      }
    }
    invalidateCache();
    return deleted;
  }
  final entities = [
    for (final item in media)
      if (item.asset != null) item.asset!,
  ];
  final sdk = androidSdkVersion();
  final trashed = <String>[];
  if (entities.isNotEmpty && (sdk == null || sdk >= 30)) {
    // Android 11+ has the system trash (recoverable); older versions do not.
    try {
      trashed.addAll(await PhotoManager.editor.moveToTrash(entities));
    } catch (_) {
      if (sdk != null) rethrow;
      // Unknown SDK: fall through to the permanent delete below.
    }
  }
  final remaining = [
    for (final item in media)
      if (!trashed.contains(item.id)) item.id,
  ];
  final deleted = [...trashed];
  if (remaining.isNotEmpty && (sdk == null || sdk < 30)) {
    deleted.addAll(await PhotoManager.editor.deleteWithIds(remaining));
  }
  invalidateCache();
  return deleted;
}

/// Android API level parsed from `Platform.operatingSystemVersion`
/// (for example `Android 13 (SDK 33)`); `null` when it cannot be read.
int? androidSdkVersion() {
  if (!Platform.isAndroid) return null;
  final match = RegExp(r'SDK (\d+)')
      .firstMatch(Platform.operatingSystemVersion);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

void invalidateCache() {
  _cachedAssets = null;
  _cachedAssetsAt = null;
  _cachedFiles = null;
  _cachedAt = null;
}
