import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../models/backup.dart';
import '../../providers/library_providers.dart';
import '../../services/api_client.dart';
import '../../services/auto_backup_service.dart';
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
  AutoBackupSettings? _autoBackup;
  bool _loading = true;
  bool _running = false;
  bool _verifyMode = false;
  bool _cancelled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _loadAutoBackup();
  }

  Future<void> _loadAutoBackup() async {
    if (!AutoBackupService.isSupported) return;
    final settings = await AutoBackupService.load();
    if (mounted) setState(() => _autoBackup = settings);
  }

  Future<void> _updateAutoBackup(
    AutoBackupSettings settings, {
    bool justEnabled = false,
  }) async {
    setState(() => _autoBackup = settings);
    await AutoBackupService.save(settings);
    await AutoBackupService.apply(settings);
    if (justEnabled) {
      await _requestNotificationPermission();
      await _maybeEnableAllFolders();
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      if (!status.isGranted && mounted) {
        _snack(AppLocalizations.of(context)!.autoBackupNotificationsOff);
      }
    } catch (_) {}
  }

  Future<void> _maybeEnableAllFolders() async {
    final l10n = AppLocalizations.of(context)!;
    final sources = _status?.sources ?? const <BackupSourceStatus>[];
    if (sources.isEmpty || sources.any((source) => source.autoBackup)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.autoBackupEnableAllTitle),
        content: Text(l10n.autoBackupEnableAllBody(sources.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.kdriveCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.autoBackupEnableAll),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final client = ref.read(apiClientProvider);
    for (final source in sources) {
      try {
        await client.updateSource(source.id, autoBackup: true);
      } catch (_) {}
    }
    await _loadStatus();
  }

  Future<void> _setSourceAutoBackup(
    BackupSourceStatus source,
    bool value,
  ) async {
    try {
      await ref
          .read(apiClientProvider)
          .updateSource(source.id, autoBackup: value);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
    await _loadStatus();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _intervalLabel(AppLocalizations l10n, int minutes) {
    if (minutes < 60) return l10n.autoBackupMinutes(minutes);
    return l10n.autoBackupHours(minutes ~/ 60);
  }

  DateTime? _lastAutoBackupRun() {
    DateTime? latest;
    for (final source in _status?.sources ?? const <BackupSourceStatus>[]) {
      final value = source.backupLastRunAt;
      if (value == null) continue;
      if (latest == null || value.isAfter(latest)) latest = value;
    }
    return latest;
  }

  Widget _autoBackupCard(AppLocalizations l10n) {
    final settings = _autoBackup;
    if (settings == null) return const SizedBox.shrink();
    final lastRun = _lastAutoBackupRun();
    final disabled = _running;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.schedule),
            title: Text(l10n.autoBackupTitle),
            subtitle: Text(l10n.autoBackupSubtitle),
            value: settings.enabled,
            onChanged: disabled
                ? null
                : (value) => _updateAutoBackup(
                    settings.copyWith(enabled: value),
                    justEnabled: value,
                  ),
          ),
          if (settings.enabled) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(l10n.autoBackupInterval),
              trailing: DropdownButton<int>(
                value: settings.intervalMinutes,
                onChanged: disabled
                    ? null
                    : (value) {
                        if (value != null) {
                          _updateAutoBackup(
                            settings.copyWith(intervalMinutes: value),
                          );
                        }
                      },
                items: [
                  for (final minutes in AutoBackupSettings.intervalOptions)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(_intervalLabel(l10n, minutes)),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.wifi),
              title: Text(l10n.autoBackupWifiOnly),
              value: settings.wifiOnly,
              onChanged: disabled
                  ? null
                  : (value) =>
                        _updateAutoBackup(settings.copyWith(wifiOnly: value)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.battery_charging_full),
              title: Text(l10n.autoBackupChargingOnly),
              value: settings.chargingOnly,
              onChanged: disabled
                  ? null
                  : (value) => _updateAutoBackup(
                      settings.copyWith(chargingOnly: value),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  lastRun == null
                      ? l10n.autoBackupNeverRan
                      : l10n.autoBackupLastRun(
                          '${MaterialLocalizations.of(context).formatCompactDate(lastRun)} '
                          '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(lastRun), alwaysUse24HourFormat: true)}',
                        ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
          if (AutoBackupService.isSupported) ...[
            const SizedBox(height: 16),
            _autoBackupCard(l10n),
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
                        !_running &&
                                _progress!.verifiedOk == 0 &&
                                _progress!.verifiedMissing == 0
                            ? l10n.backupNothingToVerify
                            : l10n.backupVerifyCounters(
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (AutoBackupService.isSupported)
                        Tooltip(
                          message: l10n.autoBackupFolderToggle,
                          child: Switch(
                            value: source.autoBackup,
                            onChanged: _running || _autoBackup?.enabled != true
                                ? null
                                : (value) =>
                                      _setSourceAutoBackup(source, value),
                          ),
                        ),
                      PopupMenuButton<String>(
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
