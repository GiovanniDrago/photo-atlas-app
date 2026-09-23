import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

/// Starts the folder backups and follows their progress. On Android the work
/// runs in a WorkManager one-off task with a foreground service (it survives
/// the app being closed); the app only reads the progress from the store.
class BackupRunner extends Notifier<BackupRunnerState> {
  Timer? _timer;

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
    queue.add(BackupQueueItem(sourceId: sourceId, label: label));
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
