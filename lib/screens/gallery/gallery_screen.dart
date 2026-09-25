import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/album.dart';
import '../../models/gallery_entry.dart';
import '../../models/gallery_upload.dart';
import '../../models/media_item.dart';
import '../../providers/album_providers.dart';
import '../../providers/collections_providers.dart';
import '../../providers/gallery_providers.dart';
import '../../providers/library_providers.dart';
import '../../services/export_service.dart';
import '../../services/gallery_actions_service.dart';
import '../../services/local_media_service.dart';
import '../../services/scan_models.dart';
import '../../services/scan_service.dart';
import '../../widgets/delete_media_dialog.dart';
import '../../widgets/gallery_tile.dart';
import '../../widgets/media_action_bar.dart';
import '../../widgets/upload_progress_sheet.dart';
import '../albums/album_dialogs.dart';
import '../albums/album_edit_screen.dart';
import '../albums/album_picker_sheet.dart';
import 'gallery_geometry.dart';
import 'media_viewer_screen.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  /// [scope] selects what the gallery shows: the whole library (default), a
  /// single device folder or a user album. [header] is shown above the grid
  /// (folder controls), [title] replaces the tab title, [showFilters] hides the
  /// filter chips and [album] turns the screen into an album detail (rules
  /// header, rename/edit/delete and remove-from-album actions).
  final GalleryScope scope;
  final String? title;
  final Widget? header;
  final bool showFilters;
  final Album? album;

  const GalleryScreen({
    super.key,
    this.scope = GalleryScope.tab,
    this.title,
    this.header,
    this.showFilters = true,
    this.album,
  });

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  Album? _album;
  final Set<String> _selectedKeys = {};

  /// Details of the running upload (null for other runs): drives the tappable
  /// bottom bar and the progress sheet.
  final ValueNotifier<GalleryUploadState?> _upload = ValueNotifier(null);
  bool _uploadCancelled = false;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _gridKey = GlobalKey();
  bool _selectionMode = false;
  bool _exporting = false;
  bool _busy = false;
  String? _busyLabel;
  GalleryActionProgress? _progress;
  double _tileSize = 100;
  bool _dragValue = true;
  int? _lastDragIndex;
  Offset? _dragPosition;
  double _dragDirection = 0;
  Timer? _dragTimer;

  @override
  void initState() {
    super.initState();
    _album = widget.album;
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _dragTimer?.cancel();
    _scrollController.dispose();
    _upload.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      ref.read(galleryProvider(widget.scope).notifier).loadMore();
    }
  }

  GalleryController get _controller =>
      ref.read(galleryProvider(widget.scope).notifier);

  List<GalleryEntry> get _entries =>
      ref.read(galleryProvider(widget.scope)).entries;

  List<GalleryEntry> get _selectedEntries => [
    for (final entry in _entries)
      if (_selectedKeys.contains(entry.key)) entry,
  ];

  void _setFilter(GalleryFilter filter) {
    _clearSelection();
    _controller.setFilter(filter);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _toggleSelection(GalleryEntry entry) {
    setState(() {
      if (!_selectedKeys.remove(entry.key)) _selectedKeys.add(entry.key);
      if (_selectedKeys.isEmpty) _selectionMode = false;
    });
  }

  int? _indexAt(Offset globalPosition) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return galleryIndexAt(
      localPosition: box.globalToLocal(globalPosition),
      scrollOffset: _scrollController.hasClients ? _scrollController.offset : 0,
      tileSize: _tileSize,
      crossAxisCount: 3,
      itemCount: _entries.length,
    );
  }

  void _applyDragValue(String key, bool value) {
    if (value) {
      _selectedKeys.add(key);
    } else {
      _selectedKeys.remove(key);
    }
  }

  /// Long press starts the selection; dragging over the grid keeps toggling
  /// the tiles it passes (selecting or deselecting, like Google Photos).
  void _onLongPressStart(LongPressStartDetails details) {
    final index = _indexAt(details.globalPosition);
    if (index == null) return;
    final entry = _entries[index];
    final value = !_selectedKeys.contains(entry.key);
    setState(() {
      _selectionMode = true;
      _dragValue = value;
      _applyDragValue(entry.key, value);
      _lastDragIndex = index;
      _dragPosition = details.globalPosition;
    });
    _updateAutoScroll(details.globalPosition);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    _dragPosition = details.globalPosition;
    _extendSelection(details.globalPosition);
    _updateAutoScroll(details.globalPosition);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _stopAutoScroll();
    setState(() {
      _lastDragIndex = null;
      _dragPosition = null;
      if (_selectedKeys.isEmpty) _selectionMode = false;
    });
  }

  void _extendSelection(Offset globalPosition) {
    final index = _indexAt(globalPosition);
    if (index == null) return;
    final last = _lastDragIndex;
    if (last == index) return;
    final entries = _entries;
    final from = last ?? index;
    setState(() {
      if (index >= from) {
        for (var i = from; i <= index; i += 1) {
          if (i >= 0 && i < entries.length) {
            _applyDragValue(entries[i].key, _dragValue);
          }
        }
      } else {
        for (var i = from; i >= index; i -= 1) {
          if (i >= 0 && i < entries.length) {
            _applyDragValue(entries[i].key, _dragValue);
          }
        }
      }
      _lastDragIndex = index;
    });
  }

  void _updateAutoScroll(Offset globalPosition) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    const edge = 72.0;
    if (local.dy < edge) {
      _startAutoScroll(-1);
    } else if (local.dy > box.size.height - edge) {
      _startAutoScroll(1);
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll(double direction) {
    _dragDirection = direction;
    _dragTimer ??= Timer.periodic(
      const Duration(milliseconds: 60),
      (_) => _autoScrollTick(),
    );
  }

  void _stopAutoScroll() {
    _dragDirection = 0;
    _dragTimer?.cancel();
    _dragTimer = null;
  }

  void _autoScrollTick() {
    if (_dragDirection == 0 || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (position.pixels + _dragDirection * 26).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != position.pixels) _scrollController.jumpTo(target);
    final global = _dragPosition;
    if (global != null) _extendSelection(global);
  }

  void _clearSelection() {
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedKeys.clear();
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedKeys.length == _entries.length) {
        _selectedKeys.clear();
      } else {
        _selectedKeys
          ..clear()
          ..addAll(_entries.map((entry) => entry.key));
      }
    });
  }

  Future<void> _openViewer(int index) async {
    final entries = List<GalleryEntry>.of(_entries);
    if (index < 0 || index >= entries.length) return;
    final key = entries[index].key;
    final result = await Navigator.of(context).push<MediaViewerResult>(
      MaterialPageRoute(
        builder: (_) =>
            MediaViewerScreen(entries: entries, initialIndex: index),
      ),
    );
    if (!mounted || result != MediaViewerResult.select) return;
    setState(() {
      _selectionMode = true;
      _selectedKeys.add(key);
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh() async {
    // Keep the folder counters (uploaded X of Y), album covers and the failed
    // upload count in sync.
    ref.invalidate(backupStatusProvider);
    ref.invalidate(sourcesProvider);
    ref.invalidate(albumsProvider);
    ref.invalidate(albumFailedCountProvider);
    await _controller.refresh();
  }

  void _report(String message, GalleryActionResult result) {
    if (!mounted) return;
    final detail = result.errors.isEmpty ? '' : ' · ${result.errors.first}';
    _snack('$message$detail');
  }

  Future<void> _runUpload() async {
    final l10n = AppLocalizations.of(context)!;
    await _startUpload(
      _selectedEntries,
      label: l10n.galleryUploading,
      noTargetsMessage: null,
    );
  }

  /// Uploads [entries] (device files not yet on kDrive) with the tappable
  /// progress bar open on the live detail; used by Gallery, folder and album
  /// scopes and by the album "retry failed" row.
  Future<void> _startUpload(
    List<GalleryEntry> entries, {
    required String label,
    required String? noTargetsMessage,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final targets = [
      for (final entry in entries)
        if (entry.canUpload) entry,
    ];
    if (targets.isEmpty) {
      if (noTargetsMessage != null) _snack(noTargetsMessage);
      return;
    }
    _uploadCancelled = false;
    _upload.value = GalleryUploadState(
      label: label,
      targets: targets,
      total: targets.length,
    );
    setState(() {
      _busy = true;
      _busyLabel = label;
      _progress = null;
    });
    var uploaded = 0;
    var failed = 0;
    try {
      final service = GalleryActionsService(ref.read(apiClientProvider));
      final result = await service.upload(
        targets,
        isCancelled: () => _uploadCancelled,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
          _upload.value = _upload.value?.record(progress);
        },
      );
      uploaded = result.uploaded;
      failed = result.failed;
      _upload.value = _upload.value?.finish(
        uploaded: uploaded,
        failed: failed,
        cancelled: _uploadCancelled,
      );
      _report(
        failed > 0
            ? l10n.galleryUploadedFailed(uploaded, failed)
            : _uploadCancelled
            ? l10n.uploadStopped
            : l10n.galleryUploadedCount(uploaded),
        result,
      );
      _clearSelection();
    } catch (error) {
      if (mounted) _snack('$error');
      _upload.value = _upload.value?.finish(
        uploaded: uploaded,
        failed: failed + targets.length,
        cancelled: _uploadCancelled,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
          _progress = null;
        });
      }
      await _refresh();
    }
  }

  void _cancelUpload() {
    _uploadCancelled = true;
    _upload.value = _upload.value?.markStopping();
  }

  Future<void> _openUploadSheet() async {
    if (_upload.value == null) return;
    await showUploadProgressSheet(
      context,
      state: _upload,
      onStop: _cancelUpload,
    );
    if (!mounted) return;
    // Drop the finished detail: the next run starts clean.
    if (_upload.value?.running == false) _upload.value = null;
  }

  Future<void> _runDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    final options = await showDeleteMediaDialog(context, entries);
    if (options == null || !mounted) return;
    if (!options.cloud && !options.local) return;
    _upload.value = null;
    setState(() {
      _busy = true;
      _busyLabel = l10n.galleryDeleting;
      _progress = null;
    });
    try {
      final service = GalleryActionsService(ref.read(apiClientProvider));
      final result = await service.delete(
        entries,
        cloud: options.cloud,
        local: options.local,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      _report(
        result.failed > 0
            ? l10n.galleryDeletedFailed(result.failed)
            : l10n.galleryDeleted(
                result.localDeleted + result.indexDeleted + result.reset,
              ),
        result,
      );
      _clearSelection();
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
          _progress = null;
        });
      }
      await _refresh();
    }
  }

  Future<void> _runShare() async {
    final l10n = AppLocalizations.of(context)!;
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    _upload.value = null;
    setState(() {
      _busy = true;
      _busyLabel = l10n.galleryPreparingShare;
      _progress = null;
    });
    try {
      final service = GalleryActionsService(ref.read(apiClientProvider));
      final result = await service.share(
        entries,
        sharePositionOrigin: _shareOrigin(),
      );
      if (result.errors.isNotEmpty) {
        _report(l10n.galleryShareFailed, result);
      }
      _clearSelection();
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
          _progress = null;
        });
      }
    }
  }

  Rect? _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _exportSelected() async {
    final l10n = AppLocalizations.of(context)!;
    final selected = _selectedEntries
        .map((entry) => entry.cloud)
        .whereType<MediaItem>()
        .toList();
    if (selected.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final payload = {
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'count': selected.length,
        'items': [for (final item in selected) _exportItem(item)],
      };
      final content = const JsonEncoder.withIndent('  ').convert(payload);
      final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
      final filename = 'photo-atlas-metadata-$stamp.json';
      final result = await saveMetadataExport(
        filename: filename,
        content: content,
      );
      if (!mounted) return;
      final savedToPath = result != null && result != filename;
      _snack(savedToPath ? l10n.exportSavedTo(result) : l10n.exportStarted);
      _clearSelection();
    } catch (error) {
      if (mounted) _snack('${l10n.exportFailed}: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Map<String, dynamic> _exportItem(MediaItem item) => {
    'id': item.id,
    'name': item.name,
    'media_type': item.mediaType,
    'mime': item.mime,
    'size_bytes': item.sizeBytes,
    'taken_at': item.takenAt?.toUtc().toIso8601String(),
    'file_created_at': item.fileCreatedAt?.toUtc().toIso8601String(),
    'modified_at': item.modifiedAt?.toUtc().toIso8601String(),
    'latitude': item.lat,
    'longitude': item.lon,
    'has_gps': item.hasGps,
    'width': item.width,
    'height': item.height,
    'duration_s': item.durationS,
    'metadata_status': item.metadataStatus,
    'source': item.sourceLabel,
    'source_kind': item.sourceKind,
    'external_key': item.externalKey,
    'path': item.path,
    'backup_status': item.backupStatus,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(galleryProvider(widget.scope));
    final filter = state.filter;
    final tileSize = (MediaQuery.sizeOf(context).width - 24 - 12) / 3;
    _tileSize = tileSize;

    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _busy ? null : _clearSelection,
              ),
              title: Text(l10n.selectedCount(_selectedKeys.length)),
              actions: [
                IconButton(
                  tooltip: l10n.selectAll,
                  onPressed: state.entries.isEmpty || _busy ? null : _selectAll,
                  icon: const Icon(Icons.select_all),
                ),
                IconButton(
                  tooltip: l10n.exportMetadata,
                  onPressed: _selectedKeys.isEmpty || _exporting || _busy
                      ? null
                      : _exportSelected,
                  icon: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                ),
              ],
            )
          : AppBar(
              title: Text(_album?.name ?? widget.title ?? l10n.galleryTab),
              actions: [
                IconButton(
                  tooltip: l10n.retry,
                  onPressed: state.loading ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
                if (_album != null)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _openAlbumEditor();
                      } else if (value == 'rename') {
                        _renameAlbum();
                      } else if (value == 'delete') {
                        _deleteAlbum();
                      }
                    },
                    itemBuilder: (context) => [
                      if (_album!.isSmart)
                        PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.tune),
                            title: Text(l10n.albumEditRules),
                          ),
                        ),
                      PopupMenuItem(
                        value: 'rename',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(l10n.albumRename),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.delete_outline),
                          title: Text(l10n.albumDelete),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
      body: Column(
        children: [
          if (_album != null)
            _AlbumHeader(
              album: _album!,
              lines: _albumRuleLines(_album!, l10n),
              onRetryFailed: _runRetryFailed,
            ),
          if (widget.header != null) widget.header!,
          if (widget.showFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: l10n.allImages,
                      selected: filter == const GalleryFilter(),
                      onSelected: () => _setFilter(const GalleryFilter()),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: l10n.photosOnly,
                      selected:
                          filter.type == 'image' &&
                          filter.upload == GalleryUploadFilter.all &&
                          !filter.missingOnly,
                      onSelected: () =>
                          _setFilter(const GalleryFilter(type: 'image')),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: l10n.videosOnly,
                      selected:
                          filter.type == 'video' &&
                          filter.upload == GalleryUploadFilter.all &&
                          !filter.missingOnly,
                      onSelected: () =>
                          _setFilter(const GalleryFilter(type: 'video')),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: l10n.galleryNotUploaded,
                      selected: filter.upload == GalleryUploadFilter.pending,
                      onSelected: () => _setFilter(
                        const GalleryFilter(
                          upload: GalleryUploadFilter.pending,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: l10n.galleryUploaded,
                      selected: filter.upload == GalleryUploadFilter.uploaded,
                      onSelected: () => _setFilter(
                        const GalleryFilter(
                          upload: GalleryUploadFilter.uploaded,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: l10n.missingMetadataOnly,
                      selected: filter.missingOnly,
                      onSelected: () =>
                          _setFilter(const GalleryFilter(missingOnly: true)),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                state.localLoading
                    ? l10n.galleryDeviceLoading
                    : _album != null
                    ? l10n.itemCount(state.cloudTotal)
                    : l10n.galleryCounts(state.localTotal, state.cloudTotal),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          if (state.localPermissionDenied)
            _PermissionBanner(onOpenSettings: ScanService.openSettings),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: _busy ? null : _onLongPressStart,
              onLongPressMoveUpdate: _busy ? null : _onLongPressMoveUpdate,
              onLongPressEnd: _busy ? null : _onLongPressEnd,
              child: _body(state, l10n, tileSize),
            ),
          ),
          if (_selectionMode && !_busy) _actionBar(l10n),
          if (_busy) _progressBar(l10n),
        ],
      ),
    );
  }

  Widget _body(GalleryState state, AppLocalizations l10n, double tileSize) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.errorLoading),
            const SizedBox(height: 8),
            FilledButton(onPressed: _refresh, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    if (state.entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.galleryEmpty, textAlign: TextAlign.center),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridView.builder(
        key: _gridKey,
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1,
        ),
        itemCount: state.entries.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.entries.length) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final entry = state.entries[index];
          return GalleryTile(
            entry: entry,
            size: tileSize,
            selectionMode: _selectionMode,
            selected: _selectedKeys.contains(entry.key),
            onTap: () {
              if (_busy) return;
              if (_selectionMode) {
                _toggleSelection(entry);
              } else {
                _openViewer(index);
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _runAddToAlbum() async {
    final l10n = AppLocalizations.of(context)!;
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    final result = await showAddToAlbumSheet(context, entries);
    if (!mounted || result == null) return;
    final detail = result.errors.isEmpty ? '' : ' · ${result.errors.first}';
    _snack('${l10n.albumAddResult(result.added, result.failed)}$detail');
    _clearSelection();
    await _refresh();
  }

  Future<void> _runRetryFailed() async {
    final l10n = AppLocalizations.of(context)!;
    final album = _album;
    if (album == null) return;
    List<GalleryEntry> entries;
    try {
      final page = await ref
          .read(apiClientProvider)
          .albumMedia(album.id, backupStatus: 'failed', limit: 500);
      if (page.items.isEmpty) return;
      final locals = await LocalMediaService.resolveForItems(page.items);
      final byKey = {for (final local in locals) local.id: local};
      entries = [
        for (final item in page.items)
          GalleryEntry(cloud: item, local: byKey[item.externalKey]),
      ];
    } on ScanPermissionException {
      if (mounted) _snack(l10n.galleryLocalPermissionDenied);
      return;
    } catch (error) {
      if (mounted) _snack('$error');
      return;
    }
    await _startUpload(
      entries,
      label: l10n.albumRetrying,
      noTargetsMessage: l10n.albumRetryNoFiles,
    );
  }

  /// Delete dialog with the album option: relation, device file and/or the
  /// kDrive copy, combined in one flow.
  Future<void> _runAlbumDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final album = _album;
    final entries = _selectedEntries;
    if (album == null || entries.isEmpty) return;
    final options = await showDeleteMediaDialog(
      context,
      entries,
      allowAlbum: !album.isSmart,
    );
    if (options == null || !mounted) return;
    if (!options.cloud && !options.local && !options.album) return;
    setState(() => _busy = true);
    try {
      if (options.album) {
        final ids = [
          for (final entry in entries)
            if (entry.cloud != null) entry.cloud!.id,
        ];
        if (ids.isNotEmpty) {
          await ref
              .read(apiClientProvider)
              .removeAlbumItems(albumId: album.id, mediaIds: ids);
        }
      }
      if (options.cloud || options.local) {
        final result = await GalleryActionsService(ref.read(apiClientProvider))
            .delete(entries, cloud: options.cloud, local: options.local);
        if (!mounted) return;
        _snack(
          result.failed > 0
              ? l10n.galleryDeletedFailed(result.failed)
              : l10n.galleryDeleted(
                  result.localDeleted + result.indexDeleted + result.reset,
                ),
        );
      } else if (mounted) {
        _snack(l10n.albumRemoved(entries.length));
      }
      _clearSelection();
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _runDownload() async {
    final l10n = AppLocalizations.of(context)!;
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    var failed = 0;
    for (final entry in entries) {
      final url = entry.cloud?.downloadUrl;
      if (url == null || url.isEmpty) {
        failed += 1;
        continue;
      }
      try {
        final opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) failed += 1;
      } catch (_) {
        failed += 1;
      }
    }
    if (mounted && failed > 0) _snack(l10n.downloadUnavailable);
    _clearSelection();
  }

  Future<void> _runRemoveFromAlbum() async {
    final l10n = AppLocalizations.of(context)!;
    final album = _album;
    if (album == null) return;
    final ids = [
      for (final entry in _selectedEntries)
        if (entry.cloud != null) entry.cloud!.id,
    ];
    if (ids.isEmpty) return;
    setState(() => _busy = true);
    try {
      final removed = await ref
          .read(apiClientProvider)
          .removeAlbumItems(albumId: album.id, mediaIds: ids);
      if (!mounted) return;
      _snack(l10n.albumRemoved(removed));
      _clearSelection();
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _runSetCover() async {
    final l10n = AppLocalizations.of(context)!;
    final album = _album;
    if (album == null) return;
    final selected = _selectedEntries
        .where((entry) => entry.cloud != null)
        .toList();
    if (selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .updateAlbum(album.id, coverMediaId: selected.first.cloud!.id);
      if (!mounted) return;
      setState(() => _album = updated);
      ref.invalidate(albumsProvider);
      _snack(l10n.albumCoverUpdated);
      _clearSelection();
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAlbumEditor() async {
    final album = _album;
    if (album == null) return;
    final updated = await Navigator.of(context).push<Album>(
      MaterialPageRoute(builder: (_) => AlbumEditScreen(album: album)),
    );
    if (!mounted) return;
    ref.invalidate(albumsProvider);
    if (updated == null) return;
    setState(() => _album = updated);
    await _controller.refresh();
  }

  Future<void> _renameAlbum() async {
    final album = _album;
    if (album == null) return;
    final name = await showAlbumNameDialog(context, initialName: album.name);
    if (!mounted || name == null) return;
    try {
      final updated = await ref
          .read(apiClientProvider)
          .updateAlbum(album.id, name: name);
      if (!mounted) return;
      setState(() => _album = updated);
      ref.invalidate(albumsProvider);
    } catch (error) {
      if (mounted) _snack('$error');
    }
  }

  Future<void> _deleteAlbum() async {
    final l10n = AppLocalizations.of(context)!;
    final album = _album;
    if (album == null) return;
    if (!await showAlbumDeleteDialog(context, album)) return;
    if (!mounted) return;
    try {
      await ref.read(apiClientProvider).deleteAlbum(album.id);
      ref.invalidate(albumsProvider);
      if (!mounted) return;
      _snack(l10n.albumDeleted);
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _snack('$error');
    }
  }

  Widget _actionBar(AppLocalizations l10n) {
    final entries = _selectedEntries;
    final album = _album;
    if (album != null) {
      final canUpload = entries.any((entry) => entry.canUpload);
      final canShare = entries.any(
        (entry) =>
            entry.hasLocal || (entry.cloud?.downloadUrl ?? '').isNotEmpty,
      );
      final canDownload = entries.any(
        (entry) => (entry.cloud?.downloadUrl ?? '').isNotEmpty,
      );
      final canRemove = entries.any((entry) => entry.cloud != null);
      final canDelete = entries.any(
        (entry) => entry.canDeleteCloud || entry.canDeleteLocal,
      );
      return MediaActionBar(
        actions: [
          MediaActionButton(
            icon: Icons.cloud_upload_outlined,
            label: l10n.galleryUpload,
            onPressed: canUpload ? _runUpload : null,
          ),
          MediaActionButton(
            icon: Icons.share_outlined,
            label: l10n.galleryShare,
            onPressed: canShare ? _runShare : null,
          ),
          MediaActionButton(
            icon: Icons.download_outlined,
            label: l10n.downloadOriginal,
            onPressed: canDownload ? _runDownload : null,
          ),
          MediaActionButton(
            icon: Icons.delete_outline,
            label: l10n.galleryDelete,
            onPressed: canDelete || canRemove ? _runAlbumDelete : null,
          ),
          if (!album.isSmart)
            MediaActionButton(
              icon: Icons.playlist_remove,
              label: l10n.albumRemove,
              onPressed: canRemove ? _runRemoveFromAlbum : null,
            ),
          MediaActionButton(
            icon: Icons.photo_camera_back_outlined,
            label: l10n.albumSetCover,
            onPressed: canRemove ? _runSetCover : null,
          ),
        ],
      );
    }
    final canUpload = entries.any((entry) => entry.canUpload);
    final canShare = entries.any(
      (entry) => entry.hasLocal || (entry.cloud?.downloadUrl ?? '').isNotEmpty,
    );
    final canDelete = entries.any(
      (entry) => entry.canDeleteCloud || entry.canDeleteLocal,
    );
    return MediaActionBar(
      actions: [
        MediaActionButton(
          icon: Icons.cloud_upload_outlined,
          label: l10n.galleryUpload,
          onPressed: canUpload ? _runUpload : null,
        ),
        MediaActionButton(
          icon: Icons.share_outlined,
          label: l10n.galleryShare,
          onPressed: canShare ? _runShare : null,
        ),
        MediaActionButton(
          icon: Icons.delete_outline,
          label: l10n.galleryDelete,
          onPressed: canDelete ? _runDelete : null,
        ),
        MediaActionButton(
          icon: Icons.playlist_add,
          label: l10n.albumAdd,
          onPressed: _runAddToAlbum,
        ),
      ],
    );
  }

  Widget _progressBar(AppLocalizations l10n) {
    final progress = _progress;
    final scheme = Theme.of(context).colorScheme;
    // Tapping the bar opens the per-file detail while an upload is running.
    final tappable = _upload.value != null;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress?.currentName == null
                      ? _busyLabel ?? ''
                      : '${_busyLabel ?? ''}: ${progress!.currentName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (tappable) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.expand_less,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress == null || progress.total == 0
                ? null
                : (progress.done / progress.total).clamp(0.0, 1.0),
          ),
          if (tappable)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                l10n.uploadDetails,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
    return SafeArea(
      child: tappable
          ? InkWell(onTap: _openUploadSheet, child: content)
          : content,
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _PermissionBanner({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Icon(Icons.photo_library_outlined, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.galleryLocalPermissionDenied,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: onOpenSettings,
            child: Text(l10n.galleryOpenSettings),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

List<String> _albumRuleLines(Album album, AppLocalizations l10n) {
  final draft = AlbumRuleDraft.fromRules(album.rules);
  final format = DateFormat.yMd();
  String range(DateTime? from, DateTime? to) {
    if (from != null && to != null) {
      return '${format.format(from)} - ${format.format(to)}';
    }
    if (from != null) return '>= ${format.format(from)}';
    return '<= ${format.format(to!)}';
  }

  final lines = <String>[];
  if (draft.takenFrom != null || draft.takenTo != null) {
    lines.add(
      '${l10n.albumRuleTaken}: ${range(draft.takenFrom, draft.takenTo)}',
    );
  }
  if (draft.uploadedFrom != null || draft.uploadedTo != null) {
    lines.add(
      '${l10n.albumRuleUploaded}: ${range(draft.uploadedFrom, draft.uploadedTo)}',
    );
  }
  if (draft.hasLocation) {
    final meters = draft.radiusM!;
    final km = (meters / 1000).toStringAsFixed(meters % 1000 == 0 ? 0 : 1);
    lines.add('${l10n.albumRuleLocation}: ${l10n.albumRuleRadius(km)}');
  }
  if (draft.mediaType == 'image') lines.add(l10n.albumRuleTypeImages);
  if (draft.mediaType == 'video') lines.add(l10n.albumRuleTypeVideos);
  return lines;
}

class _AlbumHeader extends ConsumerWidget {
  final Album album;
  final List<String> lines;
  final VoidCallback onRetryFailed;

  const _AlbumHeader({
    required this.album,
    required this.lines,
    required this.onRetryFailed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final failed = ref.watch(albumFailedCountProvider(album.id)).value ?? 0;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  album.isSmart ? l10n.albumKindSmart : l10n.albumKindManual,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.itemCount(album.itemCount),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(line, style: Theme.of(context).textTheme.labelSmall),
            ),
          if (failed > 0)
            Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.albumFailedUploads(failed),
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: onRetryFailed,
                  child: Text(l10n.albumRetryFailed),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
