import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

class GeoData {
  static List<List<LatLng>>? _land;

  static Future<List<List<LatLng>>> loadLand() async {
    if (_land != null) return _land!;
    final raw = await rootBundle.loadString('assets/geo/ne_110m_land.geojson');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final features = (json['features'] ?? const <dynamic>[]) as List<dynamic>;
    final polygons = <List<LatLng>>[];
    for (final feature in features) {
      final geometry =
          (feature as Map<String, dynamic>)['geometry']
              as Map<String, dynamic>?;
      if (geometry == null) continue;
      final type = geometry['type'] as String?;
      final coordinates =
          (geometry['coordinates'] ?? const <dynamic>[]) as List<dynamic>;
      if (type == 'Polygon') {
        for (final ring in coordinates) {
          polygons.add(_ring(ring as List<dynamic>));
        }
      } else if (type == 'MultiPolygon') {
        for (final polygon in coordinates) {
          for (final ring in polygon as List<dynamic>) {
            polygons.add(_ring(ring as List<dynamic>));
          }
        }
      }
    }
    _land = polygons;
    return polygons;
  }

  static List<LatLng> _ring(List<dynamic> ring) {
    return ring.map((point) {
      final coordinates = point as List<dynamic>;
      return LatLng(
        (coordinates[1] as num).toDouble(),
        (coordinates[0] as num).toDouble(),
      );
    }).toList();
  }
}
