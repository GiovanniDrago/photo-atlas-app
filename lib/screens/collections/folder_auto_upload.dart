import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../models/backup.dart';
import '../../models/source.dart';
import '../../providers/backup_runner_provider.dart';
import '../../providers/collections_providers.dart';
import '../../providers/library_providers.dart';
import '../../services/auto_backup_service.dart';
import '../../services/device_service.dart';
import '../../services/local_scan_service.dart';
import '../../services/scan_service.dart';

/// Enables the automatic upload of a device folder. Turning it on indexes the
/// folder (scan + database census) and uploads everything it contains, without
/// subfolders, in a foreground service that keeps running while the app is in
/// the background. The background job then keeps checking the same sources.
class FolderAutoUploadSwitch extends ConsumerStatefulWidget {
  final String albumId;
  final String label;
  final String rootPath;
  final bool showStatus;

  const FolderAutoUploadSwitch({
    super.key,
    required this.albumId,
    required this.label,
    required this.rootPath,
    this.showStatus = true,
  });

  @override
  ConsumerState<FolderAutoUploadSwitch> createState() =>
      _FolderAutoUploadSwitchState();
}

class _FolderAutoUploadSwitchState
    extends ConsumerState<FolderAutoUploadSwitch> {
  bool _preparing = false;

  MediaSource? _matchedSource(List<MediaSource> sources) {
    return matchSourceForFolder(
      albumId: widget.albumId,
      folderName: widget.label,
      sources: sources,
    );
  }

  BackupSourceStatus? _statusFor(String? sourceId) {
    if (sourceId == null) return null;
    final snapshot = ref.watch(backupStatusProvider).value;
    if (snapshot == null) return null;
    for (final source in snapshot.sources) {
      if (source.id == sourceId) return source;
    }
    return null;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggle(bool value, MediaSource? matched) async {
    final client = ref.read(apiClientProvider);
    setState(() => _preparing = true);
    try {
      if (!value) {
        if (matched != null) {
          await client.updateSource(matched.id, autoBackup: false);
        }
        return;
      }
      final deviceId = await DeviceService.ensureRegistered(client);
      final sourceId =
          matched?.id ??
          await LocalScanService(client).ensureAlbumSource(
            albumId: widget.albumId,
            label: widget.label,
            deviceId: deviceId,
          );
      await client.updateSource(sourceId, autoBackup: true);
      await _maybeEnableBackground();
      if (!mounted) return;
      final started = await ref
          .read(backupRunnerProvider.notifier)
          .enqueue(
            sourceId: sourceId,
            label: widget.label,
            rootPath: matched?.rootPath ?? widget.rootPath,
          );
      if (!started && mounted) await _showPermissionDialog();
    } catch (error) {
      _snack('$error');
    } finally {
      if (mounted) setState(() => _preparing = false);
      ref.invalidate(sourcesProvider);
    }
  }

  Future<void> _showPermissionDialog() async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.backupNoPermission),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await ScanService.openSettings();
              } catch (_) {}
            },
            child: Text(l10n.galleryOpenSettings),
          ),
        ],
      ),
    );
  }

  Future<void> _maybeEnableBackground() async {
    final settings = await AutoBackupService.load();
    if (settings.enabled || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final enable = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.folderEnableBackgroundTitle),
        content: Text(l10n.folderEnableBackgroundBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.later),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.activate),
          ),
        ],
      ),
    );
    if (enable != true) return;
    try {
      await Permission.notification.request();
    } catch (_) {}
    final updated = settings.copyWith(enabled: true);
    await AutoBackupService.save(updated);
    await AutoBackupService.apply(updated);
  }

  String _statusLine(AppLocalizations l10n, BackupSourceStatus status) {
    final parts = <String>[
      l10n.folderUploadedOf(status.uploaded, status.total),
      if (status.failed > 0) l10n.backupFailedCount(status.failed),
      if (status.backupLastRunAt != null)
        l10n.autoBackupLastRun(
          DateFormat('yyyy-MM-dd HH:mm').format(status.backupLastRunAt!),
        ),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final sources = ref.watch(sourcesProvider).value ?? const <MediaSource>[];
    final matched = _matchedSource(sources);
    final status = _statusFor(matched?.id);
    final runner = ref.watch(backupRunnerProvider);
    final runningForThisFolder =
        matched != null && runner.progress?.sourceId == matched.id;

    if (runningForThisFolder) {
      final progress = runner.progress!;
      final total = progress.total;
      final done = progress.done;
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              progress.scanning ? l10n.folderScanning : l10n.folderUploading,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: total == 0 ? null : (done / total).clamp(0.0, 1.0),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.folderAutoUpload,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (_preparing)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Tooltip(
                message: l10n.folderAutoUploadKeep,
                child: Switch(
                  value: matched?.autoBackup ?? false,
                  onChanged: (value) => _toggle(value, matched),
                ),
              ),
          ],
        ),
        if (widget.showStatus && status != null)
          Text(
            _statusLine(l10n, status),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}
