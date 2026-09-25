import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/gallery_entry.dart';

class DeleteMediaOptions {
  final bool cloud;
  final bool local;

  /// Removes the album relation only (files stay); album detail only.
  final bool album;

  const DeleteMediaOptions({
    required this.cloud,
    required this.local,
    this.album = false,
  });
}

/// Asks every time what to delete: the cloud copy (kDrive trash), the device
/// file, or both. Options that do not apply are disabled. [allowAlbum] adds the
/// "from the album" relation-only option (manual albums).
Future<DeleteMediaOptions?> showDeleteMediaDialog(
  BuildContext context,
  List<GalleryEntry> entries, {
  bool allowAlbum = false,
}) {
  return showDialog<DeleteMediaOptions>(
    context: context,
    builder: (context) =>
        DeleteMediaDialog(entries: entries, allowAlbum: allowAlbum),
  );
}

class DeleteMediaDialog extends StatefulWidget {
  final List<GalleryEntry> entries;
  final bool allowAlbum;

  const DeleteMediaDialog({
    super.key,
    required this.entries,
    this.allowAlbum = false,
  });

  @override
  State<DeleteMediaDialog> createState() => _DeleteMediaDialogState();
}

class _DeleteMediaDialogState extends State<DeleteMediaDialog> {
  late bool _cloud;
  late bool _local;
  bool _album = false;

  bool get _canCloud => widget.entries.any((entry) => entry.canDeleteCloud);
  bool get _canLocal => widget.entries.any((entry) => entry.canDeleteLocal);
  bool get _canAlbum =>
      widget.allowAlbum && widget.entries.any((entry) => entry.cloud != null);

  @override
  void initState() {
    super.initState();
    _cloud = _canCloud;
    _local = _canLocal;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nothingSelected = !_cloud && !_local && !_album;
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
          if (widget.allowAlbum)
            CheckboxListTile(
              value: _album,
              onChanged: _canAlbum
                  ? (value) => setState(() => _album = value ?? false)
                  : null,
              title: Text(l10n.albumDeleteFromAlbum),
              subtitle: Text(l10n.albumDeleteFromAlbumHint),
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
              : () => Navigator.of(context).pop(
                  DeleteMediaOptions(
                    cloud: _cloud,
                    local: _local,
                    album: _album,
                  ),
                ),
          child: Text(l10n.galleryDeleteConfirm),
        ),
      ],
    );
  }
}
