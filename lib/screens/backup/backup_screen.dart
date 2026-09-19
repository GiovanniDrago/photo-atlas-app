import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/backup.dart';
import '../../providers/library_providers.dart';
import '../../services/api_client.dart';
import '../../services/backup_service.dart';
import 'upload_picker_screen.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  BackupStatusSnapshot? _status;
  BackupProgress? _progress;
  bool _loading = true;
  bool _running = false;
  bool _verifyMode = false;
  bool _cancelled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    try {
      final snapshot = await ref.read(apiClientProvider).backupStatus();
      if (mounted) {
        setState(() {
          _status = snapshot;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runBackup({String? sourceId}) async {
    setState(() {
      _running = true;
      _verifyMode = false;
      _cancelled = false;
      _progress = const BackupProgress();
      _error = null;
    });
    try {
      final service = BackupService(ref.read(apiClientProvider));
      await service.runBackup(
        sourceId: sourceId,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        isCancelled: () => _cancelled,
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _running = false);
      await _loadStatus();
    }
  }

  Future<void> _runVerify({String? sourceId}) async {
    setState(() {
      _running = true;
      _verifyMode = true;
      _cancelled = false;
      _progress = const BackupProgress();
      _error = null;
    });
    try {
      final service = BackupService(ref.read(apiClientProvider));
      await service.runVerify(
        sourceId: sourceId,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        isCancelled: () => _cancelled,
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _running = false);
      await _loadStatus();
    }
  }

  Future<void> _openPicker() async {
    final uploaded = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const UploadPickerScreen()));
    if (uploaded == true) await _loadStatus();
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
    final status = _status;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.backupTitle),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            onPressed: _running ? null : _loadStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (kIsWeb)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.backupUnavailableWeb),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _running ? null : _openPicker,
                    icon: const Icon(Icons.upload_file),
                    label: Text(l10n.backupUploadFiles),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _running ? null : () => _runBackup(),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(l10n.backupNowAll),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _running ? null : () => _runVerify(),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(l10n.backupVerifyAll),
            ),
          ],
          if (_progress != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _verifyMode
                                ? l10n.backupVerifyRunning
                                : l10n.backupRunning,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (_running)
                          TextButton(
                            onPressed: () => setState(() => _cancelled = true),
                            child: Text(l10n.backupStop),
                          ),
                      ],
                    ),
                    if (_progress!.currentName != null)
                      Text(
                        _progress!.currentName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 8),
                    if (_verifyMode)
                      Text(
                        l10n.backupVerifyCounters(
                          _progress!.verifiedOk,
                          _progress!.verifiedMissing,
                        ),
                      )
                    else
                      Text(
                        l10n.backupCounters(
                          _progress!.uploaded,
                          _progress!.failed,
                          _formatBytes(_progress!.bytes),
                        ),
                      ),
                    if (_running)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 20),
          Text(
            l10n.backupFolders,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (status == null || status.sources.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.backupNoFolders),
              ),
            )
          else
            for (final source in status.sources)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(source.label),
                  subtitle: Text(
                    '${l10n.backupUploadedOf(source.uploaded, source.total)}'
                    '${source.failed > 0 ? ' · ${l10n.backupFailedCount(source.failed)}' : ''}'
                    '${source.backupFolderPath != null ? '\n${source.backupFolderPath}' : ''}',
                  ),
                  isThreeLine: source.backupFolderPath != null,
                  trailing: PopupMenuButton<String>(
                    enabled: !_running,
                    onSelected: (value) {
                      if (value == 'backup') {
                        _runBackup(sourceId: source.id);
                      } else if (value == 'verify') {
                        _runVerify(sourceId: source.id);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'backup',
                        child: Text(l10n.backupNow),
                      ),
                      PopupMenuItem(
                        value: 'verify',
                        child: Text(l10n.backupVerify),
                      ),
                    ],
                  ),
                ),
              ),
          if (status != null) ...[
            const SizedBox(height: 12),
            Text(
              l10n.backupTotals(
                status.uploaded,
                status.total,
                _formatBytes(status.bytesUploaded),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
