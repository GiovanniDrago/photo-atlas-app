import 'package:photo_manager/photo_manager.dart';

import '../models/backup.dart';
import '../models/source.dart';
import 'api_client.dart';
import 'device_service.dart';
import 'scan_service.dart';

class BackupProgress {
  final String? currentName;
  final int uploaded;
  final int failed;
  final int verifiedOk;
  final int verifiedMissing;
  final int bytes;
  final int total;

  const BackupProgress({
    this.currentName,
    this.uploaded = 0,
    this.failed = 0,
    this.verifiedOk = 0,
    this.verifiedMissing = 0,
    this.bytes = 0,
    this.total = 0,
  });

  BackupProgress copyWith({
    String? currentName,
    int? uploaded,
    int? failed,
    int? verifiedOk,
    int? verifiedMissing,
    int? bytes,
    int? total,
  }) {
    return BackupProgress(
      currentName: currentName ?? this.currentName,
      uploaded: uploaded ?? this.uploaded,
      failed: failed ?? this.failed,
      verifiedOk: verifiedOk ?? this.verifiedOk,
      verifiedMissing: verifiedMissing ?? this.verifiedMissing,
      bytes: bytes ?? this.bytes,
      total: total ?? this.total,
    );
  }
}

class BackupService {
  final ApiClient client;

  BackupService(this.client);

  Future<void> runBackup({
    String? sourceId,
    required void Function(BackupProgress progress) onProgress,
    bool Function()? isCancelled,
  }) async {
    final deviceId = await DeviceService.ensureRegistered(client);
    final runId = await client.createBackupRun(
      kind: 'backup',
      sourceId: sourceId,
      deviceId: deviceId,
    );
    var uploaded = 0;
    var failed = 0;
    var bytes = 0;
    final errors = <String>[];
    var cancelled = false;
    try {
      while (true) {
        if (isCancelled?.call() ?? false) {
          cancelled = true;
          break;
        }
        final pending = await client.backupPending(
          sourceId: sourceId,
          limit: 20,
        );
        if (pending.isEmpty) break;
        for (final item in pending) {
          if (isCancelled?.call() ?? false) {
            cancelled = true;
            break;
          }
          onProgress(
            BackupProgress(
              currentName: item.name,
              uploaded: uploaded,
              failed: failed,
              bytes: bytes,
              total: uploaded + failed + pending.length,
            ),
          );
          try {
            final path = await ScanService.localFilePath(
              externalKey: item.externalKey,
              path: item.path,
            );
            if (path == null || path.isEmpty) {
              throw ApiException(400, 'local file not found');
            }
            await client.uploadMedia(mediaId: item.id, filePath: path);
            uploaded += 1;
            bytes += item.sizeBytes;
          } catch (error) {
            failed += 1;
            errors.add('${item.name}: $error');
          }
        }
        if (cancelled) break;
      }
    } finally {
      await client.patchBackupRun(
        runId,
        status: cancelled ? 'cancelled' : 'completed',
        filesUploaded: uploaded,
        filesFailed: failed,
        bytesUploaded: bytes,
        errors: errors.take(20).toList(),
      );
      onProgress(
        BackupProgress(
          uploaded: uploaded,
          failed: failed,
          bytes: bytes,
          total: uploaded + failed,
        ),
      );
    }
  }

