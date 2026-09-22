import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gallery_entry.dart';
import '../../models/source.dart';
import '../../providers/collections_providers.dart';
import '../../providers/gallery_providers.dart';
import '../../providers/library_providers.dart';
import '../../services/scan_models.dart';
import '../../services/scan_service.dart';
import '../gallery/gallery_screen.dart';
import '../timeline/timeline_screen.dart';
import 'folder_auto_upload.dart';

class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final foldersAsync = ref.watch(deviceFoldersProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.collectionsTab),
        actions: [
          IconButton(
            tooltip: l10n.retry,
            onPressed: () {
              ref.invalidate(deviceFoldersProvider);
              ref.invalidate(recentPreviewProvider);
              ref.invalidate(backupStatusProvider);
              ref.invalidate(folderThumbProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(deviceFoldersProvider);
          ref.invalidate(recentPreviewProvider);
          ref.invalidate(backupStatusProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const _TimelineCard(),
            const SizedBox(height: 16),
            Text(
              l10n.collectionsFolders,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.collectionsFoldersHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ..._folders(context, ref, foldersAsync, l10n),
          ],
        ),
      ),
    );
  }

  List<Widget> _folders(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<ScanFolder>> foldersAsync,
    AppLocalizations l10n,
  ) {
    if (!ScanService.isSupported) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            l10n.collectionsLocalUnavailable,
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    return foldersAsync.when(
      data: (folders) => folders.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(l10n.collectionsEmpty, textAlign: TextAlign.center),
              ),
            ]
          : [for (final folder in folders) _FolderCard(folder: folder)],
      loading: () => const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (error, stackTrace) => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Text(
                error is ScanPermissionException
                    ? l10n.localPermissionDenied
                    : l10n.errorLoading,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (error is ScanPermissionException)
                FilledButton(
                  onPressed: () async {
                    try {
                      await ScanService.openSettings();
                    } catch (_) {}
                    ref.invalidate(deviceFoldersProvider);
                  },
                  child: Text(l10n.galleryOpenSettings),
                )
              else
                FilledButton(
                  onPressed: () => ref.invalidate(deviceFoldersProvider),
                  child: Text(l10n.retry),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Big card at the top: preview of the newest photos, opens the timeline.
class _TimelineCard extends ConsumerWidget {
  const _TimelineCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final previewAsync = ref.watch(recentPreviewProvider);
    final entries = previewAsync.value ?? const <GalleryEntry>[];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const TimelineScreen())),
        child: SizedBox(
          height: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (entries.isEmpty)
                ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Center(
                    child: previewAsync.isLoading
                        ? const CircularProgressIndicator()
                        : Icon(
                            Icons.timeline,
                            size: 42,
                            color: scheme.onSurfaceVariant,
                          ),
                  ),
                )
              else
                _PreviewCollage(entries: entries),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.65),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timeline, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.collectionsTimelineTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              l10n.collectionsTimelineSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewCollage extends StatelessWidget {
  final List<GalleryEntry> entries;

  const _PreviewCollage({required this.entries});

  @override
  Widget build(BuildContext context) {
    final items = entries.take(4).toList();
    return Row(
      children: [
        for (var index = 0; index < items.length; index += 1)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == items.length - 1 ? 0 : 2,
              ),
              child: _PreviewImage(entry: items[index]),
            ),
          ),
      ],
    );
  }
}

class _PreviewImage extends ConsumerWidget {
  final GalleryEntry entry;

  const _PreviewImage({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = entry.local?.asset;
    if (asset != null) {
      return AssetEntityImage(
        asset,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize.square(360),
        thumbnailFormat: ThumbnailFormat.jpeg,
        fit: BoxFit.cover,
      );
    }
    final url =
        entry.thumbnailUrl ??
        (entry.cloud == null
            ? null
            : ref.watch(apiClientProvider).thumbnailUrl(entry.cloud!.id));
    if (url == null || url.isEmpty) {
      return ColoredBox(color: Theme.of(context).colorScheme.surfaceContainer);
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (context, url, error) =>
          ColoredBox(color: Theme.of(context).colorScheme.surfaceContainer),
    );
  }
}

class _FolderCard extends ConsumerWidget {
  final ScanFolder folder;

  const _FolderCard({required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FolderGalleryScreen(folder: folder),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _FolderThumb(folder: folder),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          '${folder.path} · ${l10n.itemCount(folder.count)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 4),
              FolderAutoUploadSwitch(
                albumId: folder.id,
                label: folder.name,
                rootPath: 'album:${folder.id}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Folder gallery: the scope follows the matched source, so the cloud side
/// appears as soon as the folder is indexed.
class FolderGalleryScreen extends ConsumerWidget {
  final ScanFolder folder;

  const FolderGalleryScreen({super.key, required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider).value ?? const <MediaSource>[];
    final matched = matchSourceForFolder(
      albumId: folder.id,
      folderName: folder.name,
      sources: sources,
    );
    return GalleryScreen(
      scope: GalleryScope(sourceId: matched?.id, albumId: folder.id),
      title: folder.name,
      showFilters: false,
      header: _FolderHeader(folder: folder),
    );
  }
}

class _FolderThumb extends ConsumerWidget {
  final ScanFolder folder;

  const _FolderThumb({required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: Builder(
          builder: (context) {
            final assets =
                ref.watch(folderThumbProvider(folder.id)).value ?? const [];
            if (assets.isEmpty) {
              return ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.folder_outlined,
                  color: scheme.onSurfaceVariant,
                ),
              );
            }
            return AssetEntityImage(
              assets.first,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize.square(200),
              thumbnailFormat: ThumbnailFormat.jpeg,
              fit: BoxFit.cover,
            );
          },
        ),
      ),
    );
  }
}

/// Folder header inside the folder gallery: name, path, count and the toggle.
class _FolderHeader extends StatelessWidget {
  final ScanFolder folder;

  const _FolderHeader({required this.folder});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${folder.path} · ${l10n.itemCount(folder.count)}',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          FolderAutoUploadSwitch(
            albumId: folder.id,
            label: folder.name,
            rootPath: 'album:${folder.id}',
          ),
          const Divider(height: 16),
        ],
      ),
    );
  }
}
