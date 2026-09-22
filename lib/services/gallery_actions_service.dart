import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

import '../models/gallery_entry.dart';
import '../models/source.dart';
import 'api_client.dart';
import 'device_service.dart';
import 'download_service.dart';
import 'local_media_service.dart';
import 'scan_models.dart';
import 'scan_service.dart';

class GalleryActionProgress {
  final int done;
  final int total;
  final String? currentName;

  const GalleryActionProgress({
    this.done = 0,
    this.total = 0,
    this.currentName,
  });
}

class GalleryActionResult {
  final int uploaded;
  final int failed;
  final int localDeleted;
  final int cloudDeleted;
  final int indexDeleted;
  final int reset;
  final int shared;
  final List<String> errors;

  const GalleryActionResult({
    this.uploaded = 0,
    this.failed = 0,
    this.localDeleted = 0,
    this.cloudDeleted = 0,
    this.indexDeleted = 0,
    this.reset = 0,
    this.shared = 0,
    this.errors = const [],
  });

  bool get hasErrors => errors.isNotEmpty;

  GalleryActionResult merge(GalleryActionResult other) {
    return GalleryActionResult(
      uploaded: uploaded + other.uploaded,
      failed: failed + other.failed,
      localDeleted: localDeleted + other.localDeleted,
      cloudDeleted: cloudDeleted + other.cloudDeleted,
      indexDeleted: indexDeleted + other.indexDeleted,
      reset: reset + other.reset,
      shared: shared + other.shared,
      errors: [...errors, ...other.errors],
    );
  }
}

/// Upload, delete and share actions for the selected gallery entries.
class GalleryActionsService {
  GalleryActionsService(this.client);

  final ApiClient client;

