import 'dart:io';

import 'package:video_player/video_player.dart';

import '../models/gallery_entry.dart';

Future<VideoPlayerController?> videoControllerForLocal(LocalMedia media) async {
  final asset = media.asset;
  if (asset != null) {
    try {
      final file = await asset.file;
      if (file != null && file.path.isNotEmpty) {
        return VideoPlayerController.file(file);
      }
    } catch (_) {
      // Fall through to the plain path below.
    }
  }
  final path = media.path;
  if (path != null && path.isNotEmpty) {
    return VideoPlayerController.file(File(path));
  }
  return null;
}
