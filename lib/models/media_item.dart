class MediaItem {
  final String id;
  final String sourceId;
  final String externalKey;
  final String? path;
  final String name;
  final String? mime;
  final String mediaType;
  final int? sizeBytes;
  final DateTime? takenAt;
  final DateTime? fileCreatedAt;
  final DateTime? modifiedAt;
  final double? lat;
  final double? lon;
  final bool hasGps;
  final String metadataStatus;
  final int? width;
  final int? height;
  final double? durationS;
  final String? sourceKind;
  final String? sourceLabel;

  const MediaItem({
    required this.id,
    required this.sourceId,
    required this.externalKey,
    required this.name,
    required this.mediaType,
    required this.metadataStatus,
    required this.hasGps,
    this.path,
    this.mime,
    this.sizeBytes,
    this.takenAt,
    this.fileCreatedAt,
    this.modifiedAt,
    this.lat,
    this.lon,
    this.width,
    this.height,
    this.durationS,
    this.sourceKind,
    this.sourceLabel,
  });

  bool get isVideo => mediaType == 'video';
  bool get hasFullMetadata => metadataStatus == 'full';

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as String,
      sourceId: json['source_id'] as String,
      externalKey: (json['external_key'] ?? '') as String,
      path: json['path'] as String?,
      name: (json['name'] ?? '') as String,
      mime: json['mime'] as String?,
      mediaType: (json['media_type'] ?? 'image') as String,
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      takenAt: _parseDate(json['taken_at']),
      fileCreatedAt: _parseDate(json['file_created_at']),
      modifiedAt: _parseDate(json['modified_at']),
      lat: (json['lat'] as num?)?.toDouble(),
      lon: (json['lon'] as num?)?.toDouble(),
      hasGps: (json['has_gps'] ?? false) as bool,
      metadataStatus: (json['metadata_status'] ?? 'none') as String,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      durationS: (json['duration_s'] as num?)?.toDouble(),
      sourceKind: json['source_kind'] as String?,
      sourceLabel: json['source_label'] as String?,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}
