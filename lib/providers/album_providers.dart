import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import 'library_providers.dart';

final albumsProvider = FutureProvider<List<Album>>((ref) async {
  final client = ref.watch(apiClientProvider);
  return client.albums();
});

/// Number of album items whose upload failed (retry row in the album header).
final albumFailedCountProvider = FutureProvider.family<int, String>((
  ref,
  albumId,
) async {
  final client = ref.watch(apiClientProvider);
  final page = await client.albumMedia(
    albumId,
    backupStatus: 'failed',
    limit: 1,
  );
  return page.total;
});
