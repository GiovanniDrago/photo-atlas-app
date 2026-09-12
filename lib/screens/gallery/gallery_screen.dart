import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/media_item.dart';
import '../../providers/library_providers.dart';
import '../../services/api_client.dart';
import '../../widgets/media_thumbnail.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  MediaFilter _filter = const MediaFilter();
  final List<MediaItem> _items = [];
  final ScrollController _scrollController = ScrollController();
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
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
    setState(() => _filter = filter);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tileSize = (MediaQuery.sizeOf(context).width - 24 - 12) / 3;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.galleryTab)),
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
                        return MediaThumbnail(
                          item: _items[index],
                          size: tileSize,
                          showName: false,
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
