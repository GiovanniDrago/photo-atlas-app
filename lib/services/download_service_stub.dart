Future<String> prepareShareFile({
  required String path,
  required String filename,
}) async {
  throw UnsupportedError('sharing is not available on this platform');
}

Future<String> downloadShareFile({
  required String url,
  required String filename,
  Map<String, String> headers = const {},
}) async {
  throw UnsupportedError('sharing is not available on this platform');
}

Future<String> downloadToFile({
  required String url,
  required String filename,
  Duration timeout = const Duration(minutes: 30),
  void Function(int sent, int? total)? onProgress,
}) async {
  throw UnsupportedError('downloading is not available on this platform');
}
