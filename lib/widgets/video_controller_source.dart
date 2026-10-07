import 'package:video_player/video_player.dart';

import '../models/gallery_entry.dart';
import 'video_controller_source_stub.dart'
    if (dart.library.io) 'video_controller_source_io.dart'
    as impl;

/// A file-based controller for a device video, or null on platforms without a
/// file system (web); the caller then falls back to the kDrive stream.
Future<VideoPlayerController?> videoControllerForLocal(LocalMedia media) {
  return impl.videoControllerForLocal(media);
}
