import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/media_item.dart';
import '../../models/source.dart';
import '../../providers/backup_runner_provider.dart';
import '../../providers/library_providers.dart';
import '../../widgets/media_thumbnail.dart';

/// Inspection screen for the backup: lists the media that are not uploaded
/// (failed, pending or stuck) with the reason, and lets the user retry them in
/// group or one by one, or ignore the problematic ones.
class BackupIssuesScreen extends ConsumerStatefulWidget {
  const BackupIssuesScreen({super.key, this.initialSourceId});

  final String? initialSourceId;

  @override
  ConsumerState<BackupIssuesScreen> createState() => _BackupIssuesScreenState();
}

class _BackupIssuesScreenState extends ConsumerState<BackupIssuesScreen> {
  static const int _pageSize = 100;
  static const int _maxBatch = 500;

  String? _sourceId;
  bool _showSkipped = false;
  final List<MediaItem> _items = [];
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sourceId = widget.initialSourceId;
    _load();
  }

  String get _statusFilter => _showSkipped
      ? 'none,pending,uploading,failed,skipped'
      : 'none,pending,uploading,failed';

  Future<void> _load({bool reset = true}) async {
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final page = await ref.read(apiClientProvider).media(
        sourceId: _sourceId,
        backupStatus: _statusFilter,
        limit: _pageSize,
        offset: reset ? 0 : _items.length,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _total = page.total;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _retry(List<MediaItem> items) async {
    if (items.isEmpty || _busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final client = ref.read(apiClientProvider);
      final ids = items.map((item) => item.id).toList();
      var queued = 0;
      for (var index = 0; index < ids.length; index += _maxBatch) {
        final chunk = ids.sublist(
          index,
          math.min(index + _maxBatch, ids.length),
        );
        queued += await client.retryBackup(ids: chunk);
      }
      // Starting the run is a separate step: a failure here must not hide the
      // fact that the items were requeued, nor skip the refresh below.
      String? startError;
      try {
        await _enqueueSources(items.map((item) => item.sourceId).toSet());
      } catch (error) {
        startError = '$error';
      }
      if (mounted) {
        _snack(
          startError == null
              ? l10n.backupIssuesQueued(queued)
              : '${l10n.backupIssuesQueued(queued)} · $startError',
        );
      }
      await _load();
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip(List<MediaItem> items) async {
    final candidates = items
        .where((item) => item.backupStatus != 'skipped')
        .toList();
    if (candidates.isEmpty || _busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final client = ref.read(apiClientProvider);
      final ids = candidates.map((item) => item.id).toList();
      var skipped = 0;
      for (var index = 0; index < ids.length; index += _maxBatch) {
        final chunk = ids.sublist(
          index,
          math.min(index + _maxBatch, ids.length),
        );
        skipped += await client.skipBackup(chunk);
      }
      if (mounted) _snack(l10n.backupIssuesIgnored(skipped));
      await _load();
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enqueueSources(Set<String> sourceIds) async {
    if (sourceIds.isEmpty) return;
    final List<MediaSource> sources;
    try {
      sources = await ref.read(sourcesProvider.future);
    } catch (_) {
      return;
    }
    final byId = {for (final source in sources) source.id: source};
    final runner = ref.read(backupRunnerProvider.notifier);
    for (final id in sourceIds) {
      final source = byId[id];
      if (source == null) continue;
      await runner.enqueue(
        sourceId: source.id,
        label: source.label,
        rootPath: source.rootPath ?? '',
      );
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _statusLabel(AppLocalizations l10n, String status) {
    switch (status) {
      case 'failed':
        return l10n.backupStatusFailed;
      case 'uploading':
        return l10n.backupStatusUploading;
      case 'skipped':
        return l10n.backupStatusSkipped;
      default:
        return l10n.backupStatusPending;
    }
  }

  String _reason(AppLocalizations l10n, String? error) {
    if (error == null || error.isEmpty) return '';
    final value = error.toLowerCase();
    if (value.contains('invalid_upload_token') || value.contains('session')) {
      return l10n.backupReasonSessionExpired;
    }
    if (value.contains('timeout') ||
        value.contains('etimedout') ||
        value.contains('socket') ||
        value.contains('fetch failed') ||
        value.contains('connection')) {
      return l10n.backupReasonNetwork;
    }
    if (value.contains('too large') || value.contains('too_large')) {
      return l10n.backupReasonTooLarge;
    }
    if (value.contains('not found') ||
        value.contains('no such file') ||
        value.contains('local file')) {
      return l10n.backupReasonMissing;
    }
    return error.length > 160 ? '${error.substring(0, 160)}…' : error;
  }

  Widget _sourceSelector(AppLocalizations l10n) {
    final sources = ref.watch(sourcesProvider);
    return sources.when(
      data: (list) => DropdownButton<String?>(
        value: _sourceId,
        isExpanded: true,
        items: [
          DropdownMenuItem(value: null, child: Text(l10n.backupIssuesFilterAll)),
          for (final source in list)
            DropdownMenuItem(
              value: source.id,
              child: Text(source.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: _busy
            ? null
            : (value) {
                setState(() => _sourceId = value);
                _load();
              },
      ),
      loading: () => const LinearProgressIndicator(),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final retryable = _items;
    final ignoreable = _items
        .where((item) => item.backupStatus != 'skipped')
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.backupIssuesTitle),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            onPressed: _busy ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sourceSelector(l10n),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: Text(l10n.backupIssuesShowSkipped),
                      selected: _showSkipped,
                      onSelected: _busy
                          ? null
                          : (value) {
                              setState(() => _showSkipped = value);
                              _load();
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.backupIssuesSubtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  l10n.backupIssuesTotal(_total),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                if (_busy) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? Center(child: Text(l10n.backupIssuesEmpty))
                : ListView.builder(
                    itemCount: _items.length + (_items.length < _total ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _items.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Center(
                            child: _loadingMore
                                ? const CircularProgressIndicator()
                                : TextButton(
                                    onPressed: () => _load(reset: false),
                                    child: Text(l10n.backupIssuesLoadMore),
                                  ),
                          ),
                        );
                      }
                      return _issueRow(context, l10n, _items[index]);
                    },
                  ),
          ),
          if (_items.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy || retryable.isEmpty
                            ? null
                            : () => _retry(retryable),
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.backupIssuesRetryAll),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy || ignoreable.isEmpty
                            ? null
                            : () => _skip(ignoreable),
                        icon: const Icon(Icons.visibility_off_outlined),
                        label: Text(l10n.backupIssuesIgnoreAll),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _issueRow(BuildContext context, AppLocalizations l10n, MediaItem item) {
    final reason = _reason(l10n, item.backupError);
    final isSkipped = item.backupStatus == 'skipped';
    return ListTile(
      leading: SizedBox(
        width: 56,
        height: 56,
        child: MediaThumbnail(item: item, size: 56, showName: false),
      ),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_formatBytes(item.sizeBytes ?? 0)} · '
        '${_statusLabel(l10n, item.backupStatus)}'
        '${reason.isEmpty ? '' : '\n$reason'}',
        maxLines: reason.isEmpty ? 1 : 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: reason.isNotEmpty,
      trailing: PopupMenuButton<String>(
        enabled: !_busy,
        onSelected: (value) {
          if (value == 'retry') {
            _retry([item]);
          } else if (value == 'ignore') {
            _skip([item]);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'retry',
            child: Text(l10n.backupIssuesRetry),
          ),
          if (!isSkipped)
            PopupMenuItem(
              value: 'ignore',
              child: Text(l10n.backupIssuesIgnore),
            ),
        ],
      ),
    );
  }
}
