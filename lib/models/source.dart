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
  });

  bool get isKDrive => kind == 'kdrive';

  factory MediaSource.fromJson(Map<String, dynamic> json) {
    return MediaSource(
      id: json['id'] as String,
      kind: (json['kind'] ?? 'local') as String,
      label: (json['label'] ?? '') as String,
      rootPath: json['root_path'] as String?,
      itemCount: ((json['item_count'] ?? 0) as num).toInt(),
      kdriveDriveId: (json['kdrive_drive_id'] as num?)?.toInt(),
      kdriveFolderId: (json['kdrive_folder_id'] as num?)?.toInt(),
      includeSubfolders: (json['include_subfolders'] ?? true) as bool,
      lastScanAt: json['last_scan_at'] == null
          ? null
          : DateTime.tryParse(json['last_scan_at'] as String)?.toLocal(),
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
      driveId: (account?['drive_id'] as num?)?.toInt(),
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
      processed: ((json['processed'] ?? 0) as num).toInt(),
      updated: ((json['updated'] ?? 0) as num).toInt(),
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
      id: ((json['id'] ?? 0) as num).toInt(),
      name: (json['name'] ?? '') as String,
    );
  }
}
