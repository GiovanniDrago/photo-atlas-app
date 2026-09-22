import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gallery_entry.dart';
import '../../providers/library_providers.dart';
import '../../services/backup_service.dart';
import '../../services/local_media_service.dart';
import '../../services/scan_service.dart';

class UploadPickerScreen extends ConsumerStatefulWidget {
  const UploadPickerScreen({super.key});

  @override
  ConsumerState<UploadPickerScreen> createState() => _UploadPickerScreenState();
}

class _UploadPickerScreenState extends ConsumerState<UploadPickerScreen> {
  static const _pageSize = 60;

  final Map<String, LocalMedia> _selected = {};
  final List<LocalMedia> _all = [];
  int _visible = _pageSize;
  bool _loading = true;
  bool _uploading = false;
  bool _cancelled = false;
  String? _error;
  BackupProgress? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await LocalMediaService.loadAll(
        client: ref.read(apiClientProvider),
      );
      if (!mounted) return;
      setState(() {
        _all
          ..clear()
          ..addAll(page.items);
        _error = null;
      });
    } on ScanPermissionException {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context)!.localPermissionDenied,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMore() {
    setState(() => _visible += _pageSize);
  }

  void _toggle(LocalMedia media) {
    setState(() {
      if (_selected.containsKey(media.id)) {
        _selected.remove(media.id);
      } else {
        _selected[media.id] = media;
      }
    });
  }

  void _toggleAll() {
    setState(() {
      final visible = _all.take(_visible).toList();
      if (visible.every((media) => _selected.containsKey(media.id))) {
        for (final media in visible) {
          _selected.remove(media.id);
        }
      } else {
        for (final media in visible) {
          _selected[media.id] = media;
        }
      }
    });
  }

  Future<void> _upload() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _uploading = true;
      _cancelled = false;
      _progress = const BackupProgress();
      _error = null;
    });
    try {
      final service = BackupService(ref.read(apiClientProvider));
      final errors = await service.uploadPickedAssets(
        assets: [
          for (final media in _selected.values)
            if (media.asset != null) media.asset!,
        ],
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        isCancelled: () => _cancelled,
      );
      if (!mounted) return;
      final uploaded = _progress?.uploaded ?? 0;
      final failed = _progress?.failed ?? 0;
      final detail = errors.isEmpty ? null : errors.first;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed > 0
                ? '${l10n.backupUploadResult(uploaded, failed)}'
                      '${detail == null ? '' : ' · $detail'}'
                : l10n.backupUploadedCount(uploaded),
          ),
        ),
      );
      if (uploaded > 0 || failed == 0) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    if (kIsWeb || !ScanService.isAlbumBased) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.backupPickerTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.backupUnavailableWeb),
          ),
        ),
      );
    }
    final visible = _all.take(_visible).toList();
    final allSelected =
        visible.isNotEmpty &&
        visible.every((media) => _selected.containsKey(media.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.backupPickerTitle),
        actions: [
          TextButton(
            onPressed: _uploading || visible.isEmpty ? null : _toggleAll,
            child: Text(
              allSelected ? l10n.backupDeselectAll : l10n.backupSelectAll,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final media = visible[index];
                final asset = media.asset;
                final selected = _selected.containsKey(media.id);
                return GestureDetector(
                  onTap: _uploading ? null : () => _toggle(media),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (asset != null)
                        AssetEntityImage(
                          asset,
                          isOriginal: false,
                          thumbnailSize: const ThumbnailSize.square(240),
                          thumbnailFormat: ThumbnailFormat.jpeg,
                          fit: BoxFit.cover,
                        )
                      else
                        ColoredBox(color: scheme.surfaceContainerHighest),
                      if (media.isVideo)
                        const Positioned(
                          left: 4,
                          bottom: 4,
                          child: Icon(
                            Icons.play_circle_outline,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? scheme.primary
                                : scheme.surface.withValues(alpha: 0.8),
                            border: Border.all(color: scheme.outline),
                          ),
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            Icons.check,
                            size: 14,
                            color: selected
                                ? scheme.onPrimary
                                : scheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            )
          else if (_visible < _all.length)
            TextButton(
              onPressed: _showMore,
              child: Text(l10n.backupLoadMore(_all.length)),
            ),
          if (_uploading)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_progress?.currentName != null)
                    Text(
                      _progress!.currentName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.backupCounters(
                      _progress?.uploaded ?? 0,
                      _progress?.failed ?? 0,
                      '',
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (_progress?.total ?? 0) == 0
                        ? null
                        : ((_progress!.uploaded + _progress!.failed) /
                                  _progress!.total)
                              .clamp(0.0, 1.0),
                  ),
                ],
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.backupSelectedCount(_selected.length)),
                  ),
                  if (_uploading)
                    TextButton(
                      onPressed: () => setState(() => _cancelled = true),
                      child: Text(l10n.backupStop),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _selected.isEmpty ? null : _upload,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(l10n.backupUploadCount(_selected.length)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
