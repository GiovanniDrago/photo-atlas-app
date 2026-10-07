import '../models/gallery_entry.dart';
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

/// Outcome of restoring a device file that sits in the Android system trash.
enum TrashRestoreOutcome {
  restored,

  /// The system prompt was dismissed.
  cancelled,

  /// No trash support (web, desktop, Android < 11, missing asset).
  unsupported,
}

/// True when the platform can put a downloaded file back into the device
/// library (Android MediaStore, desktop file system); false on web.
bool get canRestoreInApp => impl.canRestoreInApp;

/// True when the platform has an Android system trash to restore from.
bool get canRestoreFromTrash => impl.canRestoreFromTrash;

/// Asks the system to restore a trashed device file (Android 11+ shows a
/// confirmation prompt; the app must stay in the foreground).
Future<TrashRestoreOutcome> restoreFromDeviceTrash(LocalMedia media) {
  return impl.restoreFromDeviceTrash(media);
}

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
