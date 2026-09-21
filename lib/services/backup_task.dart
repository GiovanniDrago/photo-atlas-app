import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../providers/settings_provider.dart';
import 'api_client.dart';
import 'auto_backup_service.dart';
import 'backup_service.dart';
import 'device_service.dart';
import 'local_scan_service.dart';
import 'scan_service.dart';
import 'supabase_bootstrap.dart';

@pragma('vm:entry-point')
void backupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != AutoBackupService.taskName) return true;
    try {
      await runAutoBackup();
      return true;
    } catch (error) {
      debugPrint('auto backup failed: $error');
      return false;
    }
  });
}

Future<void> runAutoBackup({
  Duration budget = const Duration(minutes: 8),
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AutoBackupService.load();
  if (!settings.enabled) return;

  final prefs = await SharedPreferences.getInstance();
  final baseUrl =
      prefs.getString('api_base_url') ?? platformDefaultApiBaseUrl();
  final config = await ApiClient(baseUrl).apiConfig();
  await SupabaseBootstrap.ensure(config);
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) {
    debugPrint('auto backup skipped: no session');
    return;
  }
  final client = ApiClient(baseUrl, token: session.accessToken);
  final scanner = LocalScanService(client);
  final sources = await scanner.autoBackupSources();
  if (sources.isEmpty) return;

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
  bool expired() => DateTime.now().isAfter(deadline);

  for (final source in sources) {
    if (expired()) break;
    final rootPath = source.rootPath;
    if (rootPath != null && ScanService.isSupported) {
      try {
        final result = await scanner.scanSource(
          sourceId: source.id,
          rootPath: rootPath,
        );
        debugPrint(
          'auto backup: ${source.label} scanned '
          '(${result.indexed}/${result.filesSeen} indexed)',
        );
      } catch (error) {
        debugPrint('auto backup: scan failed for ${source.label}: $error');
      }
    }
    if (expired()) break;
    try {
      await backup.runBackup(
        sourceId: source.id,
        onProgress: (_) {},
        isCancelled: expired,
      );
    } catch (error) {
      debugPrint('auto backup: uploads failed for ${source.label}: $error');
    }
  }
  debugPrint('auto backup done (device $deviceId)');
}
