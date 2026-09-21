import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/auto_backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AutoBackupService.initialize();
  final settings = await AutoBackupService.load();
  if (settings.enabled) {
    try {
      await AutoBackupService.apply(settings);
    } catch (_) {}
  }
  runApp(const ProviderScope(child: PhotoAtlasApp()));
}
