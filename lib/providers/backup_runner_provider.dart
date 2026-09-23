import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/backup.dart';
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
  final List<String> log;

  const BackupRunnerState({
    this.progress,
    this.queue = const [],
    this.log = const [],
  });

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
    state = BackupRunnerState(
      progress: progress,
      queue: queue,
      log: await BackupRunLog.read(),
    );
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
    state = BackupRunnerState(
      progress: state.progress,
      queue: queue,
      log: state.log,
    );
    _startPolling();
    final active = await BackupProgressStore.read();
    if (active != null && !active.finished) return;
    await _startNext(queue.first);
  }

  /// Starts one queued folder: in this process while the app is open, in the
  /// background job otherwise. Only one run at a time.
  Future<void> _startNext(BackupQueueItem item) async {
    final rootPath = (await _rootPaths())[item.sourceId] ?? '';
    if (!AutoBackupService.isSupported) {
      unawaited(
        runInApp(
          sourceId: item.sourceId,
          label: item.label,
          rootPath: rootPath,
          handoffOnBackground: false,
        ),
      );
      return;
    }
    if (_isForeground) {
      unawaited(
        runInApp(
          sourceId: item.sourceId,
          label: item.label,
          rootPath: rootPath,
        ),
      );
      return;
    }
    await AutoBackupService.registerManualRun(
      sourceId: item.sourceId,
      label: item.label,
    );
  }

  bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
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
    final rootPaths = await _rootPaths();
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

  /// Source id -> root path, waiting for the list when it is not loaded yet.
  Future<Map<String, String>> _rootPaths() async {
    try {
      final sources = await ref.read(sourcesProvider.future);
      return {for (final source in sources) source.id: source.rootPath ?? ''};
    } catch (_) {
      return const {};
    }
  }

  /// Drops the stuck queue entry and starts it again in the background.
  Future<void> retry() async {
    final queue = await BackupProgressStore.readQueue();
    if (queue.isEmpty) return;
    final first = queue.first;
    final rootPaths = await _rootPaths();
    await cancel();
    await enqueue(
      sourceId: first.sourceId,
      label: first.label,
      rootPath: rootPaths[first.sourceId] ?? '',
    );
  }

  /// Starts the first queued folder right away, in this process.
  Future<void> runNow() async {
    if (state.progress != null) return;
    final queue = await BackupProgressStore.readQueue();
    if (queue.isEmpty) return;
    await BackupProgressStore.clearCancel();
    if (AutoBackupService.isSupported) {
      await AutoBackupService.cancelManualRuns();
    }
    await BackupRunLog.add('avvio manuale: ${queue.first.label}');
    await _startNext(queue.first);
  }

  /// Sends the first queued folder to the background job again.
  Future<void> retryBackground() async {
    final queue = await BackupProgressStore.readQueue();
    if (queue.isEmpty) return;
    await BackupProgressStore.clearCancel();
    if (!AutoBackupService.isSupported) return;
    await BackupRunLog.add('riprovo in background: ${queue.first.label}');
    await AutoBackupService.registerManualRun(
      sourceId: queue.first.sourceId,
      label: queue.first.label,
    );
  }

  Future<void> cancel() async {
    await BackupProgressStore.requestCancel();
    if (AutoBackupService.isSupported) {
      await AutoBackupService.cancelManualRuns();
    }
    await BackupProgressStore.writeQueue(const []);
    final current = await BackupProgressStore.read();
    if (current != null && !current.finished) {
      await BackupProgressStore.write(
        current.copyWith(finishedAtMs: DateTime.now().millisecondsSinceEpoch),
      );
    }
    state = BackupRunnerState(progress: state.progress, queue: const []);
    _startPolling();
  }

  /// Runs scan + upload in the app process. When the app goes to the
  /// background the run is handed over to the foreground service job (the
  /// atomic claims on the server make sure no file is uploaded twice).
  Future<void> runInApp({
    required String sourceId,
    required String label,
    required String rootPath,
    bool handoffOnBackground = true,
  }) async {
    final client = ref.read(apiClientProvider);
    var autoResumed = false;
    final watcher = _LifecycleWatcher(() {
      if (!handoffOnBackground) return;
      unawaited(() async {
        await BackupRunLog.add(
          'app in background: il run continua nel foreground service',
        );
        await AutoBackupService.registerManualRun(
          sourceId: sourceId,
          label: label,
        );
        final handoffAt = DateTime.now().millisecondsSinceEpoch;
        await Future<void>.delayed(const Duration(seconds: 60));
        final current = await BackupProgressStore.read();
        final alive =
            current != null &&
            !current.finished &&
            current.updatedAtMs > handoffAt;
        if (alive || autoResumed) return;
        autoResumed = true;
        await BackupRunLog.add(
          'il job in background non è partito: riprendo in-app',
        );
        await runInApp(
          sourceId: sourceId,
          label: label,
          rootPath: rootPath,
          handoffOnBackground: false,
        );
      }());
    });
    WidgetsBinding.instance.addObserver(watcher);
    var cancelled = false;
    final cancelWatcher = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (await BackupProgressStore.cancelRequested()) cancelled = true;
    });
    bool stop() => cancelled || watcher.backgrounded;

    var progress = BackupRunProgress(
      sourceId: sourceId,
      label: label,
      phase: 'scanning',
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await BackupProgressStore.write(progress);
    await BackupRunLog.add('run in-app: $label');
    try {
      final scan = await LocalScanService(client).scanSource(
        sourceId: sourceId,
        rootPath: rootPath,
        isCancelled: stop,
        onProgress: (seen, indexed) {
          progress = progress.copyWith(total: seen);
          unawaited(BackupProgressStore.write(progress));
        },
      );
      await BackupRunLog.add('scansione: ${scan.filesSeen} file');
      if (!stop()) {
        progress = progress.copyWith(
          phase: 'uploading',
          uploaded: 0,
          failed: 0,
          total: 0,
        );
        await BackupProgressStore.write(progress);
        await BackupRunLog.add('upload: $label');
        await BackupService(client).runBackup(
          sourceId: sourceId,
          isCancelled: stop,
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
        await BackupRunLog.add('upload terminato: $label');
      }
    } catch (error) {
      progress = progress.copyWith(error: '$error');
      await BackupRunLog.add('errore: $error');
    } finally {
      cancelWatcher.cancel();
      WidgetsBinding.instance.removeObserver(watcher);
      if (watcher.backgrounded && handoffOnBackground) {
        await BackupRunLog.add('run in-app sospeso (continua in background)');
      } else {
        await BackupProgressStore.write(
          progress.copyWith(
            finishedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
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
    var progress = await BackupProgressStore.read();
    final queue = await BackupProgressStore.readQueue();
    final log = await BackupRunLog.read();
    if (progress != null && !progress.finished) {
      final last = progress.updatedAtMs != 0
          ? progress.updatedAtMs
          : progress.startedAtMs;
      final age = DateTime.now().millisecondsSinceEpoch - last;
      if (last != 0 && age > 180000) {
        await BackupRunLog.add('run fermo da oltre 3 minuti: lo chiudo');
        await BackupProgressStore.write(
          progress.copyWith(
            error: 'stalled',
            finishedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        progress = await BackupProgressStore.read();
      }
    }
    if (progress != null && progress.finished) {
      final error = progress.error;
      await BackupProgressStore.clear();
      if (error != null) {
        await BackupRunLog.add('run terminato con errore: $error');
      }
      final rest = [
        for (final item in queue)
          if (item.sourceId != progress.sourceId) item,
      ];
      await BackupProgressStore.writeQueue(rest);
      _invalidateAll();
      if (rest.isEmpty) {
        _stopPolling();
        state = BackupRunnerState(log: await BackupRunLog.read());
        return;
      }
      state = BackupRunnerState(queue: rest, log: await BackupRunLog.read());
      await _startNext(rest.first);
      return;
    }
    state = BackupRunnerState(progress: progress, queue: queue, log: log);
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

class _LifecycleWatcher with WidgetsBindingObserver {
  _LifecycleWatcher(this.onBackground);

  final VoidCallback onBackground;
  bool backgrounded = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (backgrounded) return;
      backgrounded = true;
      onBackground();
    }
  }
}
