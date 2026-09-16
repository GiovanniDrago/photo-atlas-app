import 'scan_models.dart';

export 'scan_models.dart'
    show ScannedMedia, ScanResult, ScanFolder, ScanPermissionException;

import 'scan_service_stub.dart'
    if (dart.library.io) 'scan_service_io.dart'
    as impl;

class ScanService {
  static bool get isSupported => impl.isSupported;

  static bool get isAlbumBased => impl.isAlbumBased;

  static Future<List<ScanFolder>> listFolders() => impl.listFolders();

  static Future<ScanResult> scanDirectory({
    required String directoryPath,
    required ScanBatchCallback onBatch,
    required ScanProgressCallback onProgress,
  }) {
    return impl.scanDirectory(
      directoryPath: directoryPath,
      onBatch: onBatch,
      onProgress: onProgress,
    );
  }

  static Future<ScanResult> scanAlbum({
    required String albumId,
    required ScanBatchCallback onBatch,
    required ScanProgressCallback onProgress,
  }) {
    return impl.scanAlbum(
      albumId: albumId,
      onBatch: onBatch,
      onProgress: onProgress,
    );
  }
}
