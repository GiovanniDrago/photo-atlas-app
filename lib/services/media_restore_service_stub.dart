import 'media_restore_service.dart';

bool get canRestoreInApp => false;

Future<MediaRestoreResult> restoreCloudMedia({
  required String url,
  required String filename,
  required String mediaType,
  String? originalPath,
  void Function(int sent, int? total)? onProgress,
}) async {
  throw UnsupportedError('restore is not available on this platform');
}
