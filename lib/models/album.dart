import 'dart:convert';

import 'json_value.dart';
import 'media_item.dart';

enum AlbumKind {
  manual,
  smart;

  static AlbumKind parse(Object? value) =>
      value == 'smart' ? AlbumKind.smart : AlbumKind.manual;

  String get wire => name;
}

/// One leaf of a smart-album rule tree: `{field, op, value}`.
class AlbumRule {
  final String field;
  final String op;
  final Object? value;

  const AlbumRule({required this.field, required this.op, this.value});

  factory AlbumRule.fromJson(Map<String, dynamic> json) {
    return AlbumRule(
      field: '${json['field'] ?? ''}',
      op: '${json['op'] ?? ''}',
      value: json['value'],
    );
  }

  Map<String, dynamic> toJson() => {'field': field, 'op': op, 'value': value};

  @override
  bool operator ==(Object other) =>
      other is AlbumRule &&
      other.field == field &&
      other.op == op &&
      jsonEncode(other.value) == jsonEncode(value);

  @override
  int get hashCode => Object.hash(field, op, jsonEncode(value));
}

/// Smart-album rules: one top-level group (`all` = AND, `any` = OR).
class AlbumRules {
  final String group;
  final List<AlbumRule> rules;

  const AlbumRules({this.group = 'all', this.rules = const []});

  static const empty = AlbumRules();

  bool get isEmpty => rules.isEmpty;

  factory AlbumRules.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return empty;
    final group = json['any'] != null ? 'any' : 'all';
    final list = json[group];
    if (list is! List) return empty;
    return AlbumRules(
      group: group,
      rules: [
        for (final item in list)
          if (item is Map<String, dynamic>) AlbumRule.fromJson(item),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    if (isEmpty) return const {};
    return {
      group: [for (final rule in rules) rule.toJson()],
    };
  }

  @override
  bool operator ==(Object other) {
    if (other is! AlbumRules) return false;
    if (other.group != group || other.rules.length != rules.length) {
      return false;
    }
    for (var index = 0; index < rules.length; index += 1) {
      if (rules[index] != other.rules[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(group, Object.hashAll(rules));
}

class Album {
  final String id;
  final String name;
  final AlbumKind kind;
  final AlbumRules rules;
  final String? coverMediaId;
  final MediaItem? cover;
  final int itemCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Album({
    required this.id,
    required this.name,
    required this.kind,
    this.rules = AlbumRules.empty,
    this.coverMediaId,
    this.cover,
    this.itemCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  bool get isSmart => kind == AlbumKind.smart;

  factory Album.fromJson(Map<String, dynamic> json) {
    final cover = json['cover'];
    return Album(
      id: '${json['id']}',
      name: '${json['name'] ?? ''}',
      kind: AlbumKind.parse(json['kind']),
      rules: AlbumRules.fromJson(json['rules'] as Map<String, dynamic>?),
      coverMediaId: json['cover_media_id'] as String?,
      cover: cover is Map<String, dynamic> ? MediaItem.fromJson(cover) : null,
      itemCount: asInt(json['item_count']) ?? 0,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}

/// Editable rules for the smart-album builder: the three groups exposed by the
/// UI (capture date, upload date, location + radius) plus the media type.
class AlbumRuleDraft {
  DateTime? takenFrom;
  DateTime? takenTo;
  DateTime? uploadedFrom;
  DateTime? uploadedTo;
  double? centerLat;
  double? centerLon;
  double? radiusM;
  String mediaType;

  AlbumRuleDraft({
    this.takenFrom,
    this.takenTo,
    this.uploadedFrom,
    this.uploadedTo,
    this.centerLat,
    this.centerLon,
    this.radiusM,
    this.mediaType = 'all',
  });

  bool get hasLocation =>
      centerLat != null && centerLon != null && radiusM != null;

  bool get isEmpty =>
      takenFrom == null &&
      takenTo == null &&
      uploadedFrom == null &&
      uploadedTo == null &&
      !hasLocation &&
      mediaType == 'all';

  /// Builds the API rule tree; `to` dates are inclusive (end of the day).
  AlbumRules toRules() {
    final rules = <AlbumRule>[];
    rules.addAll(_dateRules('taken_at', takenFrom, takenTo));
    rules.addAll(_dateRules('backed_up_at', uploadedFrom, uploadedTo));
    if (hasLocation) {
      rules.add(
        AlbumRule(
          field: 'location',
          op: 'within',
          value: {
            'lat': centerLat,
            'lon': centerLon,
            'radius_m': radiusM!.round(),
          },
        ),
      );
    }
    if (mediaType == 'image' || mediaType == 'video') {
      rules.add(AlbumRule(field: 'media_type', op: 'eq', value: mediaType));
    }
    return AlbumRules(rules: rules);
  }

  static List<AlbumRule> _dateRules(
    String field,
    DateTime? from,
    DateTime? to,
  ) {
    final start = from == null
        ? null
        : DateTime(from.year, from.month, from.day).toUtc();
    final end = to == null
        ? null
        : DateTime(to.year, to.month, to.day, 23, 59, 59, 999).toUtc();
    if (start != null && end != null) {
      return [
        AlbumRule(
          field: field,
          op: 'between',
          value: [start.toIso8601String(), end.toIso8601String()],
        ),
      ];
    }
    if (start != null) {
      return [
        AlbumRule(field: field, op: 'gte', value: start.toIso8601String()),
      ];
    }
    if (end != null) {
      return [AlbumRule(field: field, op: 'lte', value: end.toIso8601String())];
    }
    return const [];
  }

  /// Restores the builder fields from saved rules (date bounds return as local
  /// dates; the last condition of each field wins).
  factory AlbumRuleDraft.fromRules(AlbumRules rules) {
    final draft = AlbumRuleDraft();
    for (final rule in rules.rules) {
      switch (rule.field) {
        case 'taken_at':
        case 'backed_up_at':
          final dates = _parseDateRule(rule);
          if (rule.field == 'taken_at') {
            draft.takenFrom = dates.$1;
            draft.takenTo = dates.$2;
          } else {
            draft.uploadedFrom = dates.$1;
            draft.uploadedTo = dates.$2;
          }
        case 'location':
          final value = rule.value;
          if (value is Map) {
            draft.centerLat = _asDouble(value['lat']);
            draft.centerLon = _asDouble(value['lon']);
            draft.radiusM = _asDouble(value['radius_m']);
          }
        case 'media_type':
          if (rule.value is String) draft.mediaType = '${rule.value}';
      }
    }
    return draft;
  }

  static (DateTime?, DateTime?) _parseDateRule(AlbumRule rule) {
    switch (rule.op) {
      case 'between':
        final value = rule.value;
        if (value is List && value.length == 2) {
          return (_asDate(value[0]), _asDate(value[1]));
        }
      case 'gte':
        return (_asDate(rule.value), null);
      case 'lte':
        return (null, _asDate(rule.value));
    }
    return (null, null);
  }

  static DateTime? _asDate(Object? value) {
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return null;
  }
}
