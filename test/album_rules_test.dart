import 'package:flutter_test/flutter_test.dart';
import 'package:photoatlas/models/album.dart';

void main() {
  test('Album parses kind, rules, count and cover', () {
    final album = Album.fromJson({
      'id': 'a1',
      'name': 'Viaggio',
      'kind': 'smart',
      'rules': {
        'all': [
          {
            'field': 'taken_at',
            'op': 'between',
            'value': ['2024-01-01T00:00:00.000Z', '2024-12-31T23:59:59.999Z'],
          },
        ],
      },
      'cover_media_id': 'm1',
      'cover': {
        'id': 'm1',
        'source_id': 's1',
        'name': 'IMG_1.jpg',
        'media_type': 'image',
        'thumbnail_url': 'http://api/thumb',
      },
      'item_count': 12,
      'created_at': '2024-06-01T10:00:00Z',
    });
    expect(album.id, 'a1');
    expect(album.name, 'Viaggio');
    expect(album.kind, AlbumKind.smart);
    expect(album.isSmart, isTrue);
    expect(album.itemCount, 12);
    expect(album.rules.group, 'all');
    expect(album.rules.rules, hasLength(1));
    expect(album.rules.rules.first.field, 'taken_at');
    expect(album.cover?.id, 'm1');
    expect(album.createdAt, isNotNull);
  });

  test('rules round-trip through JSON', () {
    final rules = AlbumRules.fromJson({
      'any': [
        {'field': 'media_type', 'op': 'eq', 'value': 'video'},
        {
          'field': 'location',
          'op': 'within',
          'value': {'lat': 45.07, 'lon': 7.68, 'radius_m': 5000},
        },
      ],
    });
    expect(rules.group, 'any');
    expect(rules.rules, hasLength(2));
    final json = rules.toJson();
    expect(json.keys.single, 'any');
    expect(AlbumRules.fromJson(json), rules);
    expect(AlbumRules.empty.toJson(), isEmpty);
    expect(AlbumRules.fromJson(const {}), AlbumRules.empty);
  });

  test('draft compiles date bounds to gte, lte and between', () {
    final empty = AlbumRuleDraft();
    expect(empty.isEmpty, isTrue);
    expect(empty.toRules().isEmpty, isTrue);

    final from = AlbumRuleDraft(takenFrom: DateTime(2024, 1, 1));
    final fromRules = from.toRules().rules.single;
    expect(fromRules.field, 'taken_at');
    expect(fromRules.op, 'gte');
    expect(fromRules.value, DateTime(2024, 1, 1).toUtc().toIso8601String());

    final to = AlbumRuleDraft(takenTo: DateTime(2024, 12, 31));
    final toRules = to.toRules().rules.single;
    expect(toRules.op, 'lte');
    expect(
      toRules.value,
      DateTime(2024, 12, 31, 23, 59, 59, 999).toUtc().toIso8601String(),
    );

    final both = AlbumRuleDraft(
      takenFrom: DateTime(2024, 1, 1),
      takenTo: DateTime(2024, 12, 31),
    );
    final between = both.toRules().rules.single;
    expect(between.op, 'between');
    expect(between.value, [
      DateTime(2024, 1, 1).toUtc().toIso8601String(),
      DateTime(2024, 12, 31, 23, 59, 59, 999).toUtc().toIso8601String(),
    ]);
  });

  test('draft combines upload date, location and media type', () {
    final draft = AlbumRuleDraft(
      uploadedFrom: DateTime(2025, 3, 1),
      centerLat: 45.07,
      centerLon: 7.68,
      radiusM: 2500,
      mediaType: 'video',
    );
    final rules = draft.toRules();
    expect(rules.rules, hasLength(3));
    expect(rules.rules[0].field, 'backed_up_at');
    expect(rules.rules[0].op, 'gte');
    expect(rules.rules[1].field, 'location');
    expect(rules.rules[1].value, {'lat': 45.07, 'lon': 7.68, 'radius_m': 2500});
    expect(rules.rules[2].field, 'media_type');
    expect(rules.rules[2].value, 'video');
    expect(rules.group, 'all');

    final restored = AlbumRuleDraft.fromRules(rules);
    expect(restored.uploadedFrom, DateTime(2025, 3, 1));
    expect(restored.uploadedTo, isNull);
    expect(restored.centerLat, 45.07);
    expect(restored.centerLon, 7.68);
    expect(restored.radiusM, 2500);
    expect(restored.mediaType, 'video');
    expect(restored.toRules(), rules);
  });

  test('draft restores an inclusive date range from between', () {
    final rules = AlbumRuleDraft(
      takenFrom: DateTime(2024, 5, 1),
      takenTo: DateTime(2024, 5, 31),
    ).toRules();
    final restored = AlbumRuleDraft.fromRules(rules);
    expect(restored.takenFrom, DateTime(2024, 5, 1));
    expect(restored.takenTo, DateTime(2024, 5, 31));
  });
}
