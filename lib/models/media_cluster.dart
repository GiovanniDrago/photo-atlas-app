class MediaCluster {
  final String key;
  final double lat;
  final double lon;
  final int count;
  final double west;
  final double south;
  final double east;
  final double north;
  final String? representativeId;

  const MediaCluster({
    required this.key,
    required this.lat,
    required this.lon,
    required this.count,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    this.representativeId,
  });

  factory MediaCluster.fromJson(Map<String, dynamic> json) {
    final bounds = (json['bounds'] as Map<String, dynamic>?) ?? const {};
    return MediaCluster(
      key: (json['key'] ?? '') as String,
      lat: ((json['lat'] ?? 0) as num).toDouble(),
      lon: ((json['lon'] ?? 0) as num).toDouble(),
      count: ((json['count'] ?? 0) as num).toInt(),
      west: ((bounds['west'] ?? 0) as num).toDouble(),
      south: ((bounds['south'] ?? 0) as num).toDouble(),
      east: ((bounds['east'] ?? 0) as num).toDouble(),
      north: ((bounds['north'] ?? 0) as num).toDouble(),
      representativeId: json['representative_id'] as String?,
    );
  }
}
