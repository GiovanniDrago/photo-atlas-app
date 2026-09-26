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

  /// Bytes of the single file being uploaded right now.
  final int fileSent;
  final int fileTotal;

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
    this.fileSent = 0,
    this.fileTotal = 0,
  });

  /// 0..1 progress of the single file, null when unknown.
  double? get fileFraction {
    if (fileTotal <= 0) return null;
    return (fileSent / fileTotal).clamp(0.0, 1.0);
  }

  /// Overall progress, smoothed with the bytes of the current file.
  double? get overallFraction {
    if (total <= 0) return null;
    final current = running ? (fileFraction ?? 0) : 0.0;
    return ((done + current) / total).clamp(0.0, 1.0);
  }

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
      // Item boundary events carry no bytes: the counter restarts.
      fileSent: progress.fileSent ?? 0,
      fileTotal: progress.fileTotal ?? 0,
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
    int? fileSent,
    int? fileTotal,
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
      fileSent: fileSent ?? this.fileSent,
      fileTotal: fileTotal ?? this.fileTotal,
    );
  }
}

/// Keeps byte updates to roughly one per percent (plus the last one), so a
/// large video does not rebuild the UI on every chunk.
class FileProgressThrottle {
  int _lastSent = 0;
  int? _itemIndex;

  bool shouldEmit(GalleryActionProgress progress) {
    final sent = progress.fileSent;
    final total = progress.fileTotal;
    if (sent == null || total == null || total <= 0) return true;
    if (_itemIndex != progress.done) {
      _itemIndex = progress.done;
      _lastSent = 0;
    }
    if (sent >= total) {
      _lastSent = sent;
      return true;
    }
    if ((sent - _lastSent) * 100 < total) return false;
    _lastSent = sent;
    return true;
  }
}
