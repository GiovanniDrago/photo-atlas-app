import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'exif_service.dart';
import 'scan_models.dart';

bool get isSupported => true;

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
