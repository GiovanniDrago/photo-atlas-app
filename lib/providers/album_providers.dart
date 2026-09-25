import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import 'library_providers.dart';

final albumsProvider = FutureProvider<List<Album>>((ref) async {
  final client = ref.watch(apiClientProvider);
  return client.albums();
});
