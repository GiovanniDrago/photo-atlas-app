import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/app_localizations.dart';

/// Picks the center and radius of a smart-album location rule on the map.
/// Returns `(lat, lon, radiusM)` or null when cancelled.
class LocationPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;
  final double? initialRadiusM;

  const LocationPickerScreen({
    super.key,
    this.initialLat,
    this.initialLon,
    this.initialRadiusM,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const _minRadiusM = 100.0;
  static const _maxRadiusM = 200000.0;

  LatLng? _center;
  late double _radiusM;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    final lat = widget.initialLat;
    final lon = widget.initialLon;
    if (lat != null && lon != null) _center = LatLng(lat, lon);
    _radiusM = (widget.initialRadiusM ?? 5000).clamp(_minRadiusM, _maxRadiusM);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final center = _center;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.albumLocationTitle)),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center ?? const LatLng(41.9, 12.5),
                initialZoom: center == null ? 5 : 11,
                minZoom: 2,
                maxZoom: 18,
                onTap: (tapPosition, point) => setState(() => _center = point),
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
                if (center != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: center,
                        radius: _radiusM,
                        useRadiusInMeter: true,
                        color: scheme.primary.withValues(alpha: 0.2),
                        borderColor: scheme.primary,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                if (center != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: center,
                        width: 32,
                        height: 32,
                        child: Icon(
                          Icons.place,
                          color: scheme.primary,
                          size: 32,
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
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    center == null
                        ? l10n.albumLocationHint
                        : '${center.latitude.toStringAsFixed(4)}, '
                              '${center.longitude.toStringAsFixed(4)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Row(
                    children: [
                      Text(l10n.albumRadius),
                      Expanded(
                        child: Slider(
                          value: _radiusM.clamp(_minRadiusM, _maxRadiusM),
                          min: _minRadiusM,
                          max: _maxRadiusM,
                          divisions: 100,
                          label: _radiusLabel(),
                          onChanged: (value) =>
                              setState(() => _radiusM = value),
                        ),
                      ),
                      Text(_radiusLabel()),
                    ],
                  ),
                  FilledButton(
                    onPressed: center == null
                        ? null
                        : () => Navigator.of(context).pop((
                            lat: center.latitude,
                            lon: center.longitude,
                            radiusM: _radiusM,
                          )),
                    child: Text(l10n.albumLocationApply),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _radiusLabel() {
    final km = _radiusM / 1000;
    return '${km == km.roundToDouble() ? km.toStringAsFixed(0) : km.toStringAsFixed(1)} km';
  }
}
