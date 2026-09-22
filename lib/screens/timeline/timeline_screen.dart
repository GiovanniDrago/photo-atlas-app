import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gallery_entry.dart';
import '../../models/timeline_bucket.dart';
import '../../providers/library_providers.dart';
import '../../widgets/media_thumbnail.dart';
import '../gallery/media_viewer_screen.dart';

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final bucketsAsync = ref.watch(timelineProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.timelineTab)),
      body: bucketsAsync.when(
        data: (buckets) {
          if (buckets.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.timelineEmpty, textAlign: TextAlign.center),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(timelineProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: buckets.length,
              itemBuilder: (context, index) =>
                  _BucketCard(bucket: buckets[index]),
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
    );
  }
}

class _BucketCard extends ConsumerWidget {
  final TimelineBucket bucket;

  const _BucketCard({required this.bucket});

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
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MediaViewerScreen(
                                entries: [
                                  for (final item in page.items)
                                    GalleryEntry(cloud: item),
                                ],
                                initialIndex: index,
                              ),
                            ),
                          ),
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
