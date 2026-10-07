import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';

const _folder = 'photo-atlas-share';

Future<Directory> _shareDirectory() async {
  final root = await getTemporaryDirectory();
  final directory = Directory('${root.path}/$_folder');
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
  await directory.create(recursive: true);
  return directory;
}

String _safeName(String value) {
  final cleaned = value.replaceAll(RegExp(r'[/\\]'), '_').trim();
  return cleaned.isEmpty ? 'photo-atlas' : cleaned;
}

Future<String> prepareShareFile({
  required String path,
  required String filename,
}) async {
  final directory = await _shareDirectory();
  final target = File('${directory.path}/${_safeName(filename)}');
  await File(path).copy(target.path);
  return target.path;
}

Future<String> downloadShareFile({
  required String url,
  required String filename,
  Map<String, String> headers = const {},
}) async {
  final directory = await _shareDirectory();
  final target = File('${directory.path}/${_safeName(filename)}');
  final request = http.Request('GET', Uri.parse(url));
  request.headers.addAll(headers);
  final response = await request.send().timeout(const Duration(minutes: 5));
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, 'download failed');
  }
  final sink = target.openWrite();
  try {
    await response.stream.pipe(sink);
  } finally {
    await sink.close();
  }
  return target.path;
}

/// Downloads to the temporary folder with progress. The overall timeout only
/// guards the response headers; the stream has an inactivity timeout so a
/// stalled connection fails instead of hanging forever.
Future<String> downloadToFile({
  required String url,
  required String filename,
  Duration timeout = const Duration(minutes: 30),
  void Function(int sent, int? total)? onProgress,
}) async {
  final root = await getTemporaryDirectory();
  final directory = Directory('${root.path}/photo-atlas-restore');
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  final target = File('${directory.path}/${_safeName(filename)}');
  final request = http.Request('GET', Uri.parse(url));
  final response = await request.send().timeout(timeout);
  if (response.statusCode >= 400) {
    throw ApiException(response.statusCode, 'download failed');
  }
  final total = response.contentLength;
  var sent = 0;
  final sink = target.openWrite();
  try {
    await for (final chunk in response.stream.timeout(const Duration(minutes: 5))) {
      sink.add(chunk);
      sent += chunk.length;
      onProgress?.call(sent, total);
    }
    await sink.close();
  } catch (_) {
    await sink.close().catchError((_) {});
    await target.delete().catchError((_) => target);
    rethrow;
  }
  return target.path;
}
