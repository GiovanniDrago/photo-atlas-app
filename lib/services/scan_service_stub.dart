import 'package:photo_manager/photo_manager.dart';

import 'scan_models.dart';

bool get isSupported => false;

bool get isAlbumBased => false;

Future<List<ScanFolder>> listFolders({bool ensurePermission = true}) async =>
    const [];

Future<AssetPage> folderPage({
  required String albumId,
  required int page,
  required int size,
  bool ensurePermission = true,
}) async {
  return const AssetPage(assets: [], total: 0);
}

Future<List<AssetEntity>> recentAssets({
  int limit = 6,
  bool ensurePermission = true,
}) async => const [];

Future<ScanResult> scanDirectory({
  required String directoryPath,
  required ScanBatchCallback onBatch,
  required ScanProgressCallback onProgress,
}) async {
  throw UnsupportedError(
    'Local folder scanning is not available on the web. Use kDrive or the Android/Linux app.',
  );
}

Future<ScanResult> scanAlbum({
  required String albumId,
  required ScanBatchCallback onBatch,
  required ScanProgressCallback onProgress,
  bool ensurePermission = true,
}) async {
  throw UnsupportedError(
    'Local folder scanning is not available on the web. Use kDrive or the Android/Linux app.',
  );
}

Future<List<AssetEntity>> listAllAssetsOnce({
  bool ensurePermission = true,
}) async => const [];

Future<String?> findAlbumIdByName(
  String name, {
  bool ensurePermission = true,
}) async => null;

Future<ScannedMedia?> buildScannedMedia(AssetEntity asset) async => null;

Future<String?> localFilePath({
  required String externalKey,
  String? path,
}) async {
  return null;
}

Future<void> openSettings() async {}
