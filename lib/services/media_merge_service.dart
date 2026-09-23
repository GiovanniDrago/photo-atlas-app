import '../models/gallery_entry.dart';
import '../models/media_item.dart';
import 'api_client.dart';
import 'local_media_service.dart';

/// Adds the device copy (matched by name and size) to indexed items, so the
/// viewer and the actions behave the same whichever screen opened them.
/// When the device list is not cached yet the result is cloud-only and the
/// list is loaded in the background for the next call.
Future<List<GalleryEntry>> mergeCloudWithDevice(
  List<MediaItem> cloud, {
  ApiClient? client,
}) async {
  if (cloud.isEmpty) return const [];
  final index = await LocalMediaService.deviceIndex(client: client);
  return mergeCloudWithIndex(cloud, index);
}

/// Pure part of [mergeCloudWithDevice]: matches indexed items with the device
/// files by name and size.
List<GalleryEntry> mergeCloudWithIndex(
  List<MediaItem> cloud,
  Map<String, LocalMedia> index,
) {
  if (cloud.isEmpty) return const [];
  if (index.isEmpty) {
    return [for (final item in cloud) GalleryEntry(cloud: item)];
  }
  final locals = <LocalMedia>[];
  final seen = <String>{};
  for (final item in cloud) {
    if (item.sourceKind == 'kdrive') continue;
    final size = item.sizeBytes;
    if (size == null || size <= 0 || item.name.isEmpty) continue;
    final match = index['${item.name}|$size'];
    if (match != null && seen.add(match.id)) locals.add(match);
  }
  return mergeGalleryEntries(cloud: cloud, local: locals);
}
