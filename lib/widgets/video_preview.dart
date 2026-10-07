import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../l10n/app_localizations.dart';
import '../models/gallery_entry.dart';
import 'video_controller_source.dart';

/// Tap-to-play video page: the device file when available, the kDrive stream
/// otherwise. Falls back to [poster] when playback is not possible.
class VideoPreview extends StatefulWidget {
  final GalleryEntry entry;
  final Widget poster;

  const VideoPreview({super.key, required this.entry, required this.poster});

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  VideoPlayerController? _controller;
  bool _starting = false;
  String? _error;

  Future<void> _start() async {
    if (_starting || _controller != null) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    VideoPlayerController? controller;
    try {
      controller = await _createController();
      await controller.initialize();
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _starting = false;
      });
    } catch (error) {
      await controller?.dispose();
      if (mounted) {
        setState(() {
          _error = '$error';
          _starting = false;
        });
      }
    }
  }

  Future<VideoPlayerController> _createController() async {
    final local = widget.entry.local;
    if (local != null) {
      final controller = await videoControllerForLocal(local);
      if (controller != null) return controller;
    }
    final url = widget.entry.cloud?.streamUrl;
    if (url != null && url.isNotEmpty) {
      return VideoPlayerController.networkUrl(Uri.parse(url));
    }
    throw StateError('no video source');
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = _controller;
    if (controller == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.poster,
          if (_starting)
            const Center(child: CircularProgressIndicator())
          else
            Center(
              child: IconButton(
                onPressed: _start,
                iconSize: 72,
                color: Colors.white,
                icon: const Icon(Icons.play_circle_fill),
              ),
            ),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Text(
                l10n.videoPlaybackError,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlay,
          ),
        ),
        Positioned(left: 8, right: 8, bottom: 8, child: _controls(controller)),
      ],
    );
  }

  Widget _controls(VideoPlayerController controller) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: _togglePlay,
                color: Colors.white,
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              Expanded(
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white30,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _timeLabel(value.position, value.duration),
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
              const SizedBox(width: 8),
            ],
          ),
        );
      },
    );
  }

  static String _timeLabel(Duration position, Duration duration) {
    String two(int value) => value.toString().padLeft(2, '0');
    final pos = '${two(position.inMinutes)}:${two(position.inSeconds % 60)}';
    final total = '${two(duration.inMinutes)}:${two(duration.inSeconds % 60)}';
    return '$pos / $total';
  }
}
