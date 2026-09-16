import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/media_item.dart';
import '../../providers/library_providers.dart';
import '../../services/api_client.dart';
import '../../services/export_service.dart';
import '../../widgets/media_thumbnail.dart';
import 'media_detail_screen.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  MediaFilter _filter = const MediaFilter();
  final List<MediaItem> _items = [];
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedIds = {};
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _selectionMode = false;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _total = 0;
    });
    try {
      final page = await ref
          .read(apiClientProvider)
          .media(
            status: _filter.missingOnly ? 'missing' : _filter.status,
            type: _filter.type,
            limit: 200,
            offset: 0,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(apiClientProvider)
          .media(
            status: _filter.missingOnly ? 'missing' : _filter.status,
            type: _filter.type,
            limit: 200,
            offset: _items.length,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _setFilter(MediaFilter filter) {
    setState(() {
      _filter = filter;
      _selectedIds.clear();
      _selectionMode = false;
    });
    _reload();
  }

  void _toggleSelection(MediaItem item) {
    setState(() {
      if (_selectedIds.contains(item.id)) {
        _selectedIds.remove(item.id);
      } else {
        _selectedIds.add(item.id);
      }
    });
  }

  void _enterSelection(MediaItem item) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(item.id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _selectAllLoaded() {
    setState(() {
      if (_selectedIds.length == _items.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_items.map((item) => item.id));
      }
    });
  }

  void _openDetail(MediaItem item) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => MediaDetailScreen(item: item)));
  }

  Future<void> _exportSelected() async {
    final l10n = AppLocalizations.of(context)!;
    final selected = _items
        .where((item) => _selectedIds.contains(item.id))
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
      _exitSelection();
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
  };

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tileSize = (MediaQuery.sizeOf(context).width - 24 - 12) / 3;

    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelection,
              ),
              title: Text(l10n.selectedCount(_selectedIds.length)),
              actions: [
                IconButton(
                  tooltip: l10n.selectAll,
                  onPressed: _items.isEmpty ? null : _selectAllLoaded,
                  icon: const Icon(Icons.select_all),
                ),
                IconButton(
                  tooltip: l10n.exportMetadata,
                  onPressed: _selectedIds.isEmpty || _exporting
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
          : AppBar(title: Text(l10n.galleryTab)),
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
                    selected: _filter.type == 'all' && !_filter.missingOnly,
                    onSelected: () => _setFilter(const MediaFilter()),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: l10n.photosOnly,
                    selected: _filter.type == 'image' && !_filter.missingOnly,
                    onSelected: () =>
                        _setFilter(const MediaFilter(type: 'image')),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: l10n.videosOnly,
                    selected: _filter.type == 'video' && !_filter.missingOnly,
                    onSelected: () =>
                        _setFilter(const MediaFilter(type: 'video')),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: l10n.missingMetadataOnly,
                    selected: _filter.missingOnly,
                    onSelected: () =>
                        _setFilter(const MediaFilter(missingOnly: true)),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.errorLoading),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _reload,
                          child: Text(l10n.retry),
                        ),
                      ],
                    ),
                  )
                : _items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.galleryEmpty,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                            childAspectRatio: 1,
                          ),
                      itemCount: _items.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _items.length) {
                          return const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        final item = _items[index];
                        final selected = _selectedIds.contains(item.id);
                        return MediaThumbnail(
                          item: item,
                          size: tileSize,
                          showName: false,
                          selectionMode: _selectionMode,
                          selected: selected,
                          onTap: () {
                            if (_selectionMode) {
                              _toggleSelection(item);
                            } else {
                              _openDetail(item);
                            }
                          },
                          onLongPress: () => _enterSelection(item),
                        );
                      },
                    ),
                  ),
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
