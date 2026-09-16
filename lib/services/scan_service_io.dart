import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import 'exif_service.dart';
import 'scan_models.dart';

bool get isSupported => true;

bool get isAlbumBased => Platform.isAndroid;

Future<List<ScanFolder>> listFolders() async {
  if (!Platform.isAndroid) return const [];
  final permission = await PhotoManager.requestPermissionExtend();
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
  final permission = await PhotoManager.requestPermissionExtend();
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
        final latitude = asset.latitude;
        final longitude = asset.longitude;
        final hasGps = !(latitude == 0.0 && longitude == 0.0);
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
            lat: hasGps ? latitude : null,
            lon: hasGps ? longitude : null,
            width: asset.width,
            height: asset.height,
            durationS: mediaType == 'video' ? asset.duration.toDouble() : null,
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

Future<Uint8List> _readPrefix(File file, int byteCount) async {
  final handle = await file.open();
  try {
    return await handle.read(byteCount);
  } finally {
    await handle.close();
  }
}
