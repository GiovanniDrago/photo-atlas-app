import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/auto_backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Render right away: the WorkManager setup must never keep the app on the
  // launch screen. If it hangs on some device, the UI is already up.
  runApp(const ProviderScope(child: PhotoAtlasApp()));
  unawaited(_initAutoBackup());
}

Future<void> _initAutoBackup() async {
  try {
    await AutoBackupService.initialize().timeout(const Duration(seconds: 10));
  } catch (_) {}
  try {
    final settings = await AutoBackupService.load();
    if (settings.enabled) {
      await AutoBackupService.apply(
        settings,
      ).timeout(const Duration(seconds: 10));
    }
  } catch (_) {}
}
