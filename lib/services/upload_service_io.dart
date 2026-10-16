import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'api_client.dart';

/// Files above this size are uploaded with the resumable chunked protocol.
const int chunkedUploadThresholdBytes = 16 * 1024 * 1024;

/// Preferred chunk size; the API may answer with a different one.
const int preferredChunkBytes = 8 * 1024 * 1024;

const Duration _jsonTimeout = Duration(seconds: 60);
const Duration _chunkTimeout = Duration(minutes: 30);

class UploadCancelled implements Exception {
  const UploadCancelled();

  @override
  String toString() => 'upload cancelled';
}

Future<void> uploadFileToApi({
  required String baseUrl,
  required String? token,
  required String mediaId,
  required String filePath,
  String? destination,
  void Function(int sent, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final file = File(filePath);
  bool exists;
  int length;
  try {
    exists = await file.exists();
    length = exists ? await file.length() : 0;
  } on FileSystemException catch (error) {
    throw ApiException(
      400,
      'cannot read ${error.path ?? filePath}: ${error.osError?.message ?? error.message}',
    );
  }
  if (!exists) {
    throw ApiException(400, 'file not found on the device: $filePath');
  }
  if (length <= 0) {
    throw ApiException(400, 'empty file on the device: $filePath');
  }
  if (isCancelled?.call() ?? false) {
    throw const UploadCancelled();
  }

  // Large files (typically long videos) use the resumable chunked protocol so
  // an interrupted run resumes from the last uploaded chunk instead of
  // restarting from scratch. Falls back to the single request when the API
  // does not expose the chunked endpoints.
  if (length > chunkedUploadThresholdBytes) {
    final done = await _chunkedUpload(
      baseUrl: baseUrl,
      token: token,
      mediaId: mediaId,
      file: file,
      length: length,
      destination: destination,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (done) return;
  }

  await _singleShotUpload(
    baseUrl: baseUrl,
    token: token,
    mediaId: mediaId,
    file: file,
    length: length,
    destination: destination,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );
}

Future<void> _singleShotUpload({
  required String baseUrl,
  required String? token,
  required String mediaId,
  required File file,
  required int length,
  String? destination,
  void Function(int sent, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final query = destination == null ? '' : '?destination=$destination';
  final uri = Uri.parse('$baseUrl/api/media/$mediaId/upload$query');
  final request = http.StreamedRequest('POST', uri);
  final headers = <String, String>{'Content-Type': 'application/octet-stream'};
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  request.headers.addAll(headers);
  request.contentLength = length;

  final responseFuture = request.send();
  var sent = 0;
  try {
    await for (final chunk in file.openRead()) {
      if (isCancelled?.call() ?? false) {
        throw const UploadCancelled();
      }
      request.sink.add(chunk);
      sent += chunk.length;
      onProgress?.call(sent, length);
    }
    await request.sink.close();
  } catch (error) {
    await request.sink.close().catchError((_) {});
    rethrow;
  }

  final response = await http.Response.fromStream(
    await responseFuture.timeout(const Duration(minutes: 30)),
  );
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, _message(response));
  }
}

/// Returns true when the file was fully uploaded through the chunked protocol,
/// false when the API does not support it (caller falls back to single shot).
Future<bool> _chunkedUpload({
  required String baseUrl,
  required String? token,
  required String mediaId,
  required File file,
  required int length,
  String? destination,
  void Function(int sent, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final query = destination == null ? '' : '?destination=$destination';
  Map<String, dynamic> init;
  try {
    init = await _postJson(
      baseUrl,
      token,
      '/api/media/$mediaId/upload/init$query',
      {'size': length, 'chunk_size': preferredChunkBytes},
    );
  } on ApiException catch (error) {
    if (error.statusCode == 404 || error.statusCode == 405) return false;
    rethrow;
  }

  final session = (init['session'] ?? const <String, dynamic>{})
      as Map<String, dynamic>;
  final chunkSize = _asInt(session['chunk_size'], fallback: preferredChunkBytes);
  final totalChunks = _asInt(session['total_chunks'], fallback: 1);
  var uploadedChunks = _asInt(session['uploaded_chunks']);

  if (uploadedChunks > 0) {
    onProgress?.call(math.min(length, uploadedChunks * chunkSize), length);
  }

  final handle = await file.open();
  try {
    for (var index = uploadedChunks; index < totalChunks; index += 1) {
      if (isCancelled?.call() ?? false) {
        throw const UploadCancelled();
      }
      final start = index * chunkSize;
      final size = math.min(chunkSize, length - start);
      final bytes = await handle.read(size);
      await _sendChunkWithRetry(
        baseUrl: baseUrl,
        token: token,
        mediaId: mediaId,
        index: index,
        bytes: bytes,
        isCancelled: isCancelled,
      );
      uploadedChunks = index + 1;
      onProgress?.call(math.min(length, uploadedChunks * chunkSize), length);
    }
  } finally {
    await handle.close();
  }

  await _postJson(baseUrl, token, '/api/media/$mediaId/upload/finish', {
    'size': length,
  });
  return true;
}

Future<void> _sendChunkWithRetry({
  required String baseUrl,
  required String? token,
  required String mediaId,
  required int index,
  required List<int> bytes,
  bool Function()? isCancelled,
}) async {
  var attempt = 0;
  while (true) {
    try {
      await _sendChunk(
        baseUrl: baseUrl,
        token: token,
        mediaId: mediaId,
        index: index,
        bytes: bytes,
      );
      return;
    } catch (error) {
      if (isCancelled?.call() ?? false) rethrow;
      if (!_isTransient(error) || attempt >= 2) rethrow;
      attempt += 1;
      await Future<void>.delayed(Duration(milliseconds: 1000 * (1 << (attempt - 1))));
    }
  }
}

Future<void> _sendChunk({
  required String baseUrl,
  required String? token,
  required String mediaId,
  required int index,
  required List<int> bytes,
}) async {
  final uri = Uri.parse('$baseUrl/api/media/$mediaId/upload/chunk?index=$index');
  final headers = <String, String>{'Content-Type': 'application/octet-stream'};
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  http.Response response;
  try {
    response = await http
        .post(uri, headers: headers, body: bytes)
        .timeout(_chunkTimeout);
  } on TimeoutException {
    throw ApiException(408, 'chunk upload timed out');
  } on http.ClientException catch (error) {
    throw ApiException(0, error.message);
  }
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, _message(response));
  }
}

Future<Map<String, dynamic>> _postJson(
  String baseUrl,
  String? token,
  String path,
  Map<String, dynamic> body,
) async {
  final headers = <String, String>{'Content-Type': 'application/json'};
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  http.Response response;
  try {
    response = await http
        .post(Uri.parse('$baseUrl$path'), headers: headers, body: jsonEncode(body))
        .timeout(_jsonTimeout);
  } on TimeoutException {
    throw ApiException(408, 'request timed out');
  } on http.ClientException catch (error) {
    throw ApiException(0, error.message);
  }
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, _message(response));
  }
  if (response.body.isEmpty) return const {};
  final decoded = jsonDecode(response.body);
  return decoded is Map<String, dynamic> ? decoded : const {};
}

bool _isTransient(Object error) {
  if (error is UploadCancelled) return false;
  if (error is ApiException) {
    final code = error.statusCode;
    return code == 0 || code == 408 || code == 429 || code >= 500;
  }
  if (error is TimeoutException) return true;
  final text = error.toString();
  return text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('timed out') ||
      text.contains('Connection');
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

String _message(http.Response response) {
  try {
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return (decoded['message'] ?? decoded['error'] ?? 'upload failed')
          .toString();
    }
  } catch (_) {}
  return 'upload failed (${response.statusCode})';
}
