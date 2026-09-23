import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';

import '../../l10n/app_localizations.dart';
import '../../models/media_item.dart';
import '../../providers/backup_runner_provider.dart';
import '../../providers/collections_providers.dart';
import '../../services/auto_backup_service.dart';
import 'backup_screen.dart';

Future<void> showBackupRunSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _BackupRunSheet(),
  );
}

class _BackupRunSheet extends ConsumerStatefulWidget {
  const _BackupRunSheet();

  @override
  ConsumerState<_BackupRunSheet> createState() => _BackupRunSheetState();
}

class _BackupRunSheetState extends ConsumerState<_BackupRunSheet> {
  Future<WorkInfo?>? _workInfo;

  @override
  void initState() {
    super.initState();
    if (AutoBackupService.isSupported) {
      _workInfo = Workmanager().getWorkInfo(AutoBackupService.manualUniqueName);
    }
  }

  String _workStateLabel(AppLocalizations l10n, WorkInfo? info) {
    if (info == null) return l10n.backupStateNone;
    switch (info.state) {
      case WorkState.scheduled:
        return l10n.backupStateScheduled;
      case WorkState.running:
        return l10n.backupStateRunning;
      case WorkState.succeeded:
        return l10n.backupStateSucceeded;
      case WorkState.failed:
        return l10n.backupStateFailed;
      case WorkState.cancelled:
        return l10n.backupStateCancelled;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(backupRunnerProvider);
    final progress = state.progress;
    final sourceId = progress?.sourceId;
    final pendingAsync = sourceId == null
        ? null
        : ref.watch(backupPendingPreviewProvider(sourceId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ListView(
          shrinkWrap: true,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_upload_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.backupSheetTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            if (!state.active)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(l10n.backupSheetIdle),
              )
            else ...[
              Text(
                '${progress?.scanning == true ? l10n.folderScanning : l10n.folderUploading}'
                ' · ${progress?.label ?? state.queue.first.label}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: (progress?.total ?? 0) == 0
                    ? null
                    : ((progress?.done ?? 0) / progress!.total).clamp(0.0, 1.0),
              ),
              const SizedBox(height: 4),
              Text(
                '${progress?.done ?? 0}/${progress?.total ?? 0}'
                '${(progress?.failed ?? 0) > 0 ? ' · ${l10n.backupFailedCount(progress!.failed)}' : ''}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if ((progress?.error ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: scheme.onErrorContainer,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${l10n.backupSheetError}: ${progress!.error}',
                          style: TextStyle(
                            color: scheme.onErrorContainer,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (state.waitingTooLong) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: scheme.onErrorContainer,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.backupBannerFailed,
                              style: TextStyle(
                                color: scheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.backupBannerBatteryHint,
                        style: TextStyle(
                          color: scheme.onErrorContainer,
                          fontSize: 12,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () async {
                            try {
                              await Permission.ignoreBatteryOptimizations
                                  .request();
                            } catch (_) {}
                          },
                          child: Text(l10n.backupDisableBattery),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FutureBuilder<WorkInfo?>(
                      future: _workInfo,
                      builder: (context, snapshot) => Text(
                        '${l10n.backupJobState}: '
                        '${_workStateLabel(l10n, snapshot.data)}'
                        ' · ${l10n.backupJobStateLast}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh, size: 16),
                    onPressed: AutoBackupService.isSupported
                        ? () => setState(() {
                            _workInfo = Workmanager().getWorkInfo(
                              AutoBackupService.manualUniqueName,
                            );
                          })
                        : null,
                  ),
                ],
              ),
              if (state.queue.length > 1) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.backupQueueCount(state.queue.length - 1),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
              const SizedBox(height: 12),
              if (sourceId != null && pendingAsync != null) ...[
                Text(
                  l10n.backupSheetFiles,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                if (progress?.scanning == true)
                  Text(
                    l10n.backupSheetScanning,
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  pendingAsync.when(
                    data: (page) {
                      final bytes = page.items.fold<int>(
                        0,
                        (sum, item) => sum + (item.sizeBytes ?? 0),
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${l10n.backupSheetFilesCount(page.total, _formatBytes(bytes))}'
                            '\n${l10n.backupSheetScanNote}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          for (final item in page.items)
                            _PendingRow(item: item, formatBytes: _formatBytes),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    ),
                    error: (error, stackTrace) => Text(
                      l10n.errorLoading,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  l10n.backupSheetLog,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                children: [
                  for (final line in state.log.reversed)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: progress != null
                        ? null
                        : () async {
                            await ref
                                .read(backupRunnerProvider.notifier)
                                .runNow();
                            if (context.mounted) Navigator.of(context).pop();
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l10n.backupNow),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => ref
                        .read(backupRunnerProvider.notifier)
                        .retryBackground(),
                    icon: const Icon(Icons.cloud_queue),
                    label: Text(l10n.backupRetryBackground),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(backupRunnerProvider.notifier).cancel(),
                    icon: const Icon(Icons.stop),
                    label: Text(l10n.cancel),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const BackupScreen()),
                    );
                  },
                  child: Text(l10n.backupOpenScreen),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  final MediaItem item;
  final String Function(int bytes) formatBytes;

  const _PendingRow({required this.item, required this.formatBytes});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = item.thumbnailUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 40,
              height: 40,
              child: url == null || url.isEmpty
                  ? ColoredBox(color: scheme.surfaceContainerHighest)
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          ColoredBox(color: scheme.surfaceContainerHighest),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.sizeBytes == null ? '' : formatBytes(item.sizeBytes!),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
