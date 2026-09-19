import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/api_config.dart';
import '../models/auth_user.dart';
import '../models/backup.dart';
import '../models/json_value.dart';
import '../models/media_cluster.dart';
import '../models/media_item.dart';
import '../models/source.dart';
import '../models/timeline_bucket.dart';
import 'upload_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class MediaPage {
  final List<MediaItem> items;
  final int total;
  final int limit;
  final int offset;

  const MediaPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });
}

class ClusterQuery {
  final double west;
  final double south;
  final double east;
  final double north;
  final int zoom;

  const ClusterQuery({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    required this.zoom,
  });

  @override
  bool operator ==(Object other) =>
      other is ClusterQuery &&
      other.west == west &&
      other.south == south &&
      other.east == east &&
      other.north == north &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(west, south, east, north, zoom);
}

class MediaFilter {
  final String status;
  final String type;
  final bool missingOnly;

  const MediaFilter({
    this.status = 'all',
    this.type = 'all',
    this.missingOnly = false,
  });

  @override
  bool operator ==(Object other) =>
      other is MediaFilter &&
      other.status == status &&
      other.type == type &&
      other.missingOnly == missingOnly;

  @override
  int get hashCode => Object.hash(status, type, missingOnly);
}

class ApiClient {
  final String baseUrl;
  final String? token;
  final void Function()? onUnauthorized;

  ApiClient(String baseUrl, {this.token, this.onUnauthorized})
    : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _authHeaders {
    final value = token;
    if (value == null || value.isEmpty) return const {};
    return {'Authorization': 'Bearer $value'};
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final params = <String, String>{};
    query?.forEach((key, value) {
      if (value != null) params[key] = '$value';
    });
    return Uri.parse('$baseUrl$path')
        .replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    try {
      final response = await http
          .get(uri, headers: _authHeaders)
          .timeout(timeout);
      return _decode(response);
    } on TimeoutException {
      throw ApiException(408, 'Request timed out: $uri');
    } on http.ClientException catch (error) {
      throw ApiException(0, error.message);
    }
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final request = http.Request(method, uri)..headers.addAll(_authHeaders);
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final streamed = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on TimeoutException {
      throw ApiException(408, 'Request timed out: $uri');
    } on http.ClientException catch (error) {
      throw ApiException(0, error.message);
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty
        ? const <String, dynamic>{}
        : (jsonDecode(response.body) as Map<String, dynamic>);
    if (response.statusCode == 401) {
      onUnauthorized?.call();
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        '${body['error'] ?? response.reasonPhrase}',
      );
    }
    return body;
  }

  String thumbnailUrl(String mediaId) =>
      '$baseUrl/api/media/$mediaId/thumbnail';

  Future<ApiConfig> apiConfig() async {
    final body = await _getJson(_uri('/api/config'));
    return ApiConfig.fromJson(body);
  }

