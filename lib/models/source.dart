import 'json_value.dart';

class MediaSource {
  final String id;
  final String kind;
  final String label;
  final String? rootPath;
  final int itemCount;
  final int? kdriveDriveId;
  final int? kdriveFolderId;
  final bool includeSubfolders;
  final DateTime? lastScanAt;
  final String? deviceId;
  final String? albumKey;
  final bool autoBackup;
  final String? backupFolderPath;

  const MediaSource({
    required this.id,
    required this.kind,
    required this.label,
    required this.itemCount,
    this.rootPath,
    this.kdriveDriveId,
    this.kdriveFolderId,
    this.includeSubfolders = true,
    this.lastScanAt,
    this.deviceId,
    this.albumKey,
    this.autoBackup = false,
    this.backupFolderPath,
  });

  bool get isKDrive => kind == 'kdrive';

  factory MediaSource.fromJson(Map<String, dynamic> json) {
    return MediaSource(
      id: json['id'] as String,
      kind: (json['kind'] ?? 'local') as String,
      label: (json['label'] ?? '') as String,
      rootPath: json['root_path'] as String?,
      itemCount: asInt(json['item_count']) ?? 0,
      kdriveDriveId: asInt(json['kdrive_drive_id']),
      kdriveFolderId: asInt(json['kdrive_folder_id']),
      includeSubfolders: (json['include_subfolders'] ?? true) as bool,
      lastScanAt: json['last_scan_at'] == null
          ? null
          : DateTime.tryParse(json['last_scan_at'] as String)?.toLocal(),
      deviceId: json['device_id'] as String?,
      albumKey: json['album_key'] as String?,
      autoBackup: (json['auto_backup'] ?? false) as bool,
      backupFolderPath: json['backup_folder_path'] as String?,
    );
  }
}

class KDriveAccountStatus {
  final bool connected;
  final String? label;
  final int? driveId;

  const KDriveAccountStatus({
    required this.connected,
    this.label,
    this.driveId,
  });

  factory KDriveAccountStatus.fromJson(Map<String, dynamic> json) {
    final account = json['account'] as Map<String, dynamic>?;
    return KDriveAccountStatus(
      connected: (json['connected'] ?? false) as bool,
      label: account?['label'] as String?,
      driveId: asInt(account?['drive_id']),
    );
  }
}

class KDriveEnrichState {
  final bool running;
  final int processed;
  final int updated;
  final List<String> errors;

  const KDriveEnrichState({
    required this.running,
    required this.processed,
    required this.updated,
    required this.errors,
  });

  factory KDriveEnrichState.fromJson(Map<String, dynamic> json) {
    return KDriveEnrichState(
      running: (json['running'] ?? false) as bool,
      processed: asInt(json['processed']) ?? 0,
      updated: asInt(json['updated']) ?? 0,
      errors: ((json['errors'] ?? const <dynamic>[]) as List<dynamic>)
          .map((e) => '$e')
          .toList(),
    );
  }
}

class KDriveFolder {
  final int id;
  final String name;

  const KDriveFolder({required this.id, required this.name});

  factory KDriveFolder.fromJson(Map<String, dynamic> json) {
    return KDriveFolder(
      id: asInt(json['id']) ?? 0,
      name: (json['name'] ?? '') as String,
    );
  }
}

class KDrivePreviewState {
  final bool running;
  final int processed;
  final int updated;
  final int skipped;
  final List<String> errors;

  const KDrivePreviewState({
    required this.running,
    required this.processed,
    required this.updated,
    required this.skipped,
    required this.errors,
  });

  factory KDrivePreviewState.fromJson(Map<String, dynamic> json) {
    return KDrivePreviewState(
      running: (json['running'] ?? false) as bool,
      processed: asInt(json['processed']) ?? 0,
      updated: asInt(json['updated']) ?? 0,
      skipped: asInt(json['skipped']) ?? 0,
      errors: ((json['errors'] ?? const <dynamic>[]) as List<dynamic>)
          .map((e) => '$e')
          .toList(),
    );
  }
}
