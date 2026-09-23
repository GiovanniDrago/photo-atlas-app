import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../providers/settings_provider.dart';
import 'api_client.dart';
import 'auto_backup_service.dart';
import 'backup_progress_store.dart';
import 'backup_service.dart';
import 'device_service.dart';
import 'local_scan_service.dart';
import 'scan_service.dart';
import 'supabase_bootstrap.dart';

@pragma('vm:entry-point')
void backupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != AutoBackupService.taskName) return true;
    final sourceId = inputData?['source_id'] as String?;
    final manual = inputData?['manual'] == true;
    final label = inputData?['label'] as String?;
    try {
      await BackupRunLog.add(
        'job avviato (${manual ? 'manuale' : 'periodico'}'
        '${sourceId == null ? '' : ', sorgente $sourceId'})',
      );
      await runAutoBackup(sourceId: sourceId, manual: manual, label: label);
      return true;
    } catch (error) {
      debugPrint('auto backup failed: $error');
      await BackupRunLog.add('errore: $error');
      final progress =
          await BackupProgressStore.read() ??
          BackupRunProgress(sourceId: sourceId, label: label);
      await BackupProgressStore.write(
        progress.copyWith(
          error: '$error',
          finishedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      return false;
    }
  });
}

/// Runs the backup of the enabled sources. Manual runs (started from the
/// collections folder switch) target a single source and do not require the
/// periodic schedule to be enabled.
Future<void> runAutoBackup({
  Duration budget = const Duration(minutes: 30),
  String? sourceId,
  bool manual = false,
  String? label,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  /// Closes the run so the in-app banner never stays on "waiting".
  Future<void> finish({String? error}) async {
    final current =
        await BackupProgressStore.read() ??
        BackupRunProgress(sourceId: sourceId, label: label);
    await BackupProgressStore.write(
      current.copyWith(
        error: error,
        finishedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  final settings = await AutoBackupService.load();
  if (!manual && !settings.enabled) {
    await BackupRunLog.add('job periodico saltato: automatico disattivato');
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final baseUrl =
      prefs.getString('api_base_url') ?? platformDefaultApiBaseUrl();
  await BackupRunLog.add('server: $baseUrl');
  final config = await ApiClient(baseUrl).apiConfig();
  await SupabaseBootstrap.ensure(config);
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) {
    debugPrint('auto backup skipped: no session');
    await BackupRunLog.add('nessuna sessione Supabase nel job');
    await finish(error: 'no_session');
    return;
  }
  final client = ApiClient(baseUrl, token: session.accessToken);
  final scanner = LocalScanService(client);
  final sources = manual
      ? [
          for (final source in await client.sources())
            if (sourceId == null || source.id == sourceId) source,
        ]
      : await scanner.autoBackupSources();
  if (sources.isEmpty) {
    debugPrint('auto backup: nothing to do');
    await BackupRunLog.add('nessuna cartella da processare');
    await finish();
    return;
  }

  if (ScanService.isSupported) {
    try {
      PhotoManager.setIgnorePermissionCheck(true);
    } catch (error) {
      debugPrint('auto backup: permission check override failed: $error');
    }
  }

  final deviceId = await DeviceService.ensureRegistered(client);
  final backup = BackupService(client);
  final deadline = DateTime.now().add(budget);
  var cancelled = false;
  await BackupProgressStore.clearCancel();
  final watcher = Timer.periodic(const Duration(seconds: 2), (_) async {
    if (await BackupProgressStore.cancelRequested()) cancelled = true;
  });
  bool stop() => cancelled || DateTime.now().isAfter(deadline);

  try {
    for (final source in sources) {
      if (stop()) break;
      var progress = BackupRunProgress(
        sourceId: source.id,
        label: source.label,
        phase: 'scanning',
        startedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await BackupProgressStore.write(progress);
      await BackupRunLog.add('scansione: ${source.label}');
      final rootPath = source.rootPath;
      if (rootPath != null && ScanService.isSupported) {
        try {
          final scan = await scanner.scanSource(
            sourceId: source.id,
            rootPath: rootPath,
            isCancelled: stop,
            onProgress: (seen, indexed) {
              progress = progress.copyWith(total: seen);
              unawaited(BackupProgressStore.write(progress));
            },
          );
          await BackupRunLog.add(
            'scansione completata: ${source.label} (${scan.filesSeen} file)',
          );
        } catch (error) {
          debugPrint('auto backup: scan failed for ${source.label}: $error');
          await BackupRunLog.add('scansione fallita: $error');
        }
      }
      if (stop()) break;
      progress = progress.copyWith(
        phase: 'uploading',
        uploaded: 0,
        failed: 0,
        total: 0,
      );
      await BackupProgressStore.write(progress);
      try {
        await backup.runBackup(
          sourceId: source.id,
          isCancelled: stop,
          onProgress: (value) {
            progress = progress.copyWith(
              uploaded: value.uploaded,
              failed: value.failed,
              total: value.total,
              currentName: value.currentName,
            );
            unawaited(BackupProgressStore.write(progress));
          },
        );
        await BackupRunLog.add('upload completato: ${source.label}');
      } catch (error) {
        debugPrint('auto backup: uploads failed for ${source.label}: $error');
        await BackupRunLog.add('upload fallito: $error');
      }
    }
  } finally {
    watcher.cancel();
    await finish();
  }
  debugPrint('auto backup done (device $deviceId)');
}
