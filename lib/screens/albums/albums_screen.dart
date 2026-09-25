import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/album.dart';
import '../../providers/album_providers.dart';
import '../../providers/gallery_providers.dart';
import '../../providers/library_providers.dart';
import '../gallery/gallery_screen.dart';
import 'album_dialogs.dart';
import 'album_edit_screen.dart';

/// Albums tab: grid of manual and smart albums with cover, count and actions.
class AlbumsScreen extends ConsumerWidget {
  const AlbumsScreen({super.key});

  void _openAlbum(BuildContext context, WidgetRef ref, Album album) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GalleryScreen(
              scope: GalleryScope(userAlbumId: album.id),
              album: album,
              showFilters: false,
            ),
          ),
        )
        .then((_) => ref.invalidate(albumsProvider));
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final smart = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_album_outlined),
              title: Text(l10n.albumCreateManual),
              onTap: () => Navigator.of(context).pop(false),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(l10n.albumCreateSmart),
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (smart == null || !context.mounted) return;

    if (smart) {
      final created = await Navigator.of(
        context,
      ).push<Album>(MaterialPageRoute(builder: (_) => const AlbumEditScreen()));
      if (created == null) return;
      ref.invalidate(albumsProvider);
      if (context.mounted) _openAlbum(context, ref, created);
      return;
    }

    final name = await showAlbumNameDialog(context, create: true);
    if (name == null) return;
    try {
      final album = await ref.read(apiClientProvider).createAlbum(name: name);
      ref.invalidate(albumsProvider);
      if (context.mounted) _openAlbum(context, ref, album);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final albumsAsync = ref.watch(albumsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.albumsTab),
        actions: [
          IconButton(
            tooltip: l10n.albumNew,
            onPressed: () => _create(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: albumsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$error'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => ref.invalidate(albumsProvider),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (albums) {
          if (albums.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.albumEmpty, textAlign: TextAlign.center),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(albumsProvider.future),
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              itemCount: albums.length,
              itemBuilder: (context, index) => _AlbumCard(
                album: albums[index],
                onOpen: () => _openAlbum(context, ref, albums[index]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AlbumCard extends ConsumerWidget {
  final Album album;
  final VoidCallback onOpen;

  const _AlbumCard({required this.album, required this.onOpen});

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showAlbumNameDialog(context, initialName: album.name);
    if (name == null || name == album.name) return;
    try {
      await ref.read(apiClientProvider).updateAlbum(album.id, name: name);
      ref.invalidate(albumsProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push<Album>(
      MaterialPageRoute(builder: (_) => AlbumEditScreen(album: album)),
    );
    ref.invalidate(albumsProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    if (!await showAlbumDeleteDialog(context, album)) return;
    try {
      await ref.read(apiClientProvider).deleteAlbum(album.id);
      ref.invalidate(albumsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.albumDeleted)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final cover = album.cover;
    final client = ref.watch(apiClientProvider);
    final url = cover == null
        ? ''
        : (cover.thumbnailUrl ?? client.thumbnailUrl(cover.id));
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover == null)
              Container(
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.photo_album_outlined,
                  size: 40,
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (context, url) =>
                    Container(color: scheme.surfaceContainerHighest),
                errorWidget: (context, url, error) => Container(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.photo_album_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                  stops: [0.45, 1],
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  album.isSmart ? l10n.albumKindSmart : l10n.albumKindManual,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) {
                  if (value == 'rename') {
                    _rename(context, ref);
                  } else if (value == 'edit') {
                    _edit(context, ref);
                  } else if (value == 'delete') {
                    _delete(context, ref);
                  }
                },
                itemBuilder: (context) => [
                  if (album.isSmart)
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
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    l10n.itemCount(album.itemCount),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
