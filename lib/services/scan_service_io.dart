import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import 'exif_service.dart';
import 'scan_models.dart';

bool get isSupported => true;

bool get isAlbumBased => Platform.isAndroid;

const _permissionRequest = PermissionRequestOption(
  androidPermission: AndroidPermission(
    type: RequestType.common,
    mediaLocation: true,
  ),
);

/// Requests the media permission, unless the caller knows it is not possible
/// (background runs have no Activity and the request would crash the plugin).
Future<void> _ensurePermission({bool request = true}) async {
  if (!request) return;
  final permission = await PhotoManager.requestPermissionExtend(
    requestOption: _permissionRequest,
  );
  if (!permission.isAuth && !permission.hasAccess) {
    throw const ScanPermissionException();
  }
}

const _thumbnailSize = ThumbnailSize.square(320);
const _thumbnailQuality = 75;
const _maxThumbnailBytes = 200 * 1024;

Future<List<ScanFolder>> listFolders({bool ensurePermission = true}) async {
  if (!Platform.isAndroid) return const [];
  await _ensurePermission(request: ensurePermission);
  final paths = await PhotoManager.getAssetPathList(
    type: RequestType.common,
    onlyAll: false,
    filterOption: _galleryFilterOption(),
  );
  final folders = <ScanFolder>[];
  for (final path in paths) {
    // The "Recent" pseudo album is not a folder.
    if (path.isAll) continue;
    int count;
    try {
      count = await path.assetCountAsync;
    } catch (_) {
      continue;
    }
    if (count == 0) continue;
    var relative = path.name;
    try {
      final assets = await path.getAssetListRange(start: 0, end: 1);
      final first = assets.isEmpty ? null : assets.first;
      final value = first?.relativePath;
      if (value != null && value.trim().isNotEmpty) relative = value;
    } catch (_) {
      relative = path.name;
    }
    folders.add(
      ScanFolder(id: path.id, name: path.name, path: relative, count: count),
    );
  }
  folders.sort((a, b) => b.count.compareTo(a.count));
  return folders;
}

/// One page of a device folder, ordered newest first.
Future<AssetPage> folderPage({
  required String albumId,
  required int page,
  required int size,
  bool ensurePermission = true,
}) async {
  if (!Platform.isAndroid) return const AssetPage(assets: [], total: 0);
  await _ensurePermission(request: ensurePermission);
  final paths = await PhotoManager.getAssetPathList(
    type: RequestType.common,
    onlyAll: false,
    filterOption: _galleryFilterOption(),
  );
  AssetPathEntity? album;
  for (final path in paths) {
    if (path.id == albumId) {
      album = path;
      break;
    }
  }
  if (album == null) return const AssetPage(assets: [], total: 0);
  final total = await album.assetCountAsync;
  final start = page * size;
  if (start >= total) return AssetPage(assets: const [], total: total);
  final end = start + size > total ? total : start + size;
  final assets = await album.getAssetListRange(start: start, end: end);
  return AssetPage(assets: assets, total: total);
}

/// The newest assets of the whole library (used by the collections preview).
Future<List<AssetEntity>> recentAssets({
  int limit = 6,
  bool ensurePermission = true,
}) async {
  if (!Platform.isAndroid) return const [];
  await _ensurePermission(request: ensurePermission);
  final paths = await PhotoManager.getAssetPathList(
    type: RequestType.common,
    onlyAll: true,
    filterOption: _galleryFilterOption(),
  );
  if (paths.isEmpty) return const [];
  return paths.first.getAssetListRange(start: 0, end: limit);
}

Future<String?> findAlbumIdByName(
  String name, {
  bool ensurePermission = true,
}) async {
  if (!Platform.isAndroid) return null;
  await _ensurePermission(request: ensurePermission);
  final paths = await PhotoManager.getAssetPathList(
    type: RequestType.common,
    onlyAll: false,
  );
  for (final path in paths) {
    if (path.name == name) return path.id;
  }
  return null;
}

