import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/media_cluster.dart';
import '../services/geo_data.dart';

class PlanetGlobe extends StatefulWidget {
  final List<MediaCluster> clusters;
  final LatLng center;
  final double scale;
  final String? selectedKey;
  final ValueChanged<LatLng> onCenterChanged;
  final ValueChanged<double> onScaleChanged;
  final ValueChanged<MediaCluster> onClusterTap;

  const PlanetGlobe({
    super.key,
    required this.clusters,
    required this.center,
    required this.scale,
    required this.onCenterChanged,
    required this.onScaleChanged,
    required this.onClusterTap,
    this.selectedKey,
  });

  @override
  State<PlanetGlobe> createState() => _PlanetGlobeState();
}

class _PlanetGlobeState extends State<PlanetGlobe> {
  List<List<LatLng>>? _land;
  double _scaleAtStart = 1;
  LatLng? _centerAtStart;

  @override
  void initState() {
    super.initState();
    GeoData.loadLand().then((land) {
      if (mounted) setState(() => _land = land);
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _scaleAtStart = widget.scale;
    _centerAtStart = widget.center;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final start = _centerAtStart ?? widget.center;
    if (details.pointerCount > 1) {
      final next = (_scaleAtStart * details.scale).clamp(1.0, 3.2);
      widget.onScaleChanged(next);
      return;
    }
    final delta = details.focalPointDelta;
    if (delta == Offset.zero) return;
    final dLon = -delta.dx * 0.35 / widget.scale;
    final dLat = delta.dy * 0.35 / widget.scale;
    final latitude = (start.latitude + dLat).clamp(-75.0, 75.0);
    var longitude = start.longitude + dLon;
    if (longitude > 180) longitude -= 360;
    if (longitude < -180) longitude += 360;
    widget.onCenterChanged(LatLng(latitude, longitude));
  }

  void _onTapUp(TapUpDetails details, Size size) {
    final projector = _Projector(
      center: widget.center,
      radius: _radiusFor(size),
      origin: Offset(size.width / 2, size.height / 2),
    );
    MediaCluster? best;
    double bestDistance = 32;
    for (final cluster in widget.clusters) {
      final projected = projector.project(LatLng(cluster.lat, cluster.lon));
      if (projected == null) continue;
      final distance = (projected - details.localPosition).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = cluster;
      }
    }
    if (best != null) {
      widget.onClusterTap(best);
    }
  }

  double _radiusFor(Size size) =>
      math.min(size.width, size.height) * 0.42 * widget.scale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onTapUp: (details) => _onTapUp(details, size),
          child: RepaintBoundary(
            child: CustomPaint(
              size: size,
              painter: _GlobePainter(
                land: _land ?? const [],
                clusters: widget.clusters,
                center: widget.center,
                scale: widget.scale,
                selectedKey: widget.selectedKey,
                scheme: scheme,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Projector {
  final LatLng center;
  final double radius;
  final Offset origin;

  const _Projector({
    required this.center,
    required this.radius,
    required this.origin,
  });

  Offset? project(LatLng point) {
    final lon = _rad(point.longitude - center.longitude);
    final lat = _rad(point.latitude);
    final lat0 = _rad(center.latitude);
    final cosc =
        math.sin(lat0) * math.sin(lat) +
        math.cos(lat0) * math.cos(lat) * math.cos(lon);
    if (cosc < -0.03) return null;
    final x = radius * math.cos(lat) * math.sin(lon);
    final y =
        -radius *
        (math.cos(lat0) * math.sin(lat) -
            math.sin(lat0) * math.cos(lat) * math.cos(lon));
    return origin + Offset(x, y);
  }

  static double _rad(double degrees) => degrees * math.pi / 180.0;
}

class _GlobePainter extends CustomPainter {
  final List<List<LatLng>> land;
  final List<MediaCluster> clusters;
  final LatLng center;
  final double scale;
  final String? selectedKey;
  final ColorScheme scheme;

  const _GlobePainter({
    required this.land,
    required this.clusters,
    required this.center,
    required this.scale,
    required this.scheme,
    this.selectedKey,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) * 0.42 * scale;
    final origin = Offset(size.width / 2, size.height / 2);
    final projector = _Projector(
      center: center,
      radius: radius,
      origin: origin,
    );

    canvas.drawCircle(
      origin,
      radius + 8,
      Paint()
        ..color = scheme.primary.withValues(alpha: 0.14)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 18),
    );
    canvas.drawCircle(
      origin,
      radius,
      Paint()..color = scheme.surfaceContainerHighest,
    );

    final landFill = Paint()
      ..style = PaintingStyle.fill
      ..color = scheme.primary.withValues(alpha: 0.22);
    final coastStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = scheme.primary.withValues(alpha: 0.75);

    for (final ring in land) {
      final path = Path();
      var started = false;
      for (final point in ring) {
        final projected = projector.project(point);
        if (projected == null) {
          started = false;
          continue;
        }
        if (!started) {
          path.moveTo(projected.dx, projected.dy);
          started = true;
        } else {
          path.lineTo(projected.dx, projected.dy);
        }
      }
      if (started) {
        canvas.drawPath(path, landFill);
        canvas.drawPath(path, coastStroke);
      }
    }

    _paintGraticule(canvas, projector);
    _paintClusters(canvas, projector, radius);
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = scheme.primary.withValues(alpha: 0.55),
    );
  }

  void _paintGraticule(Canvas canvas, _Projector projector) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = scheme.onSurface.withValues(alpha: 0.08);
    for (var latitude = -60; latitude <= 60; latitude += 30) {
      _paintArc(canvas, projector, paint, latitude.toDouble(), true);
    }
    for (var longitude = -150; longitude <= 180; longitude += 30) {
      _paintArc(canvas, projector, paint, longitude.toDouble(), false);
    }
  }

  void _paintArc(
    Canvas canvas,
    _Projector projector,
    Paint paint,
    double value,
    bool isLatitude,
  ) {
    final path = Path();
    var started = false;
    for (var step = -180; step <= 180; step += 6) {
      final point = isLatitude
          ? LatLng(value, step.toDouble())
          : LatLng(step.toDouble(), value);
      final projected = projector.project(point);
      if (projected == null) {
        started = false;
        continue;
      }
      if (!started) {
        path.moveTo(projected.dx, projected.dy);
        started = true;
      } else {
        path.lineTo(projected.dx, projected.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _paintClusters(Canvas canvas, _Projector projector, double radius) {
    final maxCount = clusters.fold<int>(
      1,
      (max, cluster) => math.max(max, cluster.count),
    );
    for (final cluster in clusters) {
      final projected = projector.project(LatLng(cluster.lat, cluster.lon));
      if (projected == null) continue;
      final weight = math.sqrt(cluster.count / maxCount);
      final circleRadius = radius * (0.025 + 0.075 * weight) + 3;
      final selected = cluster.key == selectedKey;
      canvas.drawCircle(
        projected,
        circleRadius,
        Paint()
          ..color = scheme.primary.withValues(alpha: selected ? 0.95 : 0.7)
          ..maskFilter = ui.MaskFilter.blur(
            ui.BlurStyle.normal,
            selected ? 8 : 3,
          ),
      );
      canvas.drawCircle(
        projected,
        circleRadius,
        Paint()
          ..color = scheme.primary.withValues(alpha: selected ? 0.95 : 0.8),
      );
      canvas.drawCircle(
        projected,
        circleRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.6 : 1.1
          ..color = scheme.onPrimary.withValues(alpha: 0.9),
      );
      if (circleRadius >= 13) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${cluster.count}',
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: math.min(13, circleRadius * 0.7),
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          projected - Offset(textPainter.width / 2, textPainter.height / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlobePainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.scale != scale ||
        oldDelegate.selectedKey != selectedKey ||
        oldDelegate.clusters != clusters ||
        oldDelegate.land != land ||
        oldDelegate.scheme != scheme;
  }
}
