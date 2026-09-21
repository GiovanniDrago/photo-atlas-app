import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../l10n/app_localizations.dart';
import 'backup_task.dart';

class AutoBackupSettings {
  static const int defaultIntervalMinutes = 360;
  static const List<int> intervalOptions = [15, 60, 360, 1440];

  final bool enabled;
  final int intervalMinutes;
  final bool wifiOnly;
  final bool chargingOnly;

  const AutoBackupSettings({
    this.enabled = false,
    this.intervalMinutes = defaultIntervalMinutes,
    this.wifiOnly = true,
    this.chargingOnly = false,
  });

  AutoBackupSettings copyWith({
    bool? enabled,
    int? intervalMinutes,
    bool? wifiOnly,
    bool? chargingOnly,
  }) {
    return AutoBackupSettings(
      enabled: enabled ?? this.enabled,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      chargingOnly: chargingOnly ?? this.chargingOnly,
    );
  }
}

class AutoBackupService {
  static const String uniqueName = 'photo-atlas-auto-backup';
  static const String taskName = 'photoAtlasAutoBackup';
  static const String _enabledKey = 'auto_backup_enabled';
  static const String _intervalKey = 'auto_backup_interval_minutes';
  static const String _wifiKey = 'auto_backup_wifi_only';
  static const String _chargingKey = 'auto_backup_charging_only';

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initialize() async {
    if (!isSupported) return;
    try {
      await Workmanager().initialize(backupCallbackDispatcher);
    } catch (error) {
      debugPrint('workmanager initialization failed: $error');
    }
  }

  static Future<AutoBackupSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AutoBackupSettings(
      enabled: prefs.getBool(_enabledKey) ?? false,
      intervalMinutes:
          prefs.getInt(_intervalKey) ??
          AutoBackupSettings.defaultIntervalMinutes,
      wifiOnly: prefs.getBool(_wifiKey) ?? true,
      chargingOnly: prefs.getBool(_chargingKey) ?? false,
    );
  }

  static Future<void> save(AutoBackupSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, settings.enabled);
    await prefs.setInt(_intervalKey, settings.intervalMinutes);
    await prefs.setBool(_wifiKey, settings.wifiOnly);
    await prefs.setBool(_chargingKey, settings.chargingOnly);
  }

  static Future<void> apply(AutoBackupSettings settings) async {
    if (!isSupported) return;
    if (!settings.enabled) {
      await Workmanager().cancelByUniqueName(uniqueName);
      return;
    }
    final l10n = await _localizations();
    await Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: Duration(minutes: settings.intervalMinutes),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        networkType: settings.wifiOnly
            ? NetworkType.unmetered
            : NetworkType.connected,
        requiresCharging: settings.chargingOnly,
      ),
      foregroundServiceConfig: ForegroundServiceConfig(
        notificationTitle: l10n.autoBackupNotificationTitle,
        notificationText: l10n.autoBackupNotificationText,
        notificationChannelId: 'photo_atlas_backup',
        notificationChannelName: l10n.autoBackupTitle,
        notificationId: 7001,
        foregroundServiceType: ForegroundServiceType.dataSync,
      ),
    );
  }

  static Future<bool> isScheduled() async {
    if (!isSupported) return false;
    try {
      return await Workmanager().isScheduledByUniqueName(uniqueName);
    } catch (_) {
      return false;
    }
  }

  static Future<AppLocalizations> _localizations() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('locale') == 'it' ? 'it' : 'en';
    return lookupAppLocalizations(Locale(code));
  }
}
