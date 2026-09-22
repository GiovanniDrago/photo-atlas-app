import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gallery_entry.dart';
import '../models/media_item.dart';
import '../services/api_client.dart';
import '../services/local_media_service.dart';
import '../services/scan_models.dart';
import 'library_providers.dart';

class GalleryState {
  final List<GalleryEntry> entries;
  final GalleryFilter filter;
  final int cloudTotal;
  final int localTotal;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final bool localPermissionDenied;
  final bool localSupported;

  const GalleryState({
    this.entries = const [],
    this.filter = const GalleryFilter(),
    this.cloudTotal = 0,
    this.localTotal = 0,
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
    this.localPermissionDenied = false,
    this.localSupported = false,
  });

  bool get isEmpty => !loading && error == null && entries.isEmpty;

  GalleryState copyWith({
    List<GalleryEntry>? entries,
    GalleryFilter? filter,
    int? cloudTotal,
    int? localTotal,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    String? error,
    bool? localPermissionDenied,
    bool? localSupported,
  }) {
    return GalleryState(
      entries: entries ?? this.entries,
      filter: filter ?? this.filter,
      cloudTotal: cloudTotal ?? this.cloudTotal,
      localTotal: localTotal ?? this.localTotal,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error ?? this.error,
      localPermissionDenied:
          localPermissionDenied ?? this.localPermissionDenied,
      localSupported: localSupported ?? this.localSupported,
    );
  }
}

/// Loads the indexed items and the device files in pages and merges them.
class GalleryController extends Notifier<GalleryState> {
  static const _cloudPageSize = 100;
  static const _localPageSize = 60;

  final List<MediaItem> _cloud = [];
  final List<LocalMedia> _local = [];
  int _cloudPage = 0;
  int _localPage = 0;
  int _cloudTotal = 0;
  int _localTotal = 0;
  bool _cloudDone = false;
  bool _localDone = false;
  bool _localPermissionDenied = false;
  bool _disposed = false;
  int _generation = 0;
  GalleryFilter _filter = const GalleryFilter();

  @override
  GalleryState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.watch(apiClientProvider);
    _reset();
    unawaited(_loadFirstPages());
    return GalleryState(
      filter: _filter,
      localSupported: LocalMediaService.isSupported,
    );
  }

  void _reset() {
    _generation += 1;
    _cloud.clear();
    _local.clear();
    _cloudPage = 0;
    _localPage = 0;
    _cloudTotal = 0;
    _localTotal = 0;
    _cloudDone = false;
    _localDone = !LocalMediaService.isSupported;
    _localPermissionDenied = false;
  }

  bool _isStale(int generation) => _disposed || generation != _generation;

  void setFilter(GalleryFilter filter) {
    if (filter == _filter) return;
    _filter = filter;
    _reset();
    state = GalleryState(
      filter: _filter,
      localSupported: LocalMediaService.isSupported,
    );
    unawaited(_loadFirstPages());
  }

  Future<void> refresh() async {
    LocalMediaService.invalidateCache();
    _reset();
    state = GalleryState(
      filter: _filter,
      localSupported: LocalMediaService.isSupported,
    );
    await _loadFirstPages();
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore) return;
    if (_cloudDone && _localDone) return;
    final generation = _generation;
    state = state.copyWith(loadingMore: true);
    final client = ref.read(apiClientProvider);
    final tasks = <Future<void>>[
      if (!_cloudDone) _fetchCloud(client, _cloudPage, generation),
      if (!_localDone) _fetchLocal(client, _localPage, generation),
    ];
    await Future.wait(tasks);
    if (_isStale(generation)) return;
    state = _snapshot(loading: false, loadingMore: false);
  }

  Future<void> _loadFirstPages() async {
    final generation = _generation;
    final client = ref.read(apiClientProvider);
    final cloudFuture = _fetchCloud(client, 0, generation);
    final localFuture = LocalMediaService.isSupported
        ? _fetchLocal(client, 0, generation)
        : Future<void>.value();
    String? error;
    try {
      await cloudFuture;
    } catch (failure) {
      error = '$failure';
      _cloudDone = true;
    }
    try {
      await localFuture;
    } on ScanPermissionException {
      _localPermissionDenied = true;
      _localDone = true;
    } catch (_) {
      _localDone = true;
    }
    if (_isStale(generation)) return;
    state = _snapshot(loading: false, error: error);
  }

  Future<void> _fetchCloud(ApiClient client, int page, int generation) async {
    final result = await client.media(
      status: _filter.missingOnly ? 'missing' : 'all',
      type: _filter.type,
      backupStatus: _filter.backupStatus,
      limit: _cloudPageSize,
      offset: page * _cloudPageSize,
    );
    if (_isStale(generation)) return;
    final items = result.items;
    if (page == 0) {
      _cloud
        ..clear()
        ..addAll(items);
    } else {
      _cloud.addAll(items);
    }
    _cloudTotal = result.total;
    _cloudPage = page + 1;
    _cloudDone = items.length < _cloudPageSize || _cloud.length >= _cloudTotal;
  }

  Future<void> _fetchLocal(ApiClient client, int page, int generation) async {
    final result = await LocalMediaService.page(
      client: client,
      page: page,
      size: _localPageSize,
    );
    if (_isStale(generation)) return;
    if (page == 0) {
      _local
        ..clear()
        ..addAll(result.items);
    } else {
      _local.addAll(result.items);
    }
    _localTotal = result.total;
    _localPage = page + 1;
    _localDone = !result.hasMore;
    _localPermissionDenied = false;
  }

  GalleryState _snapshot({
    required bool loading,
    bool loadingMore = false,
    String? error,
  }) {
    final merged = mergeGalleryEntries(
      cloud: _cloud,
      local: _local,
    ).where((entry) => galleryEntryMatches(entry, _filter)).toList();
    return GalleryState(
      entries: merged,
      filter: _filter,
      cloudTotal: _cloudTotal,
      localTotal: _localTotal,
      loading: loading,
      loadingMore: loadingMore,
      hasMore: !_cloudDone || !_localDone,
      error: error,
      localPermissionDenied: _localPermissionDenied,
      localSupported: LocalMediaService.isSupported,
    );
  }
}

final galleryProvider = NotifierProvider<GalleryController, GalleryState>(
  GalleryController.new,
);
