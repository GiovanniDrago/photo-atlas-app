import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/gallery_entry.dart';
import '../models/gallery_upload.dart';

/// Live upload detail: overall progress, per-file state and a stop button.
/// Opened by tapping the bottom progress bar while an upload is running.
Future<void> showUploadProgressSheet(
  BuildContext context, {
  required ValueListenable<GalleryUploadState?> state,
  required VoidCallback onStop,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => UploadProgressSheet(state: state, onStop: onStop),
  );
}

class UploadProgressSheet extends StatelessWidget {
  final ValueListenable<GalleryUploadState?> state;
  final VoidCallback onStop;

  const UploadProgressSheet({
    super.key,
    required this.state,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<GalleryUploadState?>(
      valueListenable: state,
      builder: (context, run, _) {
        if (run == null) return const SizedBox.shrink();
        final value = run.overallFraction;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    run.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          run.running
                              ? (run.currentName ?? '')
                              : _summary(l10n, run),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${run.done}/${run.total}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: value),
                  if (run.running && run.failures.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.backupFailedCount(run.failures.length),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: run.targets.length,
                      itemBuilder: (context, index) => _UploadRow(
                        entry: run.targets[index],
                        status: run.statusAt(index),
                        error: run.failures[index],
                        fileFraction: run.fileFraction,
                        fileSent: run.fileSent,
                        fileTotal: run.fileTotal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (run.running)
                    OutlinedButton.icon(
                      onPressed: run.stopping ? null : onStop,
                      icon: const Icon(Icons.stop),
                      label: Text(
                        run.stopping ? l10n.uploadStopping : l10n.backupStop,
                      ),
                    )
                  else
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.close),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _summary(AppLocalizations l10n, GalleryUploadState run) {
    if (run.cancelled) {
      return '${l10n.uploadStopped} · ${l10n.galleryUploadedCount(run.uploaded)}';
    }
    if (run.failed > 0) {
      return l10n.galleryUploadedFailed(run.uploaded, run.failed);
    }
    return l10n.galleryUploadedCount(run.uploaded);
  }
}

class _UploadRow extends StatelessWidget {
  final GalleryEntry entry;
  final UploadEntryStatus status;
  final String? error;
  final double? fileFraction;
  final int fileSent;
  final int fileTotal;

  const _UploadRow({
    required this.entry,
    required this.status,
    this.error,
    this.fileFraction,
    this.fileSent = 0,
    this.fileTotal = 0,
  });

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget leading = switch (status) {
      UploadEntryStatus.done => Icon(
        Icons.check_circle_outline,
        color: scheme.primary,
      ),
      UploadEntryStatus.current => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      UploadEntryStatus.failed => Icon(
        Icons.error_outline,
        color: scheme.error,
      ),
      UploadEntryStatus.pending => Icon(
        Icons.schedule,
        color: scheme.onSurfaceVariant,
      ),
    };
    final showFileProgress =
        status == UploadEntryStatus.current && fileFraction != null;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: showFileProgress
          ? Text(
              '${(fileFraction! * 100).floor()}%',
              style: Theme.of(context).textTheme.labelMedium,
            )
          : null,
      subtitle: switch (status) {
        UploadEntryStatus.failed when error != null => Text(
          error!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: scheme.error),
        ),
        UploadEntryStatus.current when showFileProgress => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            LinearProgressIndicator(value: fileFraction, minHeight: 2),
            const SizedBox(height: 3),
            Text(
              '${_formatBytes(fileSent)} / ${_formatBytes(fileTotal)}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}
