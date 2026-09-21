class BatchItem {
  final String id;
  final String externalKey;

  const BatchItem({required this.id, required this.externalKey});

  factory BatchItem.fromJson(Map<String, dynamic> json) {
    return BatchItem(
      id: (json['id'] ?? '') as String,
      externalKey: (json['external_key'] ?? '') as String,
    );
  }
}

class BatchResult {
  final int indexed;
  final List<BatchItem> items;

  const BatchResult({required this.indexed, required this.items});
}

class BackupSourceStatus {
  final String id;
  final String label;
  final int total;
  final int uploaded;
  final int pending;
  final int failed;
  final int bytesUploaded;
  final int bytesTotal;
  final String? backupFolderPath;
  final DateTime? backupLastRunAt;
  final bool autoBackup;

  const BackupSourceStatus({
    required this.id,
    required this.label,
    required this.total,
    required this.uploaded,
    required this.pending,
    required this.failed,
    required this.bytesUploaded,
    required this.bytesTotal,
    this.backupFolderPath,
    this.backupLastRunAt,
    this.autoBackup = false,
  });

  factory BackupSourceStatus.fromJson(Map<String, dynamic> json) {
    return BackupSourceStatus(
      id: (json['id'] ?? '') as String,
      label: (json['label'] ?? '') as String,
      total: _int(json['total']),
      uploaded: _int(json['uploaded']),
      pending: _int(json['pending']),
      failed: _int(json['failed']),
      bytesUploaded: _int(json['bytes_uploaded']),
      bytesTotal: _int(json['bytes_total']),
      backupFolderPath: json['backup_folder_path'] as String?,
      backupLastRunAt: json['backup_last_run_at'] == null
          ? null
          : DateTime.tryParse(json['backup_last_run_at'] as String)?.toLocal(),
      autoBackup: (json['auto_backup'] ?? false) as bool,
    );
  }
}

class BackupStatusSnapshot {
  final List<BackupSourceStatus> sources;
  final int total;
  final int uploaded;
  final int pending;
  final int failed;
  final int bytesUploaded;
  final int bytesTotal;

  const BackupStatusSnapshot({
    required this.sources,
    required this.total,
    required this.uploaded,
    required this.pending,
    required this.failed,
    required this.bytesUploaded,
    required this.bytesTotal,
  });

  factory BackupStatusSnapshot.fromJson(Map<String, dynamic> json) {
    final sources = ((json['sources'] ?? const <dynamic>[]) as List<dynamic>)
        .map(
          (value) => BackupSourceStatus.fromJson(value as Map<String, dynamic>),
        )
        .toList();
    final totals =
        (json['totals'] ?? const <String, dynamic>{}) as Map<String, dynamic>;
    return BackupStatusSnapshot(
      sources: sources,
      total: _int(totals['total']),
      uploaded: _int(totals['uploaded']),
      pending: _int(totals['pending']),
      failed: _int(totals['failed']),
      bytesUploaded: _int(totals['bytes_uploaded']),
      bytesTotal: _int(totals['bytes_total']),
    );
  }
}

class PendingBackupItem {
  final String id;
  final String sourceId;
  final String sourceLabel;
  final String name;
  final String? mime;
  final String mediaType;
  final int sizeBytes;
  final String externalKey;
  final String? path;
  final int backupAttempts;

  const PendingBackupItem({
    required this.id,
    required this.sourceId,
    required this.sourceLabel,
    required this.name,
    required this.mediaType,
    required this.sizeBytes,
    required this.externalKey,
    this.mime,
    this.path,
    this.backupAttempts = 0,
  });

  factory PendingBackupItem.fromJson(Map<String, dynamic> json) {
    return PendingBackupItem(
      id: (json['id'] ?? '') as String,
      sourceId: (json['source_id'] ?? '') as String,
      sourceLabel: (json['source_label'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      mime: json['mime'] as String?,
      mediaType: (json['media_type'] ?? 'image') as String,
      sizeBytes: _int(json['size_bytes']),
      externalKey: (json['external_key'] ?? '') as String,
      path: json['path'] as String?,
      backupAttempts: _int(json['backup_attempts']),
    );
  }
}

class VerifyQueueItem {
  final String id;
  final String sourceId;
  final String sourceLabel;
  final String name;
  final int sizeBytes;
  final int? kdriveFileId;

  const VerifyQueueItem({
    required this.id,
    required this.sourceId,
    required this.sourceLabel,
    required this.name,
    required this.sizeBytes,
    this.kdriveFileId,
  });

  factory VerifyQueueItem.fromJson(Map<String, dynamic> json) {
    return VerifyQueueItem(
      id: (json['id'] ?? '') as String,
      sourceId: (json['source_id'] ?? '') as String,
      sourceLabel: (json['source_label'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      sizeBytes: _int(json['size_bytes']),
      kdriveFileId: json['kdrive_file_id'] == null
          ? null
          : _int(json['kdrive_file_id']),
    );
  }
}

class VerifyResult {
  final bool ok;
  final String status;
  final String? reason;

  const VerifyResult({required this.ok, required this.status, this.reason});

  factory VerifyResult.fromJson(Map<String, dynamic> json) {
    return VerifyResult(
      ok: (json['ok'] ?? false) as bool,
      status: (json['status'] ?? 'unknown') as String,
      reason: json['reason'] as String?,
    );
  }
}

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