  Future<GalleryActionResult> upload(
    List<GalleryEntry> entries, {
    void Function(GalleryActionProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final targets = entries
        .where((entry) => entry.hasLocal && !entry.isUploaded)
        .toList();
    var uploaded = 0;
    var failed = 0;
    final errors = <String>[];
    for (var index = 0; index < targets.length; index += 1) {
      if (isCancelled?.call() ?? false) break;
      final entry = targets[index];
      onProgress?.call(
        GalleryActionProgress(
          done: index,
          total: targets.length,
          currentName: entry.name,
        ),
      );
      try {
        final local = entry.local!;
        final path = await LocalMediaService.localPath(local);
        if (path == null || path.isEmpty) {
          throw ApiException(400, 'local file not found');
        }
        final mediaId = entry.cloud?.id ?? await _indexLocal(entry);
        await client.uploadMedia(mediaId: mediaId, filePath: path);
        uploaded += 1;
      } catch (error) {
        failed += 1;
        errors.add('${entry.name}: $error');
      }
    }
    onProgress?.call(
      GalleryActionProgress(done: targets.length, total: targets.length),
    );
    return GalleryActionResult(
      uploaded: uploaded,
      failed: failed,
      errors: errors,
    );
  }

  /// [cloud] moves the kDrive copies to the trash, [local] removes the device
  /// files. Stale index rows are dropped on the way.
  Future<GalleryActionResult> delete(
    List<GalleryEntry> entries, {
    required bool cloud,
    required bool local,
    void Function(GalleryActionProgress progress)? onProgress,
  }) async {
    var localDeleted = 0;
    var failed = 0;
    final errors = <String>[];
    final total = entries.length;

    final localTargets = local
        ? entries.where((entry) => entry.hasLocal).toList()
        : const <GalleryEntry>[];
    var deletedLocalIds = <String>{};
    if (localTargets.isNotEmpty) {
      onProgress?.call(GalleryActionProgress(done: 0, total: total));
      try {
        final ids = await LocalMediaService.deleteAll([
          for (final entry in localTargets) entry.local!,
        ]);
        deletedLocalIds = ids.toSet();
        localDeleted = ids.length;
        final missing = localTargets.where(
          (entry) => !deletedLocalIds.contains(entry.local!.id),
        );
        if (missing.isNotEmpty) {
          failed += missing.length;
          for (final entry in missing) {
            errors.add('${entry.name}: local delete failed');
          }
        }
      } catch (error) {
        failed += localTargets.length;
        errors.add('$error');
      }
    }

    final resetIds = <String>[];
    final dropIds = <String>[];
    final indexOnlyIds = <String>[];
    for (final entry in entries) {
      final item = entry.cloud;
      if (item == null) continue;
      final localGone =
          local && entry.hasLocal && deletedLocalIds.contains(entry.local!.id);
      if (cloud && entry.canDeleteCloud) {
        if (localGone || !entry.hasLocal) {
          dropIds.add(item.id);
        } else {
          resetIds.add(item.id);
        }
      } else if (localGone && !entry.isUploaded) {
        indexOnlyIds.add(item.id);
      }
    }

    onProgress?.call(GalleryActionProgress(done: 0, total: total));
    var result = GalleryActionResult(
      localDeleted: localDeleted,
      failed: failed,
      errors: errors,
    );
    result = result.merge(
      await _deleteBatch(resetIds, cloud: true, index: false),
    );
    result = result.merge(
      await _deleteBatch(dropIds, cloud: true, index: true),
    );
    result = result.merge(
      await _deleteBatch(indexOnlyIds, cloud: false, index: true),
    );
    return result;
  }

  Future<GalleryActionResult> _deleteBatch(
    List<String> ids, {
    required bool cloud,
    required bool index,
  }) async {
    if (ids.isEmpty) return const GalleryActionResult();
    try {
      final result = await client.deleteMedia(
        ids: ids,
        cloud: cloud,
        index: index,
      );
      return GalleryActionResult(
        cloudDeleted: result.cloudDeleted,
        indexDeleted: result.deleted,
        reset: result.reset,
        failed: result.failed.length,
        errors: [
          for (final failure in result.failed)
            '${failure.id}: ${failure.error}',
        ],
      );
    } catch (error) {
      return GalleryActionResult(failed: ids.length, errors: ['$error']);
    }
  }

  /// Shares the files of [entries], downloading cloud-only items first.
  Future<GalleryActionResult> share(
    List<GalleryEntry> entries, {
    Rect? sharePositionOrigin,
  }) async {
    final files = <XFile>[];
    final errors = <String>[];
    for (final entry in entries) {
      try {
        final local = entry.local;
        String? path;
        if (local != null) {
          final resolved = await LocalMediaService.localPath(local);
          if (resolved != null && resolved.isNotEmpty) {
            path = await prepareShareFile(path: resolved, filename: entry.name);
          }
        }
        if (path == null) {
          final url = entry.cloud?.downloadUrl;
          if (url == null || url.isEmpty) {
            throw ApiException(404, 'no file to share');
          }
          path = await downloadShareFile(url: url, filename: entry.name);
        }
        files.add(XFile(path, name: entry.name));
      } catch (error) {
        errors.add('${entry.name}: $error');
      }
    }
    if (files.isEmpty) {
      return GalleryActionResult(errors: errors);
    }
    try {
      await SharePlus.instance.share(
        ShareParams(files: files, sharePositionOrigin: sharePositionOrigin),
      );
    } catch (error) {
      return GalleryActionResult(shared: 0, errors: [...errors, '$error']);
    }
    return GalleryActionResult(shared: files.length, errors: errors);
  }

  Future<String> _indexLocal(GalleryEntry entry) async {
    final local = entry.local!;
    final deviceId = await DeviceService.ensureRegistered(client);
    final sources = await client.sources();
    final source = await _ensureSource(sources, local, deviceId);
    final media = await _scannedMedia(local);
    final batch = await client.batchMedia(
      sourceId: source.id,
      items: [media.toJson()],
    );
    final item = batch.items.isEmpty ? null : batch.items.first;
    if (item == null) {
      throw ApiException(500, 'indexing failed');
    }
    return item.id;
  }

  Future<ScannedMedia> _scannedMedia(LocalMedia local) async {
    final asset = local.asset;
    if (asset != null) {
      final scanned = await ScanService.buildScannedMedia(asset);
      if (scanned != null) return scanned;
    }
    final extension = extensionOf(local.name);
    return ScannedMedia(
      externalKey: local.id,
      path: local.path ?? '',
      name: local.name,
      mime:
          mimeByExtension[extension] ??
          (local.isVideo ? 'video/mp4' : 'image/jpeg'),
      mediaType: local.mediaType,
      sizeBytes: local.sizeBytes ?? 0,
      takenAt: local.takenAt,
      modifiedAt: local.modifiedAt,
      width: local.width,
      height: local.height,
      durationS: local.durationS,
    );
  }

  Future<MediaSource> _ensureSource(
    List<MediaSource> sources,
    LocalMedia local,
    String deviceId,
  ) async {
    final asset = local.asset;
    if (asset != null) {
      final folder = _albumName(asset);
      for (final source in sources) {
        if (source.kind != 'local') continue;
        if (source.label == folder || source.albumKey == 'path:$folder') {
          return source;
        }
      }
      final sourceId = await client.createSource(
        kind: 'local',
        label: folder,
        rootPath: 'album:path:$folder',
        deviceId: deviceId,
        albumKey: 'path:$folder',
      );
      return MediaSource(
        id: sourceId,
        kind: 'local',
        label: folder,
        itemCount: 0,
        rootPath: 'album:path:$folder',
      );
    }

    final path = local.path ?? local.id;
    for (final source in sources) {
      final root = source.rootPath;
      if (source.kind != 'local' || root == null || root.isEmpty) continue;
      if (path == root || path.startsWith('$root/')) return source;
    }
    final directory = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/'))
        : path;
    final segments = directory
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    final name = segments.isEmpty ? 'Local' : segments.last;
    final label = 'Local: $name';
    final sourceId = await client.createSource(
      kind: 'local',
      label: label,
      rootPath: directory,
      deviceId: deviceId,
    );
    return MediaSource(
      id: sourceId,
      kind: 'local',
      label: label,
      itemCount: 0,
      rootPath: directory,
    );
  }

  static String _albumName(AssetEntity asset) {
    final relative = asset.relativePath ?? '';
    final segments = relative
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    return segments.isEmpty ? 'Manual' : segments.last;
  }
}
