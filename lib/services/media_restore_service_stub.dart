import '../models/gallery_entry.dart';
import 'media_restore_service.dart';

bool get canRestoreInApp => false;

bool get canRestoreFromTrash => false;

Future<TrashRestoreOutcome> restoreFromDeviceTrash(LocalMedia media) async {
  return TrashRestoreOutcome.unsupported;
}

Future<MediaRestoreResult> restoreCloudMedia({
  required String url,
  required String filename,
  required String mediaType,
  String? originalPath,
  void Function(int sent, int? total)? onProgress,
}) async {
  throw UnsupportedError('restore is not available on this platform');
}
