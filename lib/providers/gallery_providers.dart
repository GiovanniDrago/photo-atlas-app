import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gallery_entry.dart';
import '../models/media_item.dart';
import '../services/api_client.dart';
import '../services/local_media_service.dart';
import '../services/scan_models.dart';
import 'library_providers.dart';

/// Which gallery a controller instance is showing: the whole library (tab), a
/// single device folder (collections) or a user album (albums).
class GalleryScope {
  final String? sourceId;
  final String? albumId;
  final String? rootPath;

  /// Server album id (`albums` table), cloud-only view.
  final String? userAlbumId;

  const GalleryScope({
    this.sourceId,
    this.albumId,
    this.rootPath,
    this.userAlbumId,
  });

  static const tab = GalleryScope();

  bool get isFolder => albumId != null || rootPath != null;
  bool get isUserAlbum => userAlbumId != null;

  @override
  bool operator ==(Object other) =>
      other is GalleryScope &&
      other.sourceId == sourceId &&
      other.albumId == albumId &&
      other.rootPath == rootPath &&
      other.userAlbumId == userAlbumId;

  @override
  int get hashCode => Object.hash(sourceId, albumId, rootPath, userAlbumId);
}

class GalleryState {
  final List<GalleryEntry> entries;
  final GalleryFilter filter;
  final int cloudTotal;
  final int localTotal;
  final bool loading;
  final bool localLoading;
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
    this.localLoading = false,
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
    bool? localLoading,
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
      localLoading: localLoading ?? this.localLoading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error ?? this.error,
      localPermissionDenied:
          localPermissionDenied ?? this.localPermissionDenied,
      localSupported: localSupported ?? this.localSupported,
    );
  }
}

/// Loads the indexed items (paged) and the whole device library (one ordered
/// query) and merges them.
class GalleryController extends Notifier<GalleryState> {
  GalleryController(this.scope);

  final GalleryScope scope;

  static const _cloudPageSize = 100;
  static const _localPageSize = 120;

  final List<MediaItem> _cloud = [];
  final Set<String> _cloudIds = {};
  final List<LocalMedia> _local = [];
  int _cloudPage = 0;
  int _localPage = 0;
  int _cloudTotal = 0;
  int _localTotal = 0;
  bool _cloudDone = false;
  bool _localDone = false;
  bool _localLoading = false;
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

  /// A folder gallery without an indexed source has nothing on the cloud side.
  bool get _cloudDisabled => scope.isFolder && scope.sourceId == null;

  void _reset() {
    _generation += 1;
    _cloud.clear();
    _cloudIds.clear();
    _local.clear();
    _cloudPage = 0;
    _localPage = 0;
    _cloudTotal = 0;
    _localTotal = 0;
    _cloudDone = _cloudDisabled;
    _localDone = !LocalMediaService.isSupported || scope.isUserAlbum;
    _localLoading = false;
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
      if (!_localDone && scope.isFolder)
        _fetchLocalPage(client, _localPage, generation),
    ];
    await Future.wait(tasks);
    if (_isStale(generation)) return;
    state = _snapshot(loading: false, loadingMore: false);
  }

  Future<void> _loadFirstPages() async {
    final generation = _generation;
    final client = ref.read(apiClientProvider);
    final cloudFuture = _cloudDisabled
        ? Future<void>.value()
        : _fetchCloud(client, 0, generation);
    final localFuture = scope.isFolder
        ? _fetchLocalPage(client, 0, generation)
        : scope.isUserAlbum
        ? Future<void>.value()
        : _loadLocal(client, generation);
    String? error;
    try {
      await cloudFuture;
    } catch (failure) {
      error = '$failure';
      _cloudDone = true;
    }
    if (_isStale(generation)) return;
    // The cloud items show up right away, the device library follows.
    state = _snapshot(loading: false, error: error);
    await localFuture;
    if (_isStale(generation)) return;
    state = _snapshot(loading: false, error: error);
  }

  Future<void> _fetchCloud(ApiClient client, int page, int generation) async {
    final albumId = scope.userAlbumId;
    final result = albumId != null
        ? await client.albumMedia(
            albumId,
            limit: _cloudPageSize,
            offset: page * _cloudPageSize,
          )
        : await client.media(
            status: _filter.missingOnly ? 'missing' : 'all',
            type: _filter.type,
            sourceId: scope.sourceId,
            backupStatus: _filter.backupStatus,
            limit: _cloudPageSize,
            offset: page * _cloudPageSize,
          );
    if (_isStale(generation)) return;
    final items = result.items;
    if (page == 0) {
      _cloud.clear();
      _cloudIds.clear();
    }
    for (final item in items) {
      if (_cloudIds.add(item.id)) _cloud.add(item);
    }
    _cloudTotal = result.total;
    _cloudPage = page + 1;
    _cloudDone = items.length < _cloudPageSize || _cloud.length >= _cloudTotal;
  }

  /// One page of the folder shown by this controller (bounded memory).
  Future<void> _fetchLocalPage(
    ApiClient client,
    int page,
    int generation,
  ) async {
    if (!LocalMediaService.isSupported) {
      _localDone = true;
      return;
    }
    if (page == 0) _localLoading = true;
    try {
      final result = await LocalMediaService.loadFolderPage(
        client: client,
        albumId: scope.albumId,
        rootPath: scope.rootPath,
        page: page,
        size: _localPageSize,
      );
      if (_isStale(generation)) return;
      if (page == 0) _local.clear();
      _local.addAll(result.items);
      _localTotal = result.total;
      _localPage = page + 1;
      _localDone = !result.hasMore;
      _localPermissionDenied = false;
    } on ScanPermissionException {
      if (_isStale(generation)) return;
      _localPermissionDenied = true;
      _localDone = true;
    } catch (_) {
      if (_isStale(generation)) return;
      _localDone = true;
    } finally {
      if (page == 0) _localLoading = false;
    }
  }

  Future<void> _loadLocal(ApiClient client, int generation) async {
    if (!LocalMediaService.isSupported) return;
    _localLoading = true;
    try {
      final result = await LocalMediaService.loadAll(client: client);
      if (_isStale(generation)) return;
      _local
        ..clear()
        ..addAll(result.items);
      _localTotal = result.total;
      _localPermissionDenied = false;
    } on ScanPermissionException {
      if (_isStale(generation)) return;
      _localPermissionDenied = true;
    } catch (_) {
      if (_isStale(generation)) return;
    } finally {
      _localLoading = false;
    }
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
      localLoading: _localLoading,
      loadingMore: loadingMore,
      hasMore: !_cloudDone || !_localDone,
      error: error,
      localPermissionDenied: _localPermissionDenied,
      localSupported: LocalMediaService.isSupported,
    );
  }
}

final galleryProvider =
    NotifierProvider.family<GalleryController, GalleryState, GalleryScope>(
      GalleryController.new,
    );
