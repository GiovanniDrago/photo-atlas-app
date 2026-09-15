import 'json_value.dart';

class TimelineBucket {
  final DateTime bucketStart;
  final DateTime bucketEnd;
  final String granularity;
  final int count;
  final String? representativeId;

  const TimelineBucket({
    required this.bucketStart,
    required this.bucketEnd,
    required this.granularity,
    required this.count,
    this.representativeId,
  });

  static String labelFor(TimelineBucket bucket) {
    final start = bucket.bucketStart;
    switch (bucket.granularity) {
      case 'day':
        return '${start.year}-${_two(start.month)}-${_two(start.day)}';
      case 'week':
        final end = bucket.bucketEnd.subtract(const Duration(days: 1));
        return '${start.year}-${_two(start.month)}-${_two(start.day)} / ${_two(end.month)}-${_two(end.day)}';
      default:
        return '${start.year}-${_two(start.month)}';
    }
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  factory TimelineBucket.fromJson(Map<String, dynamic> json) {
    return TimelineBucket(
      bucketStart: DateTime.parse(json['bucket_start'] as String).toLocal(),
      bucketEnd: DateTime.parse(json['bucket_end'] as String).toLocal(),
      granularity: (json['granularity'] ?? 'month') as String,
      count: asInt(json['count']) ?? 0,
      representativeId: json['representative_id'] as String?,
    );
  }
}
