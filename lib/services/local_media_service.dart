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

  /// Verifies (and asks for) the media permission from the foreground: the
  /// background runs cannot show the system prompt.
  static Future<bool> ensurePhotoPermission() => impl.ensurePhotoPermission();

  /// Loads the whole device library once, newest first and without
  /// duplicates (the platform paging is not stable without an explicit order).
  static Future<LocalMediaPage> loadAll({required ApiClient client}) {
    return impl.loadAll(client: client);
  }

  /// One page of a single device folder (or of a local folder on desktop).
  static Future<LocalMediaPage> loadFolderPage({
    required ApiClient client,
    String? albumId,
    String? rootPath,
    required int page,
    int size = 120,
  }) {
    return impl.loadFolderPage(
      client: client,
      albumId: albumId,
      rootPath: rootPath,
      page: page,
      size: size,
    );
  }

  /// The newest device files, used by the collections preview.
  static Future<List<LocalMedia>> recent({int limit = 6}) {
    return impl.recent(limit: limit);
  }

  static Future<String?> localPath(LocalMedia media) => impl.localPath(media);

  /// GPS coordinates of a device file, read lazily (used by the viewer).
  static Future<({double lat, double lon})?> location(LocalMedia media) =>
      impl.location(media);

  static Future<List<String>> deleteAll(List<LocalMedia> media) =>
      impl.deleteAll(media);

  static void invalidateCache() => impl.invalidateCache();
}
