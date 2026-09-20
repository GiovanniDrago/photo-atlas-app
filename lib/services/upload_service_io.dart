import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_client.dart';

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
