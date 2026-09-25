import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gallery_entry.dart';
import '../../models/media_item.dart';
import '../../models/timeline_bucket.dart';
import '../../providers/collections_providers.dart';
import '../../providers/gallery_providers.dart';
import '../../providers/library_providers.dart';
import '../../services/gallery_actions_service.dart';
import '../../services/media_merge_service.dart';
import '../../widgets/delete_media_dialog.dart';
import '../../widgets/media_action_bar.dart';
import '../../widgets/media_selection.dart';
import '../../widgets/media_thumbnail.dart';
import '../albums/album_picker_sheet.dart';
import '../gallery/media_viewer_screen.dart';

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  final MediaSelection _selection = MediaSelection();
  bool _selectionMode = false;
  bool _busy = false;

  void _enterSelection(MediaItem item) {
    setState(() {
      _selectionMode = true;
      _selection.add(item.id);
    });
  }

  void _toggle(MediaItem item) {
    setState(() {
      _selection.toggle(item.id);
      if (_selection.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selection.clear();
    });
  }

  List<GalleryEntry> _selectedEntries() {
    final buckets =
        ref.read(timelineProvider).value ?? const <TimelineBucket>[];
    final entries = <GalleryEntry>[];
    for (final bucket in buckets) {
      final page = ref
          .read(
            timelineItemsProvider(
              TimelineQuery(from: bucket.bucketStart, to: bucket.bucketEnd),
            ),
          )
          .value;
      if (page == null) continue;
      for (final item in page.items) {
        if (_selection.contains(item.id))
          entries.add(GalleryEntry(cloud: item));
      }
    }
    return entries;
  }

  void _invalidateLibrary() {
    ref.invalidate(timelineProvider);
    ref.invalidate(timelineItemsProvider);
    ref.invalidate(galleryProvider);
    ref.invalidate(backupStatusProvider);
    ref.invalidate(sourcesProvider);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Rect? _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _runShare() async {
    final l10n = AppLocalizations.of(context)!;
    final entries = _selectedEntries();
    if (entries.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await GalleryActionsService(ref.read(apiClientProvider))
          .share(entries, sharePositionOrigin: _shareOrigin());
      if (result.errors.isNotEmpty && mounted) {
        _snack('${l10n.galleryShareFailed}: ${result.errors.first}');
      }
      _exitSelection();
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runDownload() async {
    final l10n = AppLocalizations.of(context)!;
    final entries = _selectedEntries();
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
    _exitSelection();
  }

  Future<void> _runAddToAlbum() async {
    final l10n = AppLocalizations.of(context)!;
    final entries = _selectedEntries();
    if (entries.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await showAddToAlbumSheet(context, entries);
      if (!mounted || result == null) return;
      final detail = result.errors.isEmpty ? '' : ' · ${result.errors.first}';
      _snack('${l10n.albumAddResult(result.added, result.failed)}$detail');
      _exitSelection();
    } finally {
      if (mounted) setState(() => _busy = false);
      _invalidateLibrary();
    }
  }

  Future<void> _runDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final entries = _selectedEntries();
    if (entries.isEmpty) return;
    final options = await showDeleteMediaDialog(context, entries);
    if (options == null || !mounted) return;
    if (!options.cloud && !options.local) return;
    setState(() => _busy = true);
    try {
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
      _exitSelection();
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
      _invalidateLibrary();
    }
  }

  Future<List<GalleryEntry>> _loadBucket(int index) async {
    final buckets =
        ref.read(timelineProvider).value ?? const <TimelineBucket>[];
    if (index < 0 || index >= buckets.length) return const [];
    final bucket = buckets[index];
    final page = await ref.read(
      timelineItemsProvider(
        TimelineQuery(from: bucket.bucketStart, to: bucket.bucketEnd),
      ).future,
    );
    return mergeCloudWithDevice(
      page.items,
      client: ref.read(apiClientProvider),
    );
  }

  Future<void> _openViewer(
    int bucketIndex,
    int itemIndex,
    List<MediaItem> items,
  ) async {
    final entries = await mergeCloudWithDevice(
      items,
      client: ref.read(apiClientProvider),
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          entries: entries,
          initialIndex: itemIndex,
          loadNext: () => _loadBucket(bucketIndex + 1),
          loadPrevious: () => _loadBucket(bucketIndex - 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bucketsAsync = ref.watch(timelineProvider);
    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _busy ? null : _exitSelection,
              ),
              title: Text(l10n.selectedCount(_selection.length)),
            )
          : AppBar(title: Text(l10n.timelineTab)),
      body: Column(
        children: [
          Expanded(
            child: bucketsAsync.when(
              data: (buckets) {
                if (buckets.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.timelineEmpty,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    _invalidateLibrary();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: buckets.length,
                    itemBuilder: (context, index) => _BucketCard(
                      bucket: buckets[index],
                      selectionMode: _selectionMode,
                      isSelected: (item) => _selection.contains(item.id),
                      onTap: (item, itemIndex, items) {
                        if (_busy) return;
                        if (_selectionMode) {
                          _toggle(item);
                        } else {
                          _openViewer(index, itemIndex, items);
                        }
                      },
                      onLongPress: _enterSelection,
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.errorLoading),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => ref.invalidate(timelineProvider),
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_selectionMode && !_busy)
            MediaActionBar(
              actions: [
                MediaActionButton(
                  icon: Icons.share_outlined,
                  label: l10n.galleryShare,
                  onPressed: _runShare,
                ),
                MediaActionButton(
                  icon: Icons.download,
                  label: l10n.downloadOriginal,
                  onPressed: _runDownload,
                ),
                MediaActionButton(
                  icon: Icons.playlist_add,
                  label: l10n.albumAdd,
                  onPressed: _runAddToAlbum,
                ),
                MediaActionButton(
                  icon: Icons.delete_outline,
                  label: l10n.galleryDelete,
                  onPressed: _runDelete,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BucketCard extends ConsumerWidget {
  final TimelineBucket bucket;
  final bool selectionMode;
  final bool Function(MediaItem item) isSelected;
  final void Function(MediaItem item, int index, List<MediaItem> items) onTap;
  final void Function(MediaItem item) onLongPress;

  const _BucketCard({
    required this.bucket,
    required this.selectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final itemsAsync = ref.watch(
      timelineItemsProvider(
        TimelineQuery(from: bucket.bucketStart, to: bucket.bucketEnd),
      ),
    );
    final icon = switch (bucket.granularity) {
      'day' => Icons.today_outlined,
      'week' => Icons.date_range_outlined,
      _ => Icons.calendar_month_outlined,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  TimelineBucket.labelFor(bucket),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  l10n.itemCount(bucket.count),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 130,
              child: itemsAsync.when(
                data: (page) => page.items.isEmpty
                    ? Center(
                        child: Text(
                          l10n.galleryEmpty,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: page.items.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (context, index) => MediaThumbnail(
                          item: page.items[index],
                          size: 110,
                          selectionMode: selectionMode,
                          selected: isSelected(page.items[index]),
                          onTap: () =>
                              onTap(page.items[index], index, page.items),
                          onLongPress: () => onLongPress(page.items[index]),
                        ),
                      ),
                loading: () => const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (error, stackTrace) =>
                    Center(child: Text(l10n.errorLoading)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
