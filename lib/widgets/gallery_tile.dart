import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../l10n/app_localizations.dart';
import '../models/gallery_entry.dart';
import '../providers/library_providers.dart';
import '../services/scan_service.dart';
import 'local_file_image.dart';

/// Gallery grid tile: device thumbnail when available, network thumbnail
/// otherwise, with the upload state badge.
class GalleryTile extends ConsumerWidget {
  final GalleryEntry entry;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selectionMode;

  const GalleryTile({
    super.key,
    required this.entry,
    this.size = 120,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _thumbnail(context, ref),
              if (selectionMode)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? scheme.primary
                          : scheme.surface.withValues(alpha: 0.85),
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
              if (entry.isLocalOnly && !selectionMode)
                Positioned(
                  top: 6,
                  right: 6,
                  child: _badge(
                    scheme,
                    icon: Icons.smartphone,
                    label: l10n.galleryLocalOnly,
                  ),
                )
              else if (entry.isMetadataMissing && !selectionMode)
                Positioned(
                  top: 6,
                  right: 6,
                  child: _badge(
                    scheme,
                    icon: Icons.info_outline,
                    label: entry.cloud?.metadataStatus == 'none'
                        ? l10n.noMetadata
                        : l10n.partialMetadata,
                  ),
                ),
              if (entry.isVideo)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          _durationLabel(entry.local?.durationS),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!selectionMode)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _backupIcon,
                      size: 14,
                      color: entry.isBackupFailed ? scheme.error : Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _backupIcon {
    if (entry.isUploaded) return Icons.cloud_done;
    if (entry.isBackupFailed) return Icons.cloud_off;
    return Icons.cloud_queue;
  }

  Widget _badge(
    ColorScheme scheme, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: scheme.onTertiaryContainer),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _thumbnail(BuildContext context, WidgetRef ref) {
    final asset = entry.local?.asset;
    if (asset != null) {
      return AssetEntityImage(
        asset,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize.square(240),
        thumbnailFormat: ThumbnailFormat.jpeg,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _network(context, ref),
      );
    }
    final path = entry.local?.path;
    if (!kIsWeb && path != null && path.isNotEmpty) {
      return localFileImage(
        context,
        path: path,
        onError: () => _network(context, ref),
      );
    }
    return _network(context, ref);
  }

  Widget _network(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final url =
        entry.thumbnailUrl ??
        (entry.cloud == null
            ? null
            : ref.watch(apiClientProvider).thumbnailUrl(entry.cloud!.id));
    if (url == null || url.isEmpty) {
      return _placeholder(scheme);
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (context, url) => _placeholder(scheme, loading: true),
      errorWidget: (context, url, error) => _placeholder(scheme),
    );
  }

  Widget _placeholder(ColorScheme scheme, {bool loading = false}) {
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                entry.isVideo
                    ? Icons.videocam_outlined
                    : Icons.image_not_supported_outlined,
                color: scheme.onSurfaceVariant,
              ),
      ),
    );
  }

  static String _durationLabel(double? seconds) {
    if (seconds == null) return '--:--';
    final total = seconds.round();
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final secs = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }
}
