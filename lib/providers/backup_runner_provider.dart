import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/backup.dart';
import '../models/source.dart';
import '../services/auto_backup_service.dart';
import '../services/backup_progress_store.dart';
import '../services/backup_service.dart';
import '../services/local_scan_service.dart';
import 'collections_providers.dart';
import 'gallery_providers.dart';
import 'library_providers.dart';

class BackupRunnerState {
  final BackupRunProgress? progress;
  final List<BackupQueueItem> queue;

  const BackupRunnerState({this.progress, this.queue = const []});

  bool get active => progress != null || queue.isNotEmpty;
  bool get starting => progress == null && queue.isNotEmpty;
  int get queued => queue.isEmpty ? 0 : queue.length - 1;

  /// No progress after ~90s: the job did not start (permissions, WorkManager
  /// deferral); the banner offers a retry.
  bool get waitingTooLong {
    if (!starting) return false;
    final since = queue.first.enqueuedAtMs;
    if (since == 0) return false;
    return DateTime.now().millisecondsSinceEpoch - since > 90000;
  }
}

/// Starts the folder backups and follows their progress. On Android the work
/// runs in a WorkManager one-off task with a foreground service (it survives
/// the app being closed); the app only reads the progress from the store.
class BackupRunner extends Notifier<BackupRunnerState> {
  static const _catchUpInterval = Duration(minutes: 15);

  Timer? _timer;
  DateTime? _lastCatchUp;

  @override
  BackupRunnerState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    unawaited(_restore());
    return const BackupRunnerState();
  }

  /// Picks up a run that was already going when the app was closed.
  Future<void> _restore() async {
    final progress = await BackupProgressStore.read();
    final queue = await BackupProgressStore.readQueue();
    if (progress == null && queue.isEmpty) return;
    if (progress != null && progress.finished) {
      state = BackupRunnerState(queue: queue);
      await BackupProgressStore.clear();
      await BackupProgressStore.writeQueue(const []);
      _invalidateAll();
      return;
    }
    state = BackupRunnerState(progress: progress, queue: queue);
    _startPolling();
  }

  Future<void> enqueue({
    required String sourceId,
    required String label,
    required String rootPath,
  }) async {
    final queue = await BackupProgressStore.readQueue();
    if (queue.any((item) => item.sourceId == sourceId) ||
        state.progress?.sourceId == sourceId) {
      return;
    }
    queue.add(
      BackupQueueItem(
        sourceId: sourceId,
        label: label,
        enqueuedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await BackupProgressStore.writeQueue(queue);
    state = BackupRunnerState(progress: state.progress, queue: queue);
    _startPolling();
    if (AutoBackupService.isSupported) {
      await AutoBackupService.registerManualRun(
        sourceId: sourceId,
        label: label,
      );
      return;
    }
    unawaited(_runInline(sourceId: sourceId, label: label, rootPath: rootPath));
  }

  /// Starts the folders enabled for automatic upload that still have pending
  /// files (or that have not run recently). Called when the app opens and
  /// comes back to the foreground: while the app is open uploads start right
  /// away, the periodic schedule only matters when it is closed.
  Future<void> catchUp() async {
    if (!AutoBackupService.isSupported) return;
    if (state.active) return;
    final now = DateTime.now();
    final last = _lastCatchUp;
    if (last != null && now.difference(last) < _catchUpInterval) return;
    _lastCatchUp = now;

    BackupStatusSnapshot snapshot;
    try {
      snapshot = await ref.read(backupStatusProvider.future);
    } catch (_) {
      return;
    }
    final sources = ref.read(sourcesProvider).value ?? const <MediaSource>[];
    final rootPaths = {
      for (final source in sources) source.id: source.rootPath ?? '',
    };
    for (final source in snapshot.sources) {
      if (!source.autoBackup) continue;
      final lastRun = source.backupLastRunAt;
      final needsRun =
          source.pending > 0 ||
          lastRun == null ||
          now.difference(lastRun) > _catchUpInterval;
      if (!needsRun) continue;
      await enqueue(
        sourceId: source.id,
        label: source.label,
        rootPath: rootPaths[source.id] ?? '',
      );
    }
  }

  /// Drops the stuck queue entry and starts it again.
  Future<void> retry() async {
    final queue = await BackupProgressStore.readQueue();
    if (queue.isEmpty) return;
    final first = queue.first;
    final rootPaths = {
      for (final source
          in ref.read(sourcesProvider).value ?? const <MediaSource>[])
        source.id: source.rootPath ?? '',
    };
    await cancel();
    await enqueue(
      sourceId: first.sourceId,
      label: first.label,
      rootPath: rootPaths[first.sourceId] ?? '',
    );
  }

  Future<void> cancel() async {
    await BackupProgressStore.requestCancel();
    if (AutoBackupService.isSupported) {
      await AutoBackupService.cancelManualRuns();
    }
    await BackupProgressStore.writeQueue(const []);
    state = BackupRunnerState(progress: state.progress, queue: const []);
    _startPolling();
  }

  /// Desktop fallback: no WorkManager, the run happens in the app process.
  Future<void> _runInline({
    required String sourceId,
    required String label,
    required String rootPath,
  }) async {
    final client = ref.read(apiClientProvider);
    var progress = BackupRunProgress(
      sourceId: sourceId,
      label: label,
      phase: 'scanning',
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await BackupProgressStore.write(progress);
    try {
      await LocalScanService(client).scanSource(
        sourceId: sourceId,
        rootPath: rootPath,
        onProgress: (seen, indexed) {
          progress = progress.copyWith(total: seen);
          unawaited(BackupProgressStore.write(progress));
        },
      );
      progress = progress.copyWith(
        phase: 'uploading',
        uploaded: 0,
        failed: 0,
        total: 0,
      );
      await BackupProgressStore.write(progress);
      await BackupService(client).runBackup(
        sourceId: sourceId,
        onProgress: (value) {
          progress = progress.copyWith(
            uploaded: value.uploaded,
            failed: value.failed,
            total: value.total,
            currentName: value.currentName,
          );
          unawaited(BackupProgressStore.write(progress));
        },
      );
    } catch (error) {
      progress = progress.copyWith(error: '$error');
    } finally {
      await BackupProgressStore.write(
        progress.copyWith(finishedAtMs: DateTime.now().millisecondsSinceEpoch),
      );
    }
  }

  void _startPolling() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_poll()),
    );
    unawaited(_poll());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    final progress = await BackupProgressStore.read();
    final queue = await BackupProgressStore.readQueue();
    if (progress != null && progress.finished) {
      _stopPolling();
      state = const BackupRunnerState();
      await BackupProgressStore.clear();
      await BackupProgressStore.writeQueue(const []);
      _invalidateAll();
      return;
    }
    state = BackupRunnerState(progress: progress, queue: queue);
    if (progress == null && queue.isEmpty) _stopPolling();
  }

  void _invalidateAll() {
    ref.invalidate(sourcesProvider);
    ref.invalidate(backupStatusProvider);
    ref.invalidate(deviceFoldersProvider);
    ref.invalidate(folderThumbProvider);
    ref.invalidate(galleryProvider);
  }
}

final backupRunnerProvider = NotifierProvider<BackupRunner, BackupRunnerState>(
  BackupRunner.new,
);