Future<ScanResult> scanAlbum({
  required String albumId,
  required ScanBatchCallback onBatch,
  required ScanProgressCallback onProgress,
  bool ensurePermission = true,
}) async {
  await _ensurePermission(request: ensurePermission);
  final paths = await PhotoManager.getAssetPathList(
    type: RequestType.common,
    onlyAll: false,
  );
  AssetPathEntity? album;
  for (final path in paths) {
    if (path.id == albumId) {
      album = path;
      break;
    }
  }
  if (album == null) {
    throw ArgumentError('Album not found: $albumId');
  }

  final total = await album.assetCountAsync;
  var seen = 0;
  var indexed = 0;
  var skippedPages = 0;
  final batch = <ScannedMedia>[];
  const pageSize = 200;

  for (var start = 0; start < total; start += pageSize) {
    final end = (start + pageSize > total) ? total : start + pageSize;
    List<AssetEntity> assets;
    try {
      assets = await album.getAssetListRange(start: start, end: end);
    } catch (_) {
      // A page that cannot be read (broken MediaStore row) must not stop the
      // whole folder: skip it and keep going.
      skippedPages += 1;
      continue;
    }
    for (final asset in assets) {
      if (asset.type == AssetType.audio || asset.type == AssetType.other) {
        continue;
      }
      seen++;
      try {
        final file = await asset.file;
        final size = await file?.length() ?? 0;
        final (lat, lon) = await _readLocation(asset);
        final mediaType = asset.type == AssetType.video ? 'video' : 'image';
        final title = asset.title ?? 'asset-${asset.id}';
        batch.add(
          ScannedMedia(
            externalKey: asset.id,
            path: file?.path ?? '',
            name: title,
            mime:
                asset.mimeType ??
                (mediaType == 'video' ? 'video/mp4' : 'image/jpeg'),
            mediaType: mediaType,
            sizeBytes: size,
            takenAt: asset.createDateTime,
            modifiedAt: asset.modifiedDateTime,
            lat: lat,
            lon: lon,
            width: asset.width,
            height: asset.height,
            durationS: mediaType == 'video' ? asset.duration.toDouble() : null,
            thumbnailB64: await _readThumbnail(asset),
          ),
        );
        indexed++;
      } catch (_) {
        continue;
      }
      if (batch.length >= 100) {
        await onBatch(List.of(batch));
        batch.clear();
      }
      if (seen % 25 == 0) onProgress(seen, indexed);
    }
  }

  if (batch.isNotEmpty) {
    await onBatch(batch);
  }
  onProgress(seen, indexed);
  return ScanResult(
    filesSeen: seen,
    indexed: indexed,
    skippedPages: skippedPages,
  );
}

Future<ScanResult> scanDirectory({
  required String directoryPath,
  required ScanBatchCallback onBatch,
  required ScanProgressCallback onProgress,
}) async {
  final directory = Directory(directoryPath);
  if (!await directory.exists()) {
    throw ArgumentError('Directory not found: $directoryPath');
  }

  var seen = 0;
  var indexed = 0;
  final batch = <ScannedMedia>[];

  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    final extension = extensionOf(name);
    final mediaType = mediaTypeForExtension(extension);
    if (mediaType == null) continue;

    seen++;
    try {
      final stat = await entity.stat();
      ExtractedMetadata? metadata;
      if (mediaType == 'image' && stat.size > 0) {
        final bytes = await _readPrefix(entity, 262144);
        if (bytes.isNotEmpty) {
          final map = await Isolate.run(() => parseExifBytes(bytes));
          metadata = ExtractedMetadata.fromMap(map);
        }
      }
      batch.add(
        ScannedMedia(
          externalKey: entity.path,
          path: entity.path,
          name: name,
          mime:
              mimeByExtension[extension] ??
              (mediaType == 'image' ? 'image/jpeg' : 'video/mp4'),
          mediaType: mediaType,
          sizeBytes: stat.size,
          takenAt: metadata?.takenAt,
          modifiedAt: stat.modified,
          lat: metadata?.lat,
          lon: metadata?.lon,
          width: metadata?.width,
          height: metadata?.height,
        ),
      );
      indexed++;
    } catch (_) {
      continue;
    }

    if (batch.length >= 100) {
      await onBatch(List.of(batch));
      batch.clear();
    }
    if (seen % 25 == 0) {
      onProgress(seen, indexed);
    }
  }

  if (batch.isNotEmpty) {
    await onBatch(batch);
  }
  onProgress(seen, indexed);
  return ScanResult(filesSeen: seen, indexed: indexed);
}

