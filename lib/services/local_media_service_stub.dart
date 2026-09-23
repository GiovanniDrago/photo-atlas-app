import '../models/gallery_entry.dart';
import 'api_client.dart';
import 'local_media_service.dart';

bool get isSupported => false;

Future<Map<String, LocalMedia>> deviceIndex({ApiClient? client}) async =>
    const {};

Future<bool> ensurePhotoPermission() async => true;

Future<LocalMediaPage> loadAll({required ApiClient client}) async {
  return const LocalMediaPage(items: [], total: 0, hasMore: false);
}

Future<LocalMediaPage> loadFolderPage({
  required ApiClient client,
  String? albumId,
  String? rootPath,
  required int page,
  int size = 120,
}) async {
  return const LocalMediaPage(items: [], total: 0, hasMore: false);
}

Future<List<LocalMedia>> recent({int limit = 6}) async => const [];

Future<String?> localPath(LocalMedia media) async => media.path;

Future<({double lat, double lon})?> location(LocalMedia media) async => null;

Future<List<String>> deleteAll(List<LocalMedia> media) async => const [];

void invalidateCache() {}
