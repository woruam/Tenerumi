import 'dart:ui';

/// Radius used by both live and committed freehand ink.
double inkRadius(double? width, {required bool pressureSensitive}) {
  final pressure = ((width ?? 2.5) / 5).clamp(0.1, 1.0);
  return pressureSensitive ? 5 * (0.5 - 0.7 * (0.5 - pressure)) : 2.5;
}

Path inkStrokePath(
  Iterable<({Offset position, double? width})> samples, {
  required bool pressureSensitive,
}) {
  final geometry = InkGeometry();
  for (final sample in samples) {
    geometry.append(
      sample.position,
      sample.width,
      pressureSensitive: pressureSensitive,
    );
  }
  return geometry.path;
}

/// Incremental round ink: one capsule per sample, with a single filled path.
/// Matching winding keeps intersections filled without darkening highlighters.
class InkGeometry {
  final Path path = Path();
  Offset? _previous;
  double _previousRadius = 0;

  void append(
    Offset position,
    double? width, {
    required bool pressureSensitive,
  }) {
    final radius = inkRadius(width, pressureSensitive: pressureSensitive);
    final previous = _previous;
    if (previous != null && position != previous) {
      final delta = position - previous;
      final normal = Offset(-delta.dy, delta.dx) / delta.distance;
      path.addPolygon([
        previous - normal * _previousRadius,
        position - normal * radius,
        position + normal * radius,
        previous + normal * _previousRadius,
      ], true);
    }
    path.addOval(Rect.fromCircle(center: position, radius: radius));
    _previous = position;
    _previousRadius = radius;
  }

  void clear() {
    path.reset();
    _previous = null;
    _previousRadius = 0;
  }
}