/// Explicit ordering: without it MediaStore returns rows in an arbitrary,
/// unstable order, which breaks paging (duplicates and skipped items).
FilterOptionGroup _galleryFilterOption() {
  return FilterOptionGroup(
    orders: [
      OrderOption(type: OrderOptionType.createDate, asc: false),
      OrderOption(type: OrderOptionType.updateDate, asc: false),
    ],
  );
}

/// The whole device media library in a single query, newest first.
Future<List<AssetEntity>> listAllAssetsOnce({
  bool ensurePermission = true,
}) async {
  if (!Platform.isAndroid) return const [];
  await _ensurePermission(request: ensurePermission);
  final paths = await PhotoManager.getAssetPathList(
    type: RequestType.common,
    onlyAll: true,
    filterOption: _galleryFilterOption(),
  );
  if (paths.isEmpty) return const [];
  final all = paths.first;
  final total = await all.assetCountAsync;
  if (total <= 0) return const [];
  return all.getAssetListRange(start: 0, end: total);
}

Future<ScannedMedia?> buildScannedMedia(AssetEntity asset) async {
  if (asset.type == AssetType.audio || asset.type == AssetType.other) {
    return null;
  }
  try {
    final file = await asset.file;
    final size = await file?.length() ?? 0;
    final (lat, lon) = await _readLocation(asset);
    final mediaType = asset.type == AssetType.video ? 'video' : 'image';
    final title = asset.title ?? 'asset-${asset.id}';
    return ScannedMedia(
      externalKey: asset.id,
      path: file?.path ?? '',
      name: title,
      mime:
          asset.mimeType ?? (mediaType == 'video' ? 'video/mp4' : 'image/jpeg'),
      mediaType: mediaType,
      sizeBytes: size,
      takenAt: asset.createDateTime,
      modifiedAt: asset.modifiedDateTime,
      lat: lat,
      lon: lon,
      width: asset.width,
      height: asset.height,
      durationS: mediaType == 'video' ? asset.duration.toDouble() : null,
      thumbnailB64: await _readThumbnail(asset),
    );
  } catch (_) {
    return null;
  }
}

Future<void> openSettings() => PhotoManager.openSetting();

Future<String?> localFilePath({
  required String externalKey,
  String? path,
}) async {
  if (!Platform.isAndroid) return path;
  AssetEntity? asset;
  try {
    asset = await AssetEntity.fromId(externalKey);
  } catch (_) {
    asset = null;
  }
  if (asset == null) return path;
  final current = asset;
  final candidates = [
    await _safeFile(() => current.loadFile(isOrigin: true)),
    await _safeFile(() => current.originFile),
    await _safeFile(() => current.file),
  ];
  for (final candidate in candidates) {
    if (candidate == null) continue;
    try {
      if (candidate.existsSync() && candidate.lengthSync() > 0) {
        return candidate.path;
      }
    } catch (_) {
      continue;
    }
  }
  return path;
}

Future<File?> _safeFile(Future<File?> Function() loader) async {
  try {
    return await loader();
  } catch (_) {
    return null;
  }
}

Future<Uint8List> _readPrefix(File file, int byteCount) async {
  final handle = await file.open();
  try {
    return await handle.read(byteCount);
  } finally {
    await handle.close();
  }
}

Future<(double?, double?)> _readLocation(AssetEntity asset) async {
  try {
    final location = await asset.latlngAsync();
    final lat = location?.latitude;
    final lon = location?.longitude;
    if (lat == null || lon == null || (lat == 0.0 && lon == 0.0)) {
      return (null, null);
    }
    return (lat, lon);
  } catch (_) {
    return (null, null);
  }
}

Future<String?> _readThumbnail(AssetEntity asset) async {
  try {
    final bytes = await asset.thumbnailDataWithSize(
      _thumbnailSize,
      quality: _thumbnailQuality,
    );
    if (bytes == null || bytes.isEmpty || bytes.length > _maxThumbnailBytes) {
      return null;
    }
    return base64Encode(bytes);
  } catch (_) {
    return null;
  }
}
