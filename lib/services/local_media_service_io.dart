import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

import '../models/gallery_entry.dart';
import 'api_client.dart';
import 'local_media_service.dart';
import 'scan_models.dart';
import 'scan_service.dart';

bool get isSupported => true;

const _cacheTtl = Duration(minutes: 5);

List<LocalMedia>? _cachedFiles;
DateTime? _cachedAt;

Future<LocalMediaPage> page({
  required ApiClient client,
  required int page,
  int size = 60,
}) {
  if (ScanService.isAlbumBased) return _assetPage(page: page, size: size);
  return _filePage(client: client, page: page, size: size);
}

Future<LocalMediaPage> _assetPage({
  required int page,
  required int size,
}) async {
  final result = await ScanService.listAllAssets(page: page, size: size);
  final items = <LocalMedia>[];
  for (final asset in result.assets) {
    if (asset.type == AssetType.audio || asset.type == AssetType.other) {
      continue;
    }
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
  final seen = (page + 1) * size;
  return LocalMediaPage(
    items: items,
    total: result.total,
    hasMore: seen < result.total,
  );
}

Future<LocalMediaPage> _filePage({
  required ApiClient client,
  required int page,
  int size = 60,
}) async {
  final files = await _localFiles(client);
  final start = page * size;
  if (start >= files.length) {
    return LocalMediaPage(items: const [], total: files.length, hasMore: false);
  }
  final end = start + size > files.length ? files.length : start + size;
  return LocalMediaPage(
    items: files.sublist(start, end),
    total: files.length,
    hasMore: end < files.length,
  );
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
  final ids = [for (final item in media) item.id];
  final deleted = await PhotoManager.editor.deleteWithIds(ids);
  return deleted;
}

void invalidateCache() {
  _cachedFiles = null;
  _cachedAt = null;
}
