import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../models/backup.dart';
import '../../models/source.dart';
import '../../providers/collections_providers.dart';
import '../../providers/gallery_providers.dart';
import '../../providers/library_providers.dart';
import '../../services/auto_backup_service.dart';
import '../../services/backup_service.dart';
import '../../services/device_service.dart';
import '../../services/local_scan_service.dart';

/// Enables the automatic upload of a device folder. Turning it on indexes the
/// folder (scan + database census) and uploads everything it contains, without
/// subfolders. The background job then keeps checking the same sources.
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
  bool _busy = false;
  String? _busyLabel;
  double? _progress;

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

  Future<void> _toggle(bool value, MediaSource? matched) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _busyLabel = value ? l10n.folderScanning : null;
      _progress = null;
    });
    final client = ref.read(apiClientProvider);
    try {
      if (!value) {
        if (matched != null) {
          await client.updateSource(matched.id, autoBackup: false);
        }
        return;
      }
      final deviceId = await DeviceService.ensureRegistered(client);
      final scanner = LocalScanService(client);
      final sourceId =
          matched?.id ??
          await scanner.ensureAlbumSource(
            albumId: widget.albumId,
            label: widget.label,
            deviceId: deviceId,
          );
      await client.updateSource(sourceId, autoBackup: true);
      await _maybeEnableBackground();

      final rootPath = matched?.rootPath ?? widget.rootPath;
      await scanner.scanSource(
        sourceId: sourceId,
        rootPath: rootPath,
        onProgress: (seen, indexed) {
          if (mounted) setState(() => _busyLabel = l10n.folderScanning);
        },
      );
      if (!mounted) return;
      setState(() => _busyLabel = l10n.folderUploading);
      await BackupService(client).runBackup(
        sourceId: sourceId,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _busyLabel = l10n.folderUploading;
            _progress = progress.total == 0
                ? null
                : ((progress.uploaded + progress.failed) / progress.total)
                      .clamp(0.0, 1.0);
          });
        },
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
          _progress = null;
        });
      }
      _invalidate();
    }
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
    await AutoBackupService.save(settings.copyWith(enabled: true));
    await AutoBackupService.apply(settings.copyWith(enabled: true));
  }

  void _invalidate() {
    ref.invalidate(sourcesProvider);
    ref.invalidate(backupStatusProvider);
    ref.invalidate(deviceFoldersProvider);
    ref.invalidate(galleryProvider);
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
            if (_busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(
                value: matched?.autoBackup ?? false,
                onChanged: (value) => _toggle(value, matched),
              ),
          ],
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _busyLabel ?? '',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: _progress),
              ],
            ),
          )
        else if (widget.showStatus && status != null)
          Text(
            _statusLine(l10n, status),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}
