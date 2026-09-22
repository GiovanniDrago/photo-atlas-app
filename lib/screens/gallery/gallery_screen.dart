import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gallery_entry.dart';
import '../../models/media_item.dart';
import '../../providers/gallery_providers.dart';
import '../../providers/library_providers.dart';
import '../../services/export_service.dart';
import '../../services/gallery_actions_service.dart';
import '../../services/scan_service.dart';
import '../../widgets/gallery_tile.dart';
import 'media_detail_screen.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  final Set<String> _selectedKeys = {};
  final ScrollController _scrollController = ScrollController();
  bool _selectionMode = false;
  bool _exporting = false;
  bool _busy = false;
  String? _busyLabel;
  GalleryActionProgress? _progress;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      ref.read(galleryProvider.notifier).loadMore();
    }
  }

  GalleryController get _controller => ref.read(galleryProvider.notifier);

  List<GalleryEntry> get _entries => ref.read(galleryProvider).entries;

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

  void _enterSelection(GalleryEntry entry) {
    setState(() {
      _selectionMode = true;
      _selectedKeys.add(entry.key);
    });
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

  void _openDetail(GalleryEntry entry) {
    final item = entry.cloud;
    if (item == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => MediaDetailScreen(item: item)));
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh() async {
    await _controller.refresh();
  }

  void _report(String message, GalleryActionResult result) {
    if (!mounted) return;
    final detail = result.errors.isEmpty ? '' : ' · ${result.errors.first}';
    _snack('$message$detail');
  }

  Future<void> _runUpload() async {
    final l10n = AppLocalizations.of(context)!;
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    setState(() {
      _busy = true;
      _busyLabel = l10n.galleryUploading;
      _progress = null;
    });
    try {
      final service = GalleryActionsService(ref.read(apiClientProvider));
      final result = await service.upload(
        entries,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      _report(
        result.failed > 0
            ? l10n.galleryUploadedFailed(result.uploaded, result.failed)
            : l10n.galleryUploadedCount(result.uploaded),
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

  Future<void> _runDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    final options = await showDialog<_DeleteOptions>(
      context: context,
      builder: (context) => _DeleteDialog(entries: entries),
    );
    if (options == null || !mounted) return;
    if (!options.cloud && !options.local) return;
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
    final state = ref.watch(galleryProvider);
    final filter = state.filter;
    final tileSize = (MediaQuery.sizeOf(context).width - 24 - 12) / 3;

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
              title: Text(l10n.galleryTab),
              actions: [
                IconButton(
                  tooltip: l10n.retry,
                  onPressed: state.loading ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: Column(
        children: [
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
                      const GalleryFilter(upload: GalleryUploadFilter.pending),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: l10n.galleryUploaded,
                    selected: filter.upload == GalleryUploadFilter.uploaded,
                    onSelected: () => _setFilter(
                      const GalleryFilter(upload: GalleryUploadFilter.uploaded),
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
          if (state.localPermissionDenied)
            _PermissionBanner(onOpenSettings: ScanService.openSettings),
          Expanded(child: _body(state, l10n, tileSize)),
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
              } else if (entry.isIndexed) {
                _openDetail(entry);
              }
            },
            onLongPress: () => _enterSelection(entry),
          );
        },
      ),
    );
  }

  Widget _actionBar(AppLocalizations l10n) {
    final entries = _selectedEntries;
    final canUpload = entries.any((entry) => entry.canUpload);
    final canShare = entries.any(
      (entry) => entry.hasLocal || (entry.cloud?.downloadUrl ?? '').isNotEmpty,
    );
    final canDelete = entries.any(
      (entry) => entry.canDeleteCloud || entry.canDeleteLocal,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: canUpload ? _runUpload : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  l10n.galleryUpload,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: canShare ? _runShare : null,
                icon: const Icon(Icons.share_outlined),
                label: Text(
                  l10n.galleryShare,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: canDelete ? _runDelete : null,
                icon: const Icon(Icons.delete_outline),
                label: Text(
                  l10n.galleryDelete,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressBar(AppLocalizations l10n) {
    final progress = _progress;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              progress?.currentName == null
                  ? _busyLabel ?? ''
                  : '${_busyLabel ?? ''}: ${progress!.currentName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress == null || progress.total == 0
                  ? null
                  : (progress.done / progress.total).clamp(0.0, 1.0),
            ),
          ],
        ),
      ),
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

class _DeleteOptions {
  final bool cloud;
  final bool local;

  const _DeleteOptions({required this.cloud, required this.local});
}

class _DeleteDialog extends StatefulWidget {
  final List<GalleryEntry> entries;

  const _DeleteDialog({required this.entries});

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  late bool _cloud;
  late bool _local;

  bool get _canCloud => widget.entries.any((entry) => entry.canDeleteCloud);
  bool get _canLocal => widget.entries.any((entry) => entry.canDeleteLocal);

  @override
  void initState() {
    super.initState();
    _cloud = _canCloud;
    _local = _canLocal;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nothingSelected = !_cloud && !_local;
    return AlertDialog(
      title: Text(l10n.galleryDeleteTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            value: _cloud,
            onChanged: _canCloud
                ? (value) => setState(() => _cloud = value ?? false)
                : null,
            title: Text(l10n.galleryDeleteCloud),
            subtitle: Text(l10n.galleryDeleteCloudHint),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: _local,
            onChanged: _canLocal
                ? (value) => setState(() => _local = value ?? false)
                : null,
            title: Text(l10n.galleryDeleteLocal),
            subtitle: Text(l10n.galleryDeleteLocalHint),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: nothingSelected
              ? null
              : () =>
                    Navigator.of(context)
                        .pop(_DeleteOptions(cloud: _cloud, local: _local)),
          child: Text(l10n.galleryDeleteConfirm),
        ),
      ],
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
