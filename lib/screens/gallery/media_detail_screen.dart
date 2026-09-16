import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/media_item.dart';
import '../../providers/library_providers.dart';

class MediaDetailScreen extends ConsumerWidget {
  final MediaItem item;

  const MediaDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final client = ref.watch(apiClientProvider);
    final imageUrl = item.thumbnailUrl ?? client.thumbnailUrl(item.id);

    return Scaffold(
      appBar: AppBar(title: Text(item.name, overflow: TextOverflow.ellipsis)),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (context, url, error) => Center(
                  child: Icon(
                    item.isVideo
                        ? Icons.videocam_outlined
                        : Icons.image_not_supported_outlined,
                    size: 48,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FilledButton.icon(
              onPressed: () => _download(context, l10n),
              icon: const Icon(Icons.download),
              label: Text(l10n.downloadOriginal),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.metadataTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ..._metadataRows(context, l10n),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _download(BuildContext context, AppLocalizations l10n) async {
    final url = item.downloadUrl;
    if (url == null || url.isEmpty) {
      _snack(context, l10n.downloadUnavailable);
      return;
    }
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      _snack(context, l10n.downloadUnavailable);
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  List<Widget> _metadataRows(BuildContext context, AppLocalizations l10n) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    String date(DateTime? value) =>
        value == null ? l10n.notAvailable : dateFormat.format(value);
    final size = item.sizeBytes;

    final rows = <(String, String)>[
      (l10n.fieldType, item.isVideo ? l10n.videosOnly : l10n.photosOnly),
      (l10n.fieldMime, item.mime ?? l10n.notAvailable),
      (l10n.fieldSize, size == null ? l10n.notAvailable : _formatBytes(size)),
      (l10n.fieldTakenAt, date(item.takenAt)),
      (l10n.fieldFileCreated, date(item.fileCreatedAt)),
      (l10n.fieldModified, date(item.modifiedAt)),
      (
        l10n.fieldGps,
        item.hasGps
            ? '${item.lat!.toStringAsFixed(6)}, ${item.lon!.toStringAsFixed(6)}'
            : l10n.notAvailable,
      ),
      (
        l10n.fieldDimensions,
        (item.width != null && item.height != null)
            ? '${item.width} × ${item.height}'
            : l10n.notAvailable,
      ),
      (
        l10n.fieldDuration,
        item.durationS == null
            ? l10n.notAvailable
            : _formatDuration(item.durationS!),
      ),
      (l10n.fieldMetadataStatus, _statusLabel(l10n, item.metadataStatus)),
      (
        l10n.fieldSource,
        '${item.sourceLabel ?? l10n.notAvailable} (${item.sourceKind ?? '-'})',
      ),
      if (item.sourceKind == 'kdrive')
        (l10n.fieldKdriveFileId, item.externalKey),
      (l10n.fieldPath, item.path ?? l10n.notAvailable),
    ];

    return [
      for (final (label, value) in rows)
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
