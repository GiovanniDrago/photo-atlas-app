import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import 'download_service.dart';
import 'media_restore_service.dart';

bool get canRestoreInApp => true;

/// Downloads the cloud file and puts it back into the device library: the
/// original folder when it can be written, the downloads folder otherwise.
Future<MediaRestoreResult> restoreCloudMedia({
  required String url,
  required String filename,
  required String mediaType,
  String? originalPath,
  void Function(int sent, int? total)? onProgress,
}) async {
  final tempPath = await downloadToFile(
    url: url,
    filename: filename,
    onProgress: onProgress,
  );
  try {
    if (Platform.isAndroid) {
      return await _saveToAndroidLibrary(
        tempPath: tempPath,
        filename: filename,
        mediaType: mediaType,
        originalPath: originalPath,
      );
    }
    return await _saveToDesktop(
      tempPath: tempPath,
      filename: filename,
      originalPath: originalPath,
    );
  } finally {
    await File(tempPath).delete().catchError((_) => File(tempPath));
  }
}

/// MediaStore insert with the original relative folder; falls back to the
/// downloads folder when the original path is not usable.
Future<MediaRestoreResult> _saveToAndroidLibrary({
  required String tempPath,
  required String filename,
  required String mediaType,
  String? originalPath,
}) async {
  final relative = _androidRelativePath(originalPath);
  if (relative != null) {
    final saved = await _saveToMediaStore(
      tempPath: tempPath,
      filename: filename,
      mediaType: mediaType,
      relativePath: relative,
    );
    if (saved != null) {
      return MediaRestoreResult(destination: relative, originalFolder: true);
    }
  }
  final saved = await _saveToMediaStore(
    tempPath: tempPath,
    filename: filename,
    mediaType: mediaType,
    relativePath: 'Download',
  );
  if (saved == null) {
    throw FileSystemException('the device library rejected $filename');
  }
  return const MediaRestoreResult(destination: 'Download', originalFolder: false);
}

Future<AssetEntity?> _saveToMediaStore({
  required String tempPath,
  required String filename,
  required String mediaType,
  required String relativePath,
}) async {
  try {
    if (mediaType == 'video') {
      return await PhotoManager.editor.saveVideo(
        File(tempPath),
        title: filename,
        relativePath: relativePath,
      );
    }
    return await PhotoManager.editor.saveImageWithPath(
      tempPath,
      title: filename,
      relativePath: relativePath,
    );
  } catch (_) {
    return null;
  }
}

/// `DCIM/Camera` from `/storage/emulated/0/DCIM/Camera/x.mp4`; null for
/// missing paths, other volumes (SD cards) or files at the volume root.
String? _androidRelativePath(String? path) {
  if (path == null || path.isEmpty) return null;
  const primary = '/storage/emulated/0/';
  if (!path.startsWith(primary)) return null;
  final relative = path.substring(primary.length);
  final index = relative.lastIndexOf('/');
  if (index <= 0) return null;
  final folder = relative.substring(0, index);
  if (folder.isEmpty || folder.startsWith('.')) return null;
  return folder;
}

/// Desktop: back to the original path when the folder exists, otherwise the
/// downloads folder.
Future<MediaRestoreResult> _saveToDesktop({
  required String tempPath,
  required String filename,
  String? originalPath,
}) async {
  final name = _safeName(filename);
  if (originalPath != null && originalPath.isNotEmpty) {
    final target = File(originalPath);
    if (await target.parent.exists()) {
      try {
        await File(tempPath).copy(target.path);
        return MediaRestoreResult(
          destination: target.parent.path,
          originalFolder: true,
        );
      } catch (_) {
        // Fall through to the downloads folder.
      }
    }
  }
  final downloads = await getDownloadsDirectory();
  final directory = downloads ?? await getTemporaryDirectory();
  final target = File('${directory.path}/$name');
  await File(tempPath).copy(target.path);
  return MediaRestoreResult(
    destination: directory.path,
    originalFolder: false,
  );
}

String _safeName(String value) {
  final cleaned = value.replaceAll(RegExp(r'[/\\]'), '_').trim();
  return cleaned.isEmpty ? 'photo-atlas' : cleaned;
}
