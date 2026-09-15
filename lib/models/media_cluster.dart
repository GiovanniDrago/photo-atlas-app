import 'json_value.dart';

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
      lat: asDouble(json['lat']) ?? 0,
      lon: asDouble(json['lon']) ?? 0,
      count: asInt(json['count']) ?? 0,
      west: asDouble(bounds['west']) ?? 0,
      south: asDouble(bounds['south']) ?? 0,
      east: asDouble(bounds['east']) ?? 0,
      north: asDouble(bounds['north']) ?? 0,
      representativeId: json['representative_id'] as String?,
    );
  }
}
