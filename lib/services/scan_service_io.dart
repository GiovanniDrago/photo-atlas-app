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

const _thumbnailSize = ThumbnailSize.square(320);
const _thumbnailQuality = 75;
const _maxThumbnailBytes = 200 * 1024;

Future<List<ScanFolder>> listFolders() async {
  if (!Platform.isAndroid) return const [];
  final permission = await PhotoManager.requestPermissionExtend(
    requestOption: _permissionRequest,
  );
  if (!permission.isAuth && !permission.hasAccess) {
    throw const ScanPermissionException();
  }
  final paths = await PhotoManager.getAssetPathList(
    type: RequestType.common,
    onlyAll: false,
  );
  final folders = <ScanFolder>[];
  for (final path in paths) {
    final count = await path.assetCountAsync;
    if (count == 0) continue;
    folders.add(ScanFolder(id: path.id, name: path.name, count: count));
  }
  folders.sort((a, b) => b.count.compareTo(a.count));
  return folders;
}

Future<ScanResult> scanAlbum({
  required String albumId,
  required ScanBatchCallback onBatch,
  required ScanProgressCallback onProgress,
}) async {
  final permission = await PhotoManager.requestPermissionExtend(
    requestOption: _permissionRequest,
  );
  if (!permission.isAuth && !permission.hasAccess) {
    throw const ScanPermissionException();
  }
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
  final batch = <ScannedMedia>[];
  const pageSize = 200;

  for (var start = 0; start < total; start += pageSize) {
    final end = (start + pageSize > total) ? total : start + pageSize;
    final assets = await album.getAssetListRange(start: start, end: end);
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
  return ScanResult(filesSeen: seen, indexed: indexed);
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

Future<AssetPage> listAllAssets({required int page, required int size}) async {
  if (!Platform.isAndroid) return const AssetPage(assets: [], total: 0);
  final permission = await PhotoManager.requestPermissionExtend(
    requestOption: _permissionRequest,
  );
  if (!permission.isAuth && !permission.hasAccess) {
    throw const ScanPermissionException();
  }
  final paths = await PhotoManager.getAssetPathList(
    type: RequestType.common,
    onlyAll: true,
  );
  if (paths.isEmpty) return const AssetPage(assets: [], total: 0);
  final all = paths.first;
  final total = await all.assetCountAsync;
  final assets = await all.getAssetListPaged(page: page, size: size);
  return AssetPage(assets: assets, total: total);
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

Future<String?> localFilePath({
  required String externalKey,
  String? path,
}) async {
  if (!Platform.isAndroid) return path;
  try {
    final asset = await AssetEntity.fromId(externalKey);
    if (asset == null) return path;
    final file = await asset.originFile ?? await asset.file;
    return file?.path ?? path;
  } catch (_) {
    return path;
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
