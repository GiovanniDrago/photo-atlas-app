import '../models/source.dart';
import 'api_client.dart';
import 'scan_service.dart';

class LocalScanService {
  final ApiClient client;

  LocalScanService(this.client);

  static const _albumPathPrefix = 'album:path:';
  static const _albumPrefix = 'album:';

  Future<String> ensureSource({
    required String label,
    required String rootPath,
    String? deviceId,
    String? albumKey,
  }) async {
    final sources = await client.sources();
    for (final source in sources) {
      if (source.kind == 'local' && source.rootPath == rootPath) {
        return source.id;
      }
    }
    return client.createSource(
      kind: 'local',
      label: label,
      rootPath: rootPath,
      deviceId: deviceId,
      albumKey: albumKey,
    );
  }

  Future<List<MediaSource>> autoBackupSources() async {
    final sources = await client.sources();
    return sources
        .where((source) => source.kind == 'local' && source.autoBackup)
        .toList();
  }

  Future<ScanResult> scanSource({
    required String sourceId,
    required String rootPath,
    void Function(int seen, int indexed)? onProgress,
  }) async {
    final scanRunId = await client.createScanRun(sourceId);
    try {
      Future<void> onBatch(List<ScannedMedia> batch) async {
        await client.batchMedia(
          sourceId: sourceId,
          scanRunId: scanRunId,
          items: batch.map((item) => item.toJson()).toList(),
        );
      }

      final progress = onProgress ?? (int seen, int indexed) {};
      final albumId = await resolveAlbumId(rootPath);
      if (rootPath.startsWith(_albumPrefix) && albumId == null) {
        await client.patchScanRun(
          scanRunId,
          status: 'completed',
          filesSeen: 0,
          filesIndexed: 0,
        );
        return const ScanResult(filesSeen: 0, indexed: 0);
      }
      final result = albumId != null
          ? await ScanService.scanAlbum(
              albumId: albumId,
              onBatch: onBatch,
              onProgress: progress,
            )
          : await ScanService.scanDirectory(
              directoryPath: rootPath,
              onBatch: onBatch,
              onProgress: progress,
            );
      await client.patchScanRun(
        scanRunId,
        status: 'completed',
        filesSeen: result.filesSeen,
        filesIndexed: result.indexed,
      );
      return result;
    } catch (error) {
      try {
        await client.patchScanRun(
          scanRunId,
          status: 'failed',
          errors: ['$error'],
        );
      } catch (_) {}
      rethrow;
    }
  }

  Future<String?> resolveAlbumId(String rootPath) async {
    if (!ScanService.isAlbumBased) return null;
    if (rootPath.startsWith(_albumPathPrefix)) {
      final folder = rootPath.substring(_albumPathPrefix.length);
      if (folder.isEmpty) return null;
      return ScanService.findAlbumIdByName(folder);
    }
    if (rootPath.startsWith(_albumPrefix)) {
      final albumId = rootPath.substring(_albumPrefix.length);
      return albumId.isEmpty ? null : albumId;
    }
    return null;
  }
}
