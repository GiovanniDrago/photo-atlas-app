import 'package:photo_manager/photo_manager.dart';

import 'scan_models.dart';

export 'scan_models.dart'
    show ScannedMedia, ScanResult, ScanFolder, ScanPermissionException;

export 'package:photo_manager/photo_manager.dart'
    show AssetEntity, AssetType, ThumbnailFormat, ThumbnailSize;

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

  static Future<AssetPage> listAllAssets({
    required int page,
    required int size,
  }) {
    return impl.listAllAssets(page: page, size: size);
  }

  static Future<String?> findAlbumIdByName(String name) {
    return impl.findAlbumIdByName(name);
  }

  static Future<ScannedMedia?> buildScannedMedia(AssetEntity asset) {
    return impl.buildScannedMedia(asset);
  }

  static Future<String?> localFilePath({
    required String externalKey,
    String? path,
  }) {
    return impl.localFilePath(externalKey: externalKey, path: path);
  }

  /// Opens the system settings page of the app (media permissions).
  static Future<void> openSettings() => impl.openSettings();
}
