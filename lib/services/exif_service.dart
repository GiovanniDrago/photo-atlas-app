import 'dart:typed_data';

import 'package:exif/exif.dart';

class ExtractedMetadata {
  final DateTime? takenAt;
  final double? lat;
  final double? lon;
  final int? width;
  final int? height;

  const ExtractedMetadata({
    this.takenAt,
    this.lat,
    this.lon,
    this.width,
    this.height,
  });

  factory ExtractedMetadata.fromMap(Map<String, dynamic> map) {
    return ExtractedMetadata(
      takenAt: map['takenAt'] == null
          ? null
          : DateTime.tryParse(map['takenAt'] as String),
      lat: (map['lat'] as num?)?.toDouble(),
      lon: (map['lon'] as num?)?.toDouble(),
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
    );
  }

  bool get isEmpty => takenAt == null && lat == null && lon == null;
}

Map<String, dynamic> parseExifBytes(Uint8List bytes) {
  final result = <String, dynamic>{};
  if (bytes.isEmpty) return result;
  Map<String, IfdTag> tags;
  try {
    tags = readExifFromBytes(bytes);
  } catch (_) {
    return result;
  }
  if (tags.isEmpty) return result;

  final dateTag =
      tags['EXIF DateTimeOriginal'] ??
      tags['EXIF DateTimeDigitized'] ??
      tags['Image DateTime'];
  if (dateTag != null) {
    final parsed = _parseExifDate(dateTag.printable);
    if (parsed != null) result['takenAt'] = parsed.toIso8601String();
  }

  final lat = _dms(tags, 'GPS GPSLatitude', 'GPS GPSLatitudeRef');
  final lon = _dms(tags, 'GPS GPSLongitude', 'GPS GPSLongitudeRef');
  if (lat != null) result['lat'] = lat;
  if (lon != null) result['lon'] = lon;

  final width = _intTag(
    tags['EXIF ExifImageWidth'] ?? tags['Image ImageWidth'],
  );
  final height = _intTag(
    tags['EXIF ExifImageLength'] ?? tags['Image ImageLength'],
  );
  if (width != null) result['width'] = width;
  if (height != null) result['height'] = height;

  return result;
}

DateTime? _parseExifDate(String? value) {
  if (value == null || value.length < 19) return null;
  final normalized = value.replaceFirstMapped(
    RegExp(r'^(\d{4}):(\d{2}):(\d{2})'),
    (match) => '${match[1]}-${match[2]}-${match[3]}',
  );
  return DateTime.tryParse(normalized);
}

double? _dms(Map<String, IfdTag> tags, String key, String refKey) {
  final tag = tags[key];
  if (tag == null) return null;
  final values = tag.values.toList();
  if (values.length < 3) return null;
  final degrees = _ratio(values[0]);
  final minutes = _ratio(values[1]);
  final seconds = _ratio(values[2]);
  if (degrees == null || minutes == null || seconds == null) return null;
  var result = degrees + minutes / 60.0 + seconds / 3600.0;
  final ref = tags[refKey]?.printable.trim().toUpperCase();
  if (ref == 'S' || ref == 'W') result = -result;
  return result;
}

double? _ratio(dynamic value) {
  if (value is num) return value.toDouble();
  try {
    final dynamic ratio = value;
    final numerator = ratio.numerator;
    final denominator = ratio.denominator;
    if (numerator is num && denominator is num && denominator != 0) {
      return numerator / denominator;
    }
  } catch (_) {
    return null;
  }
  return null;
}

int? _intTag(IfdTag? tag) {
  if (tag == null) return null;
  final values = tag.values.toList();
  if (values.isEmpty) return null;
  final first = values.first;
  if (first is num) return first.toInt();
  final asDouble = _ratio(first);
  return asDouble?.round();
}
