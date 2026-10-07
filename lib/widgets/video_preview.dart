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
  bool _scrubbing = false;
  Duration? _scrubPosition;

  Future<void> _start() async {
    if (_starting || _controller != null) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    Object? lastError;
    for (final build in _sources()) {
      VideoPlayerController? controller;
      try {
        controller = await build();
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
        return;
      } catch (error) {
        // A broken device file must not block the kDrive stream.
        lastError = error;
        await controller?.dispose();
      }
    }
    if (mounted) {
      setState(() {
        _error = lastError == null ? 'no video source' : '$lastError';
        _starting = false;
      });
    }
  }

  /// Playback candidates in order: the device file (when usable) and then the
  /// kDrive stream.
  List<Future<VideoPlayerController> Function()> _sources() {
    final candidates = <Future<VideoPlayerController> Function()>[];
    final local = widget.entry.hasLocal ? widget.entry.local : null;
    if (local != null) {
      candidates.add(() async {
        final controller = await videoControllerForLocal(local);
        if (controller == null) throw StateError('no local file');
        return controller;
      });
    }
    final url = widget.entry.cloud?.streamUrl;
    if (url != null && url.isNotEmpty) {
      candidates.add(
        () async => VideoPlayerController.networkUrl(Uri.parse(url)),
      );
    }
    return candidates;
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

  void _seekBy(Duration delta) {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    var target = value.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    final duration = value.duration;
    if (duration > Duration.zero && target > duration) target = duration;
    controller.seekTo(target);
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
        final duration = value.duration;
        final position = _scrubbing
            ? (_scrubPosition ?? value.position)
            : value.position;
        final maxMs = duration.inMilliseconds;
        final valueMs = position.inMilliseconds
            .clamp(0, maxMs > 0 ? maxMs : 0)
            .toDouble();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: _togglePlay,
                color: Colors.white,
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              IconButton(
                tooltip: '-10s',
                onPressed: () => _seekBy(const Duration(seconds: -10)),
                color: Colors.white,
                icon: const Icon(Icons.replay_10),
              ),
              IconButton(
                tooltip: '+10s',
                onPressed: () => _seekBy(const Duration(seconds: 10)),
                color: Colors.white,
                icon: const Icon(Icons.forward_10),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                  ),
                  child: Slider(
                    value: valueMs,
                    max: maxMs > 0 ? maxMs.toDouble() : 1,
                    onChanged: maxMs > 0
                        ? (ms) => setState(() {
                            _scrubbing = true;
                            _scrubPosition = Duration(milliseconds: ms.round());
                          })
                        : null,
                    onChangeEnd: maxMs > 0
                        ? (ms) {
                            controller.seekTo(
                              Duration(milliseconds: ms.round()),
                            );
                            setState(() {
                              _scrubbing = false;
                              _scrubPosition = null;
                            });
                          }
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _timeLabel(position, duration),
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
