import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Progress of a backup run, written by the background isolate and read by the
/// app (SharedPreferences are visible to both).
class BackupRunProgress {
  final String? sourceId;
  final String? label;
  final String? phase;
  final int uploaded;
  final int failed;
  final int total;
  final String? currentName;
  final int startedAtMs;
  final int? finishedAtMs;
  final String? error;

  const BackupRunProgress({
    this.sourceId,
    this.label,
    this.phase,
    this.uploaded = 0,
    this.failed = 0,
    this.total = 0,
    this.currentName,
    this.startedAtMs = 0,
    this.finishedAtMs,
    this.error,
  });

  bool get finished => finishedAtMs != null;
  bool get scanning => phase == 'scanning';
  int get done => uploaded + failed;

  BackupRunProgress copyWith({
    String? phase,
    int? uploaded,
    int? failed,
    int? total,
    String? currentName,
    int? finishedAtMs,
    String? error,
  }) {
    return BackupRunProgress(
      sourceId: sourceId,
      label: label,
      phase: phase ?? this.phase,
      uploaded: uploaded ?? this.uploaded,
      failed: failed ?? this.failed,
      total: total ?? this.total,
      currentName: currentName ?? this.currentName,
      startedAtMs: startedAtMs,
      finishedAtMs: finishedAtMs ?? this.finishedAtMs,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() => {
    'source_id': sourceId,
    'label': label,
    'phase': phase,
    'uploaded': uploaded,
    'failed': failed,
    'total': total,
    'current_name': currentName,
    'started_at': startedAtMs,
    'finished_at': finishedAtMs,
    'error': error,
  };

  factory BackupRunProgress.fromJson(Map<String, dynamic> json) {
    return BackupRunProgress(
      sourceId: json['source_id'] as String?,
      label: json['label'] as String?,
      phase: json['phase'] as String?,
      uploaded: (json['uploaded'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      currentName: json['current_name'] as String?,
      startedAtMs: (json['started_at'] as num?)?.toInt() ?? 0,
      finishedAtMs: (json['finished_at'] as num?)?.toInt(),
      error: json['error'] as String?,
    );
  }
}

class BackupQueueItem {
  final String sourceId;
  final String label;
  final int enqueuedAtMs;

  const BackupQueueItem({
    required this.sourceId,
    required this.label,
    this.enqueuedAtMs = 0,
  });

  Map<String, dynamic> toJson() => {
    'source_id': sourceId,
    'label': label,
    'enqueued_at': enqueuedAtMs,
  };

  factory BackupQueueItem.fromJson(Map<String, dynamic> json) {
    return BackupQueueItem(
      sourceId: (json['source_id'] ?? '') as String,
      label: (json['label'] ?? '') as String,
      enqueuedAtMs: (json['enqueued_at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Bounded technical log of the backup runs, shown in the detail sheet.
class BackupRunLog {
  static const _key = 'backup_run_log';
  static const maxLines = 50;

  static Future<List<String>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  static Future<void> add(String message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lines = prefs.getStringList(_key) ?? <String>[];
      final now = DateTime.now();
      final stamp =
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      lines.add('$stamp $message');
      if (lines.length > maxLines) {
        lines.removeRange(0, lines.length - maxLines);
      }
      await prefs.setStringList(_key, lines);
    } catch (_) {}
  }
}

class BackupProgressStore {
  static const _progressKey = 'backup_run_progress';
  static const _cancelKey = 'backup_cancel_requested';
  static const _queueKey = 'backup_manual_queue';

  static Future<BackupRunProgress?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_progressKey);
      if (raw == null || raw.isEmpty) return null;
      return BackupRunProgress.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(BackupRunProgress progress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_progressKey, jsonEncode(progress.toJson()));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_progressKey);
      await prefs.remove(_cancelKey);
    } catch (_) {}
  }

  static Future<bool> cancelRequested() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_cancelKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestCancel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cancelKey, true);
    } catch (_) {}
  }

  static Future<void> clearCancel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cancelKey);
    } catch (_) {}
  }

  static Future<List<BackupQueueItem>> readQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_queueKey) ?? const [];
      return [
        for (final value in raw)
          BackupQueueItem.fromJson(jsonDecode(value) as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> writeQueue(List<BackupQueueItem> queue) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_queueKey, [
        for (final item in queue) jsonEncode(item.toJson()),
      ]);
    } catch (_) {}
  }
}
