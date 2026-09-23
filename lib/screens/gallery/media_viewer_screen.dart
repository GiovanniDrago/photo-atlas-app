import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gallery_entry.dart';
import '../../models/media_item.dart';
import '../../providers/collections_providers.dart';
import '../../providers/gallery_providers.dart';
import '../../providers/library_providers.dart';
import '../../services/folder_launcher.dart';
import '../../services/gallery_actions_service.dart';
import '../../services/local_media_service.dart';
import '../../services/scan_service.dart';
import '../../widgets/delete_media_dialog.dart';
import '../../widgets/local_file_image.dart';

enum MediaViewerResult { select }

/// Full screen viewer: horizontal swipe between items, vertical scroll for
/// the metadata and a small map preview when the position is known.
class MediaViewerScreen extends ConsumerStatefulWidget {
  final List<GalleryEntry> entries;
  final int initialIndex;

  /// Called when the last (or first) item is reached, to continue with the
  /// next (or previous) time bucket.
  final Future<List<GalleryEntry>> Function()? loadNext;
  final Future<List<GalleryEntry>> Function()? loadPrevious;

  const MediaViewerScreen({
    super.key,
    required this.entries,
    this.initialIndex = 0,
    this.loadNext,
    this.loadPrevious,
  });

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen> {
  late final PageController _controller;
  late final List<GalleryEntry> _entries;
  late int _index;
  final Map<String, Future<({double lat, double lon})?>> _locations = {};
  bool _sharing = false;
  bool _busy = false;
  bool _loadingNext = false;
  bool _loadingPrevious = false;

  @override
  void initState() {
    super.initState();
    _entries = List.of(widget.entries);
    _index = widget.initialIndex.clamp(0, _entries.length - 1);
    _controller = PageController(initialPage: _index);
  }

  Future<void> _maybeLoadNext() async {
    final loader = widget.loadNext;
    if (loader == null || _loadingNext || _index < _entries.length - 1) return;
    _loadingNext = true;
    try {
      final items = await loader();
      if (!mounted || items.isEmpty) return;
      setState(() => _entries.addAll(items));
    } catch (_) {
    } finally {
      _loadingNext = false;
    }
  }

  Future<void> _maybeLoadPrevious() async {
    final loader = widget.loadPrevious;
    if (loader == null || _loadingPrevious || _index > 0) return;
    _loadingPrevious = true;
    try {
      final items = await loader();
      if (!mounted || items.isEmpty) return;
      setState(() {
        _entries.insertAll(0, items);
        _index += items.length;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.jumpToPage(_index);
        }
      });
    } catch (_) {
    } finally {
      _loadingPrevious = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  GalleryEntry get _entry => _entries[_index];

  Future<({double lat, double lon})?> _locationOf(GalleryEntry entry) {
    return _locations.putIfAbsent(entry.key, () => _loadLocation(entry));
  }

  Future<({double lat, double lon})?> _loadLocation(GalleryEntry entry) async {
    final item = entry.cloud;
    if (item != null && item.hasGps && item.lat != null && item.lon != null) {
      return (lat: item.lat!, lon: item.lon!);
    }
    final local = entry.local;
    if (local != null) return LocalMediaService.location(local);
    return null;
  }

  Future<void> _share() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _sharing = true);
    try {
      final service = GalleryActionsService(ref.read(apiClientProvider));
      final result = await service.share([
        _entry,
      ], sharePositionOrigin: _shareOrigin());
      if (result.errors.isNotEmpty && mounted) {
        _snack('${l10n.galleryShareFailed}: ${result.errors.first}');
      }
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Rect? _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _upload() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final result = await GalleryActionsService(ref.read(apiClientProvider))
          .upload([_entry]);
      if (!mounted) return;
      _snack(
        result.failed > 0
            ? l10n.galleryUploadedFailed(result.uploaded, result.failed)
            : l10n.galleryUploadedCount(result.uploaded),
      );
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
      _invalidateLibrary();
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final options = await showDeleteMediaDialog(context, [_entry]);
    if (options == null || !mounted) return;
    if (!options.cloud && !options.local) return;
    setState(() => _busy = true);
    try {
      final result = await GalleryActionsService(ref.read(apiClientProvider))
          .delete([_entry], cloud: options.cloud, local: options.local);
      if (!mounted) return;
      _snack(
        result.failed > 0
            ? l10n.galleryDeletedFailed(result.failed)
            : l10n.galleryDeleted(
                result.localDeleted + result.indexDeleted + result.reset,
              ),
      );
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
      _invalidateLibrary();
    }
  }

  void _invalidateLibrary() {
    ref.invalidate(galleryProvider);
    ref.invalidate(timelineProvider);
    ref.invalidate(timelineItemsProvider);
    ref.invalidate(backupStatusProvider);
    ref.invalidate(sourcesProvider);
  }

  Future<void> _openFolder() async {
    final l10n = AppLocalizations.of(context)!;
    final entry = _entry;
    final opened = await openDeviceFolder(
      relativePath: entry.local?.relativePath,
      absolutePath: _folderPath(entry),
    );
    if (!opened && mounted) _snack(l10n.openFolderFailed);
  }

  String? _folderPath(GalleryEntry entry) {
    final path = entry.local?.path ?? entry.cloud?.path;
    if (path == null || path.isEmpty) return null;
    final index = path.lastIndexOf('/');
    if (index <= 0) return null;
    return path.substring(0, index);
  }

  Future<void> _openInMaps() async {
    final l10n = AppLocalizations.of(context)!;
    final location = await _locationOf(_entry);
    if (!mounted) return;
    if (location == null) {
      _snack(l10n.viewerNoLocation);
      return;
    }
    final geo = Uri.parse(
      'geo:${location.lat},${location.lon}?q=${location.lat},${location.lon}',
    );
    final web = Uri.parse(
      'https://www.openstreetmap.org/?mlat=${location.lat}&mlon=${location.lon}'
      '#map=16/${location.lat}/${location.lon}',
    );
    var opened = false;
    try {
      opened = await launchUrl(geo, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      try {
        opened = await launchUrl(web, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && mounted) _snack(l10n.viewerOpenMapsFailed);
  }

  Future<void> _download(String url) async {
    final l10n = AppLocalizations.of(context)!;
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) _snack(l10n.downloadUnavailable);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.entries.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.galleryEmpty)),
      );
    }
    final entry = _entry;
    final canUpload = entry.canUpload;
    final downloadUrl = entry.cloud?.downloadUrl;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          Center(
            child: Text(
              l10n.viewerPosition(_index + 1, _entries.length),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'share') {
                _share();
              } else if (value == 'upload') {
                _upload();
              } else if (value == 'delete') {
                _delete();
              } else if (value == 'download') {
                _download(downloadUrl!);
              } else if (value == 'select') {
                Navigator.of(context).pop(MediaViewerResult.select);
              } else if (value == 'maps') {
                _openInMaps();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'share',
                enabled: !_busy,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.share_outlined),
                  title: Text(l10n.galleryShare),
                ),
              ),
              if (canUpload)
                PopupMenuItem(
                  value: 'upload',
                  enabled: !_busy,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: Text(l10n.galleryUpload),
                  ),
                ),
              if (downloadUrl != null && downloadUrl.isNotEmpty)
                PopupMenuItem(
                  value: 'download',
                  enabled: !_busy,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.download),
                    title: Text(l10n.downloadOriginal),
                  ),
                ),
              PopupMenuItem(
                value: 'delete',
                enabled: !_busy,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: Text(l10n.galleryDelete),
                ),
              ),
              PopupMenuItem(
                value: 'select',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(l10n.viewerSelect),
                ),
              ),
              if (entry.cloud?.hasGps == true || entry.local != null)
                PopupMenuItem(
                  value: 'maps',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.map_outlined),
                    title: Text(l10n.viewerOpenInMaps),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: _entries.length,
        onPageChanged: (index) {
          setState(() => _index = index);
          if (index >= _entries.length - 1) {
            _maybeLoadNext();
          } else if (index == 0) {
            _maybeLoadPrevious();
          }
        },
        itemBuilder: (context, index) => _page(_entries[index], l10n),
      ),
    );
  }

  Widget _page(GalleryEntry entry, AppLocalizations l10n) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          key: PageStorageKey(entry.key),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _preview(entry),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.viewerScrollHint,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down,
                                color: Colors.white,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _details(entry, l10n),
            ],
          ),
        );
      },
    );
  }

  Widget _preview(GalleryEntry entry) {
    final asset = entry.local?.asset;
    if (asset != null) {
      return AssetEntityImage(
        asset,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize.square(1440),
        thumbnailFormat: ThumbnailFormat.jpeg,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _network(entry),
      );
    }
    final path = entry.local?.path;
    if (path != null && path.isNotEmpty) {
      return localFileImage(
        context,
        path: path,
        fit: BoxFit.contain,
        onError: () => _network(entry),
      );
    }
    return _network(entry);
  }

  Widget _network(GalleryEntry entry) {
    final url = _previewUrl(entry);
    if (url == null || url.isEmpty) {
      return Center(
        child: Icon(
          entry.isVideo
              ? Icons.videocam_outlined
              : Icons.image_not_supported_outlined,
          size: 48,
          color: Colors.white54,
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      placeholder: (context, url) =>
          const Center(child: CircularProgressIndicator()),
      errorWidget: (context, url, error) => Center(
        child: Icon(
          entry.isVideo
              ? Icons.videocam_outlined
              : Icons.image_not_supported_outlined,
          size: 48,
          color: Colors.white54,
        ),
      ),
    );
  }

  String? _previewUrl(GalleryEntry entry) {
    final url = entry.thumbnailUrl;
    if (url == null || url.isEmpty) {
      final item = entry.cloud;
      if (item == null) return null;
      return ref.read(apiClientProvider).thumbnailUrl(item.id);
    }
    // kDrive items can be asked for a larger preview on the fly.
    return entry.isKDriveSource ? '$url&w=1600' : url;
  }

  Widget _details(GalleryEntry entry, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<({double lat, double lon})?>(
      future: _locationOf(entry),
      builder: (context, snapshot) {
        final location = snapshot.data;
        return Container(
          color: scheme.surface,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusChip(entry, l10n, scheme),
                ],
              ),
              const SizedBox(height: 12),
              ..._metadataRows(entry, l10n, location),
              if (location != null) ...[
                const SizedBox(height: 16),
                Text(
                  l10n.viewerLocation,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _MiniMap(
                  lat: location.lat,
                  lon: location.lon,
                  onOpen: _openInMaps,
                ),
              ],
              if (entry.cloud?.downloadUrl case final url? when url.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FilledButton.icon(
                    onPressed: () => _download(url),
                    icon: const Icon(Icons.download),
                    label: Text(l10n.downloadOriginal),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusChip(
    GalleryEntry entry,
    AppLocalizations l10n,
    ColorScheme scheme,
  ) {
    final (icon, label, color) = entry.isUploaded
        ? (Icons.cloud_done, l10n.galleryUploaded, scheme.primary)
        : entry.isBackupFailed
        ? (Icons.cloud_off, l10n.backupStatusFailed, scheme.error)
        : (Icons.cloud_queue, l10n.galleryNotUploaded, scheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  List<Widget> _metadataRows(
    GalleryEntry entry,
    AppLocalizations l10n,
    ({double lat, double lon})? location,
  ) {
    final item = entry.cloud;
    final local = entry.local;
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    String date(DateTime? value) =>
        value == null ? l10n.notAvailable : dateFormat.format(value);
    final size = entry.sizeBytes;
    final width = item?.width ?? local?.width;
    final height = item?.height ?? local?.height;
    final duration = item?.durationS ?? local?.durationS;

    final rows = <(String, String)>[
      (l10n.fieldType, entry.isVideo ? l10n.videosOnly : l10n.photosOnly),
      if (item?.mime != null) (l10n.fieldMime, item!.mime!),
      (l10n.fieldSize, size == null ? l10n.notAvailable : _formatBytes(size)),
      (l10n.fieldTakenAt, date(item?.takenAt ?? local?.takenAt)),
      if (item != null) (l10n.fieldFileCreated, date(item.fileCreatedAt)),
      (l10n.fieldModified, date(item?.modifiedAt ?? local?.modifiedAt)),
      (
        l10n.fieldGps,
        location == null
            ? l10n.notAvailable
            : '${location.lat.toStringAsFixed(6)}, '
                  '${location.lon.toStringAsFixed(6)}',
      ),
      (
        l10n.fieldDimensions,
        (width != null && height != null)
            ? '$width × $height'
            : l10n.notAvailable,
      ),
      (
        l10n.fieldDuration,
        duration == null ? l10n.notAvailable : _formatDuration(duration),
      ),
      if (item != null)
        (l10n.fieldMetadataStatus, _statusLabel(l10n, item.metadataStatus)),
      if (item != null) (l10n.fieldBackup, _backupLabel(l10n, item)),
      (
        l10n.fieldSource,
        '${entry.sourceLabel ?? l10n.notAvailable} '
            '(${item?.sourceKind ?? (local != null ? 'local' : '-')})',
      ),
      if (item?.sourceKind == 'kdrive')
        (l10n.fieldKdriveFileId, item!.externalKey),
      (l10n.fieldPath, item?.path ?? local?.path ?? l10n.notAvailable),
    ];

    return [
      for (final (label, value) in rows)
        if (label == l10n.fieldPath && _canOpenFolder(entry))
          InkWell(
            onTap: _openFolder,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(child: Text(value)),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.folder_open,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(child: SelectableText(value)),
              ],
            ),
          ),
    ];
  }

  bool _canOpenFolder(GalleryEntry entry) {
    final relative = entry.local?.relativePath;
    if (relative != null && relative.isNotEmpty) return true;
    return _folderPath(entry) != null;
  }

  static String _backupLabel(AppLocalizations l10n, MediaItem item) {
    switch (item.backupStatus) {
      case 'uploaded':
        final date = item.backedUpAt;
        return date == null
            ? l10n.backupStatusUploaded
            : '${l10n.backupStatusUploaded} · '
                  '${DateFormat('yyyy-MM-dd HH:mm').format(date)}';
      case 'failed':
        return item.backupError == null
            ? l10n.backupStatusFailed
            : '${l10n.backupStatusFailed} (${item.backupError})';
      default:
        return l10n.backupStatusPending;
    }
  }

  static String _statusLabel(AppLocalizations l10n, String status) {
    switch (status) {
      case 'full':
        return l10n.fullMetadata;
      case 'partial':
        return l10n.partialMetadata;
      default:
        return l10n.noMetadata;
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _formatDuration(double seconds) {
    final total = seconds.round();
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final secs = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }
}

class _MiniMap extends StatelessWidget {
  final double lat;
  final double lon;
  final VoidCallback onOpen;

  const _MiniMap({required this.lat, required this.lon, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onOpen,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 160,
              child: AbsorbPointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(lat, lon),
                    initialZoom: 15,
                    minZoom: 2,
                    maxZoom: 18,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: isDark
                          ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                          : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'dev.giovannidrago.photoatlas',
                      maxZoom: 20,
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(lat, lon),
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.location_on,
                            size: 36,
                            color: scheme.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '© OpenStreetMap · CARTO',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}
