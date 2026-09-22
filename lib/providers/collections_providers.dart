import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/backup.dart';
import '../models/gallery_entry.dart';
import '../models/media_item.dart';
import '../services/local_media_service.dart';
import '../services/scan_models.dart';
import '../services/scan_service.dart';
import 'library_providers.dart';

/// Device folders (MediaStore buckets on Android, configured local folders on
/// desktop). Folders that only contain subfolders do not exist as buckets, so
/// they are naturally excluded.
final deviceFoldersProvider = FutureProvider<List<ScanFolder>>((ref) async {
  if (!ScanService.isSupported) return const [];
  return ScanService.listFolders();
});

/// Per source backup counters, used by the folder cards and the folder view.
final backupStatusProvider = FutureProvider<BackupStatusSnapshot>((ref) {
  return ref.watch(apiClientProvider).backupStatus();
});

/// First asset of a device folder, used as its thumbnail (cached per folder).
final folderThumbProvider = FutureProvider.family<List<AssetEntity>, String>((
  ref,
  albumId,
) async {
  final page = await ScanService.folderPage(albumId: albumId, page: 0, size: 1);
  return page.assets;
});

/// The newest items (device + cloud) shown in the collections timeline card.
final recentPreviewProvider = FutureProvider<List<GalleryEntry>>((ref) async {
  final client = ref.watch(apiClientProvider);
  var cloud = const <MediaItem>[];
  try {
    cloud = (await client.media(limit: 6)).items;
  } catch (_) {
    cloud = const [];
  }
  var local = const <LocalMedia>[];
  if (LocalMediaService.isSupported) {
    try {
      local = await LocalMediaService.recent(limit: 6);
    } catch (_) {
      local = const [];
    }
  }
  return mergeGalleryEntries(cloud: cloud, local: local).take(6).toList();
});
