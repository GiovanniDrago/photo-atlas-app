import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/media_cluster.dart';
import '../models/media_item.dart';
import '../models/source.dart';
import '../models/timeline_bucket.dart';
import '../services/api_client.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  final auth = ref.watch(authProvider);
  return ApiClient(
    baseUrl,
    token: auth.token,
    onUnauthorized: () => ref.read(authProvider.notifier).handleUnauthorized(),
  );
});

final healthProvider = FutureProvider<bool>((ref) {
  return ref.watch(apiClientProvider).health();
});

final sourcesProvider = FutureProvider<List<MediaSource>>((ref) {
  return ref.watch(apiClientProvider).sources();
});

final clustersProvider =
    FutureProvider.family<List<MediaCluster>, ClusterQuery>((ref, query) {
      final client = ref.watch(apiClientProvider);
      return client.clusters(
        west: query.west,
        south: query.south,
        east: query.east,
        north: query.north,
        zoom: query.zoom,
      );
    });

final clusterMediaProvider =
    FutureProvider.family<List<MediaItem>, ClusterQuery>((ref, query) {
      final client = ref.watch(apiClientProvider);
      return client
          .media(
            west: query.west,
            south: query.south,
            east: query.east,
            north: query.north,
            limit: 200,
          )
          .then((page) => page.items);
    });

final timelineProvider = FutureProvider<List<TimelineBucket>>((ref) {
  return ref.watch(apiClientProvider).timeline();
});

class TimelineQuery {
  final DateTime from;
  final DateTime to;

  const TimelineQuery({required this.from, required this.to});

  @override
  bool operator ==(Object other) =>
      other is TimelineQuery && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

final timelineItemsProvider = FutureProvider.family<MediaPage, TimelineQuery>((
  ref,
  query,
) {
  return ref
      .watch(apiClientProvider)
      .timelineItems(from: query.from, to: query.to);
});
