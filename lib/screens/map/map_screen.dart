import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gallery_entry.dart';
import '../../models/media_cluster.dart';
import '../../providers/library_providers.dart';
import '../../services/api_client.dart';
import '../../widgets/media_thumbnail.dart';
import '../../widgets/planet_globe.dart';
import '../gallery/media_viewer_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const ClusterQuery _worldQuery = ClusterQuery(
    west: -180,
    south: -90,
    east: 180,
    north: 90,
    zoom: 1,
  );

  final MapController _mapController = MapController();
  bool _globeMode = true;
  LatLng _globeCenter = const LatLng(25, 0);
  double _globeScale = 1.0;
  ClusterQuery _globeQuery = _worldQuery;
  ClusterQuery _mapQuery = _worldQuery;
  LatLng _mapCenter = const LatLng(25, 0);
  double _mapZoom = 4.5;
  MediaCluster? _selected;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _handleGlobeScale(double scale) {
    final zoom = scale < 1.4 ? 1 : (scale < 1.8 ? 2 : 3);
    setState(() {
      _globeScale = scale;
      _globeQuery = ClusterQuery(
        west: -180,
        south: -90,
        east: 180,
        north: 90,
        zoom: zoom,
      );
    });
    if (scale >= 2.5) {
      _switchToMap(_globeCenter, 4.5);
    }
  }

  void _switchToMap(LatLng center, double zoom) {
    setState(() {
      _globeMode = false;
      _selected = null;
      _mapCenter = center;
      _mapZoom = zoom;
      _mapQuery = ClusterQuery(
        west: -180,
        south: -90,
        east: 180,
        north: 90,
        zoom: zoom.floor(),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(center, zoom);
    });
  }

  void _switchToGlobe() {
    setState(() {
      _globeMode = true;
      _selected = null;
      _globeScale = 1.0;
      _globeQuery = _worldQuery;
      _globeCenter = _mapCenter;
    });
  }

  void _handleMapPosition(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final bounds = camera.visibleBounds;
      final zoom = camera.zoom.floor().clamp(0, 18);
      setState(() {
        _mapCenter = camera.center;
        _mapZoom = camera.zoom;
        if (camera.zoom < 2.6) {
          _globeMode = true;
          _globeScale = 1.0;
          _globeCenter = camera.center;
          _globeQuery = _worldQuery;
        } else {
          _mapQuery = ClusterQuery(
            west: bounds.west.clamp(-180.0, 180.0),
            south: bounds.south.clamp(-90.0, 90.0),
            east: bounds.east.clamp(-180.0, 180.0),
            north: bounds.north.clamp(-90.0, 90.0),
            zoom: zoom,
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final query = _globeMode ? _globeQuery : _mapQuery;
    final clustersAsync = ref.watch(clustersProvider(query));
    final clusters = clustersAsync.value ?? const <MediaCluster>[];
    final selected = _selected;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            onPressed: () {
              if (_globeMode) {
                _switchToMap(_globeCenter, 4.5);
              } else {
                _switchToGlobe();
              }
            },
            icon: Icon(_globeMode ? Icons.map_outlined : Icons.public),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _globeMode
                      ? _buildGlobe(clusters)
                      : _buildMap(clusters, scheme),
                ),
                if (clustersAsync.isLoading)
                  const Positioned(
                    top: 12,
                    right: 12,
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (_globeMode)
                  Positioned(
                    bottom: 14,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Text(
                          l10n.planetHint,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (selected != null) _buildSelectedSection(selected, l10n),
        ],
      ),
    );
  }

  Widget _buildGlobe(List<MediaCluster> clusters) {
    return PlanetGlobe(
      clusters: clusters,
      center: _globeCenter,
      scale: _globeScale,
      selectedKey: _selected?.key,
      onCenterChanged: (center) => setState(() => _globeCenter = center),
      onScaleChanged: _handleGlobeScale,
      onClusterTap: (cluster) => setState(() => _selected = cluster),
    );
  }

  Widget _buildMap(List<MediaCluster> clusters, ColorScheme scheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxCount = clusters.fold<int>(
      1,
      (max, cluster) => math.max(max, cluster.count),
    );
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _mapCenter,
        initialZoom: _mapZoom,
        minZoom: 2,
        maxZoom: 18,
        onPositionChanged: _handleMapPosition,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
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
        CircleLayer(
          circles: [
            for (final cluster in clusters)
              CircleMarker(
                point: LatLng(cluster.lat, cluster.lon),
                radius: 10 + 26 * math.sqrt(cluster.count / maxCount),
                useRadiusInMeter: false,
                color: scheme.primary.withValues(
                  alpha: _selected?.key == cluster.key ? 0.85 : 0.4,
                ),
                borderColor: scheme.primary,
                borderStrokeWidth: 1.5,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final cluster in clusters)
              Marker(
                point: LatLng(cluster.lat, cluster.lon),
                width: 64,
                height: 36,
                child: GestureDetector(
                  onTap: () => setState(() => _selected = cluster),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: scheme.primary),
                      ),
                      child: Text(
                        '${cluster.count}',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
            TextSourceAttribution('CARTO'),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectedSection(MediaCluster cluster, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final mediaAsync = ref.watch(
      clusterMediaProvider(
        ClusterQuery(
          west: cluster.west,
          south: cluster.south,
          east: cluster.east,
          north: cluster.north,
          zoom: 0,
        ),
      ),
    );
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(Icons.place_outlined, color: scheme.primary),
            title: Text(l10n.sectionSelected),
            subtitle: Text(l10n.itemCount(cluster.count)),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _selected = null),
            ),
          ),
          Expanded(
            child: mediaAsync.when(
              data: (items) => items.isEmpty
                  ? Center(child: Text(l10n.galleryEmpty))
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) => MediaThumbnail(
                        item: items[index],
                        size: 110,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MediaViewerScreen(
                              entries: [
                                for (final item in items)
                                  GalleryEntry(cloud: item),
                              ],
                              initialIndex: index,
                            ),
                          ),
                        ),
                      ),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  Center(child: Text(l10n.errorLoading)),
            ),
          ),
        ],
      ),
    );
  }
}
