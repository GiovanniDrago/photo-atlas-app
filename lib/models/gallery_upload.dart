import '../services/gallery_actions_service.dart';
import 'gallery_entry.dart';

enum UploadEntryStatus { pending, current, done, failed }

/// State of an in-app upload run (gallery selection, album retry), rendered by
/// the tappable bottom bar and by the progress sheet.
class GalleryUploadState {
  static const _unset = Object();

  final String label;
  final List<GalleryEntry> targets;
  final int done;
  final int total;
  final String? currentName;

  /// Failure reason by target index (the progress callback reports the index it
  /// just processed).
  final Map<int, String?> failures;
  final bool running;
  final bool stopping;
  final int uploaded;
  final int failed;
  final bool cancelled;

  const GalleryUploadState({
    required this.label,
    this.targets = const [],
    this.done = 0,
    this.total = 0,
    this.currentName,
    this.failures = const {},
    this.running = true,
    this.stopping = false,
    this.uploaded = 0,
    this.failed = 0,
    this.cancelled = false,
  });

  UploadEntryStatus statusAt(int index) {
    if (failures.containsKey(index)) return UploadEntryStatus.failed;
    if (index < done) return UploadEntryStatus.done;
    if (running && index == done) return UploadEntryStatus.current;
    return UploadEntryStatus.pending;
  }

  GalleryUploadState record(GalleryActionProgress progress) {
    final failedName = progress.failedName;
    return copyWith(
      done: progress.done,
      total: progress.total,
      currentName: progress.currentName,
      failures: failedName == null
          ? failures
          : {...failures, progress.done: progress.error},
    );
  }

  GalleryUploadState markStopping() => copyWith(stopping: true);

  GalleryUploadState finish({
    required int uploaded,
    required int failed,
    required bool cancelled,
  }) {
    return GalleryUploadState(
      label: label,
      targets: targets,
      done: total,
      total: total,
      currentName: null,
      failures: failures,
      running: false,
      stopping: false,
      uploaded: uploaded,
      failed: failed,
      cancelled: cancelled,
    );
  }

  GalleryUploadState copyWith({
    int? done,
    int? total,
    Object? currentName = _unset,
    Map<int, String?>? failures,
    bool? running,
    bool? stopping,
    int? uploaded,
    int? failed,
    bool? cancelled,
  }) {
    return GalleryUploadState(
      label: label,
      targets: targets,
      done: done ?? this.done,
      total: total ?? this.total,
      currentName: identical(currentName, _unset)
          ? this.currentName
          : currentName as String?,
      failures: failures ?? this.failures,
      running: running ?? this.running,
      stopping: stopping ?? this.stopping,
      uploaded: uploaded ?? this.uploaded,
      failed: failed ?? this.failed,
      cancelled: cancelled ?? this.cancelled,
    );
  }
}