  Future<AuthUser> me() async {
    final body = await _getJson(_uri('/api/auth/me'));
    return AuthUser.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<AuthUser> mfaSync() async {
    final body = await _sendJson('POST', _uri('/api/auth/mfa/sync'));
    return AuthUser.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<({int password, int mfa})> recoveryCodeCounts() async {
    final body = await _getJson(_uri('/api/auth/recovery-codes'));
    return (
      password: asInt(body['password_remaining']) ?? 0,
      mfa: asInt(body['mfa_remaining']) ?? 0,
    );
  }

  Future<List<String>> regenerateRecoveryCodes({
    String kind = 'password',
  }) async {
    final body = await _sendJson(
      'POST',
      _uri('/api/auth/recovery-codes'),
      body: {'kind': kind},
    );
    return ((body['recovery_codes'] ?? const <dynamic>[]) as List<dynamic>)
        .map((value) => '$value')
        .toList();
  }

  Future<void> resetPasswordWithCode({
    required String identifier,
    required String recoveryCode,
    required String newPassword,
  }) async {
    await _sendJson(
      'POST',
      _uri('/api/auth/password/reset-with-code'),
      body: {
        'identifier': identifier,
        'recovery_code': recoveryCode,
        'new_password': newPassword,
      },
    );
  }

  Future<void> resetMfaWithCode({
    required String identifier,
    required String recoveryCode,
  }) async {
    await _sendJson(
      'POST',
      _uri('/api/auth/mfa/recovery'),
      body: {'identifier': identifier, 'recovery_code': recoveryCode},
    );
  }

  Future<bool> health({Duration timeout = const Duration(seconds: 25)}) async {
    try {
      final body = await _getJson(_uri('/health'), timeout: timeout);
      return body['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<MediaPage> media({
    double? west,
    double? south,
    double? east,
    double? north,
    DateTime? from,
    DateTime? to,
    String status = 'all',
    String type = 'all',
    String? sourceId,
    bool? hasGps,
    String? search,
    int limit = 100,
    int offset = 0,
    String order = 'taken_at.desc',
  }) async {
    final body = await _getJson(
      _uri('/api/media', {
        'west': west,
        'south': south,
        'east': east,
        'north': north,
        'from': from?.toUtc().toIso8601String(),
        'to': to?.toUtc().toIso8601String(),
        'status': status,
        'type': type,
        'source_id': sourceId,
        'has_gps': hasGps,
        'q': search,
        'limit': limit,
        'offset': offset,
        'order': order,
      }),
    );
    return MediaPage(
      items: ((body['items'] ?? const <dynamic>[]) as List<dynamic>)
          .map((item) => MediaItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: asInt(body['total']) ?? 0,
      limit: asInt(body['limit']) ?? limit,
      offset: asInt(body['offset']) ?? offset,
    );
  }

  Future<List<MediaCluster>> clusters({
    required double west,
    required double south,
    required double east,
    required double north,
    required int zoom,
  }) async {
    final body = await _getJson(
      _uri('/api/clusters', {
        'west': west,
        'south': south,
        'east': east,
        'north': north,
        'zoom': zoom,
      }),
    );
    return ((body['clusters'] ?? const <dynamic>[]) as List<dynamic>)
        .map((item) => MediaCluster.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<TimelineBucket>> timeline({DateTime? from}) async {
    final body = await _getJson(
      _uri('/api/timeline', {'from': from?.toUtc().toIso8601String()}),
    );
    return ((body['buckets'] ?? const <dynamic>[]) as List<dynamic>)
        .map((item) => TimelineBucket.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<MediaPage> timelineItems({
    required DateTime from,
    required DateTime to,
    int limit = 200,
    int offset = 0,
  }) async {
    final body = await _getJson(
      _uri('/api/timeline/items', {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
        'limit': limit,
        'offset': offset,
      }),
    );
    return MediaPage(
      items: ((body['items'] ?? const <dynamic>[]) as List<dynamic>)
          .map((item) => MediaItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: asInt(body['total']) ?? 0,
      limit: asInt(body['limit']) ?? limit,
      offset: asInt(body['offset']) ?? offset,
    );
  }

  Future<List<MediaSource>> sources() async {
    final body = await _getJson(_uri('/api/sources'));
    return ((body['sources'] ?? const <dynamic>[]) as List<dynamic>)
        .map((item) => MediaSource.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<String> createSource({
    required String kind,
    required String label,
    String? rootPath,
    String? deviceId,
    String? albumKey,
  }) async {
    final body = await _sendJson(
      'POST',
      _uri('/api/sources'),
      body: {
        'kind': kind,
        'label': label,
        'root_path': rootPath,
        'device_id': deviceId,
        'album_key': albumKey,
      },
    );
    return (body['source'] as Map<String, dynamic>)['id'] as String;
  }

  Future<BatchResult> batchMedia({
    required String sourceId,
    String? scanRunId,
    required List<Map<String, dynamic>> items,
  }) async {
    final body = await _sendJson(
      'POST',
      _uri('/api/media/batch'),
      body: {'source_id': sourceId, 'scan_run_id': scanRunId, 'items': items},
    );
    return BatchResult(
      indexed: asInt(body['indexed']) ?? 0,
      items: ((body['items'] ?? const <dynamic>[]) as List<dynamic>)
          .map((value) => BatchItem.fromJson(value as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<String> registerDevice({
    required String fingerprint,
    String? name,
    String? platform,
  }) async {
    final body = await _sendJson(
      'POST',
      _uri('/api/devices'),
      body: {'fingerprint': fingerprint, 'name': name, 'platform': platform},
    );
    return (body['device'] as Map<String, dynamic>)['id'] as String;
  }

  Future<BackupStatusSnapshot> backupStatus() async {
    final body = await _getJson(_uri('/api/backup/status'));
    return BackupStatusSnapshot.fromJson(body);
  }

  Future<List<PendingBackupItem>> backupPending({
    String? sourceId,
    int limit = 100,
  }) async {
    final body = await _getJson(
      _uri('/api/backup/pending', {'source_id': sourceId, 'limit': limit}),
    );
    return ((body['items'] ?? const <dynamic>[]) as List<dynamic>)
        .map(
          (value) => PendingBackupItem.fromJson(value as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<VerifyQueueItem>> verifyQueue({
    String? sourceId,
    int limit = 100,
  }) async {
    final body = await _getJson(
      _uri('/api/backup/verify-queue', {'source_id': sourceId, 'limit': limit}),
    );
    return ((body['items'] ?? const <dynamic>[]) as List<dynamic>)
        .map((value) => VerifyQueueItem.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<VerifyResult> verifyMedia(String mediaId) async {
    final body = await _sendJson('POST', _uri('/api/media/$mediaId/verify'));
    return VerifyResult.fromJson(body);
  }

  Future<String> createBackupRun({
    String kind = 'backup',
    String? sourceId,
    String? deviceId,
  }) async {
    final body = await _sendJson(
      'POST',
      _uri('/api/backup/runs'),
      body: {'kind': kind, 'source_id': sourceId, 'device_id': deviceId},
    );
    return (body['run'] as Map<String, dynamic>)['id'] as String;
  }

  Future<void> patchBackupRun(
    String id, {
    String? status,
    int? filesSeen,
    int? filesUploaded,
    int? filesSkipped,
    int? filesFailed,
    int? verifiedOk,
    int? verifiedMissing,
    int? bytesUploaded,
    List<String>? errors,
  }) async {
    await _sendJson(
      'PATCH',
      _uri('/api/backup/runs/$id'),
      body: {
        'status': status,
        'files_seen': filesSeen,
        'files_uploaded': filesUploaded,
        'files_skipped': filesSkipped,
        'files_failed': filesFailed,
        'verified_ok': verifiedOk,
        'verified_missing': verifiedMissing,
        'bytes_uploaded': bytesUploaded,
        'errors': errors,
      },
    );
  }

  Future<void> uploadMedia({
    required String mediaId,
    required String filePath,
    String? destination,
    void Function(int sent, int total)? onProgress,
    bool Function()? isCancelled,
  }) {
    return uploadFileToApi(
      baseUrl: baseUrl,
      token: token,
      mediaId: mediaId,
      filePath: filePath,
      destination: destination,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  Future<MediaSource> patchSource(
    String id, {
    String? deviceId,
    String? albumKey,
  }) async {
    final body = await _sendJson(
      'PATCH',
      _uri('/api/sources/$id'),
      body: {'device_id': deviceId, 'album_key': albumKey},
    );
    return MediaSource.fromJson(body['source'] as Map<String, dynamic>);
  }

  Future<String> createScanRun(String sourceId) async {
    final body = await _sendJson(
      'POST',
      _uri('/api/scan-runs'),
      body: {'source_id': sourceId},
    );
    return (body['scan_run'] as Map<String, dynamic>)['id'] as String;
  }

  Future<Map<String, dynamic>> scanRun(String id) async {
    final body = await _getJson(_uri('/api/scan-runs/$id'));
    return body['scan_run'] as Map<String, dynamic>;
  }

  Future<void> patchScanRun(
    String id, {
    String? status,
    int? filesSeen,
    int? filesIndexed,
    List<String>? errors,
  }) async {
    await _sendJson(
      'PATCH',
      _uri('/api/scan-runs/$id'),
      body: {
        'status': status,
        'files_seen': filesSeen,
        'files_indexed': filesIndexed,
        if (errors != null) 'errors': errors,
      },
    );
  }

  Future<KDriveAccountStatus> kdriveStatus() async {
    final body = await _getJson(_uri('/api/kdrive/status'));
    return KDriveAccountStatus.fromJson(body);
  }

  Future<void> kdriveConnect({
    required String token,
    required int driveId,
    String? label,
  }) async {
    await _sendJson(
      'POST',
      _uri('/api/kdrive/connect'),
      body: {'token': token, 'drive_id': driveId, 'label': label},
    );
  }

  Future<List<KDriveFolder>> kdriveFolders({int parentId = 1}) async {
    final body = await _getJson(
      _uri('/api/kdrive/folders', {'parent_id': parentId}),
    );
    return ((body['folders'] ?? const <dynamic>[]) as List<dynamic>)
        .map((item) => KDriveFolder.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<String> kdriveScan({
    required int folderId,
    bool includeSubfolders = true,
    String? label,
  }) async {
    final body = await _sendJson(
      'POST',
      _uri('/api/kdrive/scan'),
      body: {
        'folder_id': folderId,
        'include_subfolders': includeSubfolders,
        if (label != null) 'label': label,
      },
    );
    return body['scan_run_id'] as String;
  }

  Future<void> updateSource(
    String id, {
    String? label,
    bool? includeSubfolders,
  }) async {
    await _sendJson(
      'PATCH',
      _uri('/api/sources/$id'),
      body: {
        if (label != null) 'label': label,
        if (includeSubfolders != null) 'include_subfolders': includeSubfolders,
      },
    );
  }

  Future<void> deleteSource(String id) async {
    await _sendJson('DELETE', _uri('/api/sources/$id'));
  }

  Future<void> kdriveEnrich({int limit = 20}) async {
    await _sendJson('POST', _uri('/api/kdrive/enrich'), body: {'limit': limit});
  }

  Future<KDriveEnrichState> kdriveEnrichState() async {
    final body = await _getJson(_uri('/api/kdrive/enrich'));
    return KDriveEnrichState.fromJson(body);
  }

  Future<void> kdrivePreviews() async {
    await _sendJson('POST', _uri('/api/kdrive/previews'));
  }

  Future<KDrivePreviewState> kdrivePreviewsState() async {
    final body = await _getJson(_uri('/api/kdrive/previews'));
    return KDrivePreviewState.fromJson(body);
  }
}
