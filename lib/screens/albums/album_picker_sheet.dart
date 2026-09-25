import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/album.dart';
import '../../models/gallery_entry.dart';
import '../../providers/album_providers.dart';
import '../../providers/library_providers.dart';
import '../../services/album_actions_service.dart';
import 'album_dialogs.dart';

/// Lists the manual albums and adds the selected entries to one of them (or to
/// a new one). Returns the result, or null when dismissed.
Future<AlbumAddResult?> showAddToAlbumSheet(
  BuildContext context,
  List<GalleryEntry> entries,
) {
  return showModalBottomSheet<AlbumAddResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AlbumPickerSheet(entries: entries),
  );
}

class _AlbumPickerSheet extends ConsumerStatefulWidget {
  final List<GalleryEntry> entries;

  const _AlbumPickerSheet({required this.entries});

  @override
  ConsumerState<_AlbumPickerSheet> createState() => _AlbumPickerSheetState();
}

class _AlbumPickerSheetState extends ConsumerState<_AlbumPickerSheet> {
  bool _busy = false;

  Future<void> _createAndAdd() async {
    final name = await showAlbumNameDialog(context, create: true);
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final client = ref.read(apiClientProvider);
      final resolved = await AlbumActionsService(client)
          .resolveMediaIds(widget.entries);
      await client.createAlbum(name: name, mediaIds: resolved.mediaIds);
      ref.invalidate(albumsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(
        AlbumAddResult(
          added: resolved.mediaIds.length,
          failed: resolved.failed,
          errors: resolved.errors,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _addTo(Album album) async {
    setState(() => _busy = true);
    final result = await AlbumActionsService(ref.read(apiClientProvider))
        .addEntries(albumId: album.id, entries: widget.entries);
    ref.invalidate(albumsProvider);
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final albumsAsync = ref.watch(albumsProvider);
    final albums = albumsAsync.value ?? const <Album>[];
    final manual = albums.where((album) => !album.isSmart).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                l10n.albumAddTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            Flexible(
              child: albumsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('$error', textAlign: TextAlign.center),
                ),
                data: (_) => ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: Text(l10n.albumNew),
                      onTap: _busy ? null : _createAndAdd,
                    ),
                    if (manual.isEmpty)
                      ListTile(
                        enabled: false,
                        leading: const Icon(Icons.info_outline),
                        title: Text(l10n.albumNoManual),
                      ),
                    for (final album in manual)
                      ListTile(
                        leading: const Icon(Icons.photo_album_outlined),
                        title: Text(album.name),
                        subtitle: Text(l10n.itemCount(album.itemCount)),
                        onTap: _busy ? null : () => _addTo(album),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
