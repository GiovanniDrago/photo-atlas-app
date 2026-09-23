import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../navigation.dart';
import '../providers/backup_runner_provider.dart';
import '../screens/backup/backup_run_sheet.dart';

/// Thin progress bar shown above every screen while a folder backup runs.
class BackupBanner extends ConsumerWidget {
  const BackupBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(backupRunnerProvider);
    if (!state.active) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final progress = state.progress;
    final label = progress?.label ?? l10n.backupBannerStarting;
    final phase = progress == null
        ? l10n.backupBannerStarting
        : progress.scanning
        ? l10n.folderScanning
        : l10n.folderUploading;
    final total = progress?.total ?? 0;
    final done = progress?.done ?? 0;
    final queued = state.queued;
    final stuck = state.waitingTooLong;
    final title = stuck
        ? l10n.backupBannerFailed
        : '$phase · $label${queued > 0 ? ' (+$queued)' : ''}';
    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () {
            final context = appNavigatorKey.currentContext;
            if (context != null) showBackupRunSheet(context);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                Icon(
                  stuck ? Icons.error_outline : Icons.cloud_upload_outlined,
                  size: 18,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: total == 0
                            ? null
                            : (done / total).clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: scheme.onPrimaryContainer.withValues(
                          alpha: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (total > 0 && !stuck)
                  Text(
                    '$done/$total',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                if (stuck)
                  IconButton(
                    tooltip: l10n.backupNow,
                    icon: Icon(
                      Icons.play_arrow,
                      color: scheme.onPrimaryContainer,
                    ),
                    onPressed: () =>
                        ref.read(backupRunnerProvider.notifier).runNow(),
                  ),
                IconButton(
                  tooltip: l10n.backupStop,
                  icon: Icon(Icons.close, color: scheme.onPrimaryContainer),
                  onPressed: () =>
                      ref.read(backupRunnerProvider.notifier).cancel(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
