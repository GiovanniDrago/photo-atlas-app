import '../models/gallery_entry.dart';
import 'api_client.dart';
import 'local_media_service.dart';

bool get isSupported => false;

Future<LocalMediaPage> page({
  required ApiClient client,
  required int page,
  int size = 60,
}) async {
  return const LocalMediaPage(items: [], total: 0, hasMore: false);
}

Future<String?> localPath(LocalMedia media) async => media.path;

Future<List<String>> deleteAll(List<LocalMedia> media) async => const [];

void invalidateCache() {}
