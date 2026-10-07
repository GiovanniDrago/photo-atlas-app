import 'media_restore_service_stub.dart'
    if (dart.library.io) 'media_restore_service_io.dart'
    as impl;

/// Where a cloud-only file was put after the in-app download.
class MediaRestoreResult {
  final String destination;

  /// True when the file went back to its original device folder.
  final bool originalFolder;

  const MediaRestoreResult({
    required this.destination,
    required this.originalFolder,
  });
}

/// True when the platform can put a downloaded file back into the device
/// library (Android MediaStore, desktop file system); false on web.
bool get canRestoreInApp => impl.canRestoreInApp;

/// Downloads a cloud file and saves it back on the device: the original
/// folder when available, the downloads folder otherwise.
Future<MediaRestoreResult> restoreCloudMedia({
  required String url,
  required String filename,
  required String mediaType,
  String? originalPath,
  void Function(int sent, int? total)? onProgress,
}) {
  return impl.restoreCloudMedia(
    url: url,
    filename: filename,
    mediaType: mediaType,
    originalPath: originalPath,
    onProgress: onProgress,
  );
}
