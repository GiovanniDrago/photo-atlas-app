import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/media_item.dart';
import '../providers/library_providers.dart';

class MediaThumbnail extends ConsumerWidget {
  final MediaItem item;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showName;
  final bool selected;
  final bool selectionMode;

  const MediaThumbnail({
    super.key,
    required this.item,
    this.size = 120,
    this.onTap,
    this.onLongPress,
    this.showName = true,
    this.selected = false,
    this.selectionMode = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final client = ref.watch(apiClientProvider);
    final imageUrl = item.thumbnailUrl ?? client.thumbnailUrl(item.id);
    final missingMetadata = !item.hasFullMetadata;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (context, url) => Container(
                        color: scheme.surfaceContainerHighest,
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(
                          item.isVideo
                              ? Icons.videocam_outlined
                              : Icons.image_not_supported_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
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
                    if (item.isVideo)
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
                                _durationLabel(item.durationS),
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
                            item.isBackedUp
                                ? Icons.cloud_done
                                : item.isBackupFailed
                                ? Icons.cloud_off
                                : Icons.cloud_queue,
                            size: 14,
                            color: item.isBackupFailed
                                ? scheme.error
                                : Colors.white,
                          ),
                        ),
                      ),
                    if (missingMetadata && !selectionMode)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.tertiaryContainer.withValues(
                              alpha: 0.9,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.metadataStatus == 'none'
                                ? l10n.noMetadata
                                : l10n.partialMetadata,
                            style: TextStyle(
                              color: scheme.onTertiaryContainer,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (showName)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 2, right: 2),
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
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
