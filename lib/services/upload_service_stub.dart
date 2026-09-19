import 'api_client.dart';

Future<void> uploadFileToApi({
  required String baseUrl,
  required String? token,
  required String mediaId,
  required String filePath,
  String? destination,
  void Function(int sent, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  throw ApiException(400, 'backup uploads are not available on the web');
}
