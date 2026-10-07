import 'download_service_stub.dart'
    if (dart.library.io) 'download_service_io.dart'
    as impl;

/// Copies a device file into a temporary folder so it can be shared.
Future<String> prepareShareFile({
  required String path,
  required String filename,
}) {
  return impl.prepareShareFile(path: path, filename: filename);
}

/// Downloads a remote file into a temporary folder so it can be shared.
Future<String> downloadShareFile({
  required String url,
  required String filename,
  Map<String, String> headers = const {},
}) {
  return impl.downloadShareFile(url: url, filename: filename, headers: headers);
}

/// Downloads a remote file into the temporary folder, reporting the bytes
/// received. The generous timeout keeps large videos on slow links possible.
Future<String> downloadToFile({
  required String url,
  required String filename,
  Duration timeout = const Duration(minutes: 30),
  void Function(int sent, int? total)? onProgress,
}) {
  return impl.downloadToFile(
    url: url,
    filename: filename,
    timeout: timeout,
    onProgress: onProgress,
  );
}