  Future<void> runVerify({
    String? sourceId,
    required void Function(BackupProgress progress) onProgress,
    bool Function()? isCancelled,
  }) async {
    final deviceId = await DeviceService.ensureRegistered(client);
    final runId = await client.createBackupRun(
      kind: 'verify',
      sourceId: sourceId,
      deviceId: deviceId,
    );
    var verifiedOk = 0;
    var verifiedMissing = 0;
    final errors = <String>[];
    var cancelled = false;
    try {
      while (true) {
        if (isCancelled?.call() ?? false) {
          cancelled = true;
          break;
        }
        final queue = await client.verifyQueue(sourceId: sourceId, limit: 20);
        if (queue.isEmpty) break;
        for (final item in queue) {
          if (isCancelled?.call() ?? false) {
            cancelled = true;
            break;
          }
          onProgress(
            BackupProgress(
              currentName: item.name,
              verifiedOk: verifiedOk,
              verifiedMissing: verifiedMissing,
              total: verifiedOk + verifiedMissing + queue.length,
            ),
          );
          try {
            final result = await client.verifyMedia(item.id);
            if (result.ok) {
              verifiedOk += 1;
            } else {
              verifiedMissing += 1;
            }
          } catch (error) {
            verifiedMissing += 1;
            errors.add('${item.name}: $error');
          }
        }
        if (cancelled) break;
      }
    } finally {
      await client.patchBackupRun(
        runId,
        status: cancelled ? 'cancelled' : 'completed',
        verifiedOk: verifiedOk,
        verifiedMissing: verifiedMissing,
        errors: errors.take(20).toList(),
      );
      onProgress(
        BackupProgress(
          verifiedOk: verifiedOk,
          verifiedMissing: verifiedMissing,
          total: verifiedOk + verifiedMissing,
        ),
      );
    }
  }

  Future<void> uploadPickedAssets({
    required List<AssetEntity> assets,
    required void Function(BackupProgress progress) onProgress,
    bool Function()? isCancelled,
  }) async {
    if (assets.isEmpty) return;
    final deviceId = await DeviceService.ensureRegistered(client);
    final sources = await client.sources();
    final sourceByLabel = <String, MediaSource>{};
    for (final source in sources) {
      if (source.kind == 'local') sourceByLabel[source.label] = source;
    }

    var uploaded = 0;
    var failed = 0;
    var bytes = 0;
    final errors = <String>[];

    for (var index = 0; index < assets.length; index += 1) {
      if (isCancelled?.call() ?? false) break;
      final asset = assets[index];
      final media = await ScanService.buildScannedMedia(asset);
      if (media == null) {
        failed += 1;
        errors.add('${asset.title ?? asset.id}: unsupported asset');
        continue;
      }
      onProgress(
        BackupProgress(
          currentName: media.name,
          uploaded: uploaded,
          failed: failed,
          bytes: bytes,
          total: assets.length,
        ),
      );
      try {
        final folder = _folderName(asset);
        var source = sourceByLabel[folder];
        if (source == null) {
          final sourceId = await client.createSource(
            kind: 'local',
            label: folder,
            rootPath: 'album:path:$folder',
            deviceId: deviceId,
            albumKey: 'path:$folder',
          );
          source = MediaSource(
            id: sourceId,
            kind: 'local',
            label: folder,
            itemCount: 0,
            rootPath: 'album:path:$folder',
          );
          sourceByLabel[folder] = source;
        }
        final batch = await client.batchMedia(
          sourceId: source.id,
          items: [media.toJson()],
        );
        final batchItem = batch.items.isEmpty ? null : batch.items.first;
        if (batchItem == null) {
          throw ApiException(500, 'indexing failed');
        }
        final path = await ScanService.localFilePath(
          externalKey: media.externalKey,
          path: media.path,
        );
        if (path == null || path.isEmpty) {
          throw ApiException(400, 'local file not found');
        }
        await client.uploadMedia(
          mediaId: batchItem.id,
          filePath: path,
          destination: 'manual',
        );
        uploaded += 1;
        bytes += media.sizeBytes;
      } catch (error) {
        failed += 1;
        errors.add('${media.name}: $error');
      }
    }
    onProgress(
      BackupProgress(
        uploaded: uploaded,
        failed: failed,
        bytes: bytes,
        total: assets.length,
      ),
    );
  }

  static String _folderName(AssetEntity asset) {
    final relative = asset.relativePath ?? '';
    final segments = relative
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    if (segments.isEmpty) return 'Manual';
    return segments.last;
  }
}
