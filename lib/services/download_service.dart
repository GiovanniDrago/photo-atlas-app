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
