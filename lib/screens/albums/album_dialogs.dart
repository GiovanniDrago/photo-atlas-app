import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/album.dart';

/// Rename (or name) dialog shared by the album screens. Returns the trimmed
/// name or null when cancelled.
Future<String?> showAlbumNameDialog(
  BuildContext context, {
  String? initialName,
  bool create = false,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController(text: initialName ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(create ? l10n.albumNew : l10n.albumRename),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 120,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: l10n.albumNameLabel),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.isEmpty) return null;
  return name;
}

Future<bool> showAlbumDeleteDialog(BuildContext context, Album album) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.albumDeleteTitle),
      content: Text(l10n.albumDeleteBody(album.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.albumDelete),
        ),
      ],
    ),
  );
  return confirmed == true;
}
