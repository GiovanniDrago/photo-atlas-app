import '../models/gallery_entry.dart';
import 'api_client.dart';
import 'gallery_actions_service.dart';

class AlbumSelectionResult {
  final List<String> mediaIds;
  final int failed;
  final List<String> errors;

  const AlbumSelectionResult({
    this.mediaIds = const [],
    this.failed = 0,
    this.errors = const [],
  });
}

class AlbumAddResult {
  final int added;
  final int failed;
  final List<String> errors;

  const AlbumAddResult({
    this.added = 0,
    this.failed = 0,
    this.errors = const [],
  });
}

/// Album membership actions: indexing device-only entries first (metadata and
/// thumbnail, no kDrive upload) so they have a media id to relate.
class AlbumActionsService {
  AlbumActionsService(this.client, [GalleryActionsService? galleryActions])
    : galleryActions = galleryActions ?? GalleryActionsService(client);

  final ApiClient client;
  final GalleryActionsService galleryActions;

  /// Resolves the selected entries to media ids, indexing the device-only ones.
  Future<AlbumSelectionResult> resolveMediaIds(
    List<GalleryEntry> entries,
  ) async {
    final ids = <String>[];
    final errors = <String>[];
    var failed = 0;
    for (final entry in entries) {
      final cloud = entry.cloud;
      if (cloud != null) {
        ids.add(cloud.id);
        continue;
      }
      try {
        ids.add(await galleryActions.indexLocal(entry));
      } catch (error) {
        failed += 1;
        errors.add('${entry.name}: $error');
      }
    }
    return AlbumSelectionResult(mediaIds: ids, failed: failed, errors: errors);
  }

  Future<AlbumAddResult> addEntries({
    required String albumId,
    required List<GalleryEntry> entries,
  }) async {
    final resolved = await resolveMediaIds(entries);
    if (resolved.mediaIds.isEmpty) {
      return AlbumAddResult(failed: resolved.failed, errors: resolved.errors);
    }
    try {
      final added = await client.addAlbumItems(
        albumId: albumId,
        mediaIds: resolved.mediaIds,
      );
      return AlbumAddResult(
        added: added,
        failed: resolved.failed + (resolved.mediaIds.length - added),
        errors: resolved.errors,
      );
    } catch (error) {
      return AlbumAddResult(
        failed: resolved.failed + resolved.mediaIds.length,
        errors: [...resolved.errors, '$error'],
      );
    }
  }
}
