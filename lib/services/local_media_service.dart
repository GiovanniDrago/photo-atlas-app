import '../models/gallery_entry.dart';
import 'api_client.dart';
import 'local_media_service_stub.dart'
    if (dart.library.io) 'local_media_service_io.dart'
    as impl;

class LocalMediaPage {
  final List<LocalMedia> items;
  final int total;
  final bool hasMore;

  const LocalMediaPage({
    required this.items,
    required this.total,
    required this.hasMore,
  });
}

/// Device files shown next to the indexed ones: the whole Android media
/// library, or the local folders configured on desktop.
class LocalMediaService {
  static bool get isSupported => impl.isSupported;

  /// Loads the whole device library once, newest first and without
  /// duplicates (the platform paging is not stable without an explicit order).
  static Future<LocalMediaPage> loadAll({required ApiClient client}) {
    return impl.loadAll(client: client);
  }

  static Future<String?> localPath(LocalMedia media) => impl.localPath(media);

  /// GPS coordinates of a device file, read lazily (used by the viewer).
  static Future<({double lat, double lon})?> location(LocalMedia media) =>
      impl.location(media);

  static Future<List<String>> deleteAll(List<LocalMedia> media) =>
      impl.deleteAll(media);

  static void invalidateCache() => impl.invalidateCache();
}
