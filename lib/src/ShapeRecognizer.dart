import 'dart:math';
import 'dart:ui';

import 'package:xournalpp/layer_contents/XppStroke.dart';

/// Heuristic shape recognition: straightens hand-drawn lines, circles,
/// triangles and rectangles, similar to the shape recognizer of desktop
/// Xournal++ and modern note-taking apps.
class ShapeRecognizer {
  /// Returns straightened points if a shape was recognized, otherwise null.
  static List<XppStrokePoint>? recognize(List<XppStrokePoint> points) {
    if (points.length < 8) return null;
    final pts = points.map((p) => Offset(p.x ?? 0, p.y ?? 0)).toList();
    double avgWidth = 0;
    for (final p in points) {
      avgWidth += p.width ?? 2;
    }
    avgWidth /= points.length;

    double perimeter = 0;
    for (int i = 1; i < pts.length; i++) {
      perimeter += (pts[i] - pts[i - 1]).distance;
    }
    if (perimeter < 20) return null;

    final line = _recognizeLine(pts, avgWidth, perimeter);
    if (line != null) return line;

    final bool closed = (pts.first - pts.last).distance < 0.2 * perimeter;
    if (!closed) return null;

    final circle = _recognizeCircle(pts, avgWidth);
    if (circle != null) return circle;

    return _recognizePolygon(pts, avgWidth, perimeter);
  }

  static List<XppStrokePoint>? _recognizeLine(
      List<Offset> pts, double width, double perimeter) {
    final start = pts.first, end = pts.last;
    final length = (end - start).distance;
    if (length < 20) return null;
    // a straight line should not be much longer than the segment
    if (perimeter > length * 1.15) return null;
    double maxDeviation = 0;
    for (final p in pts) {
      maxDeviation = max(maxDeviation, _distanceToSegment(p, start, end));
    }
    if (maxDeviation > max(8, 0.06 * length)) return null;
    return [
      XppStrokePoint(x: start.dx, y: start.dy, width: width),
      XppStrokePoint(x: end.dx, y: end.dy, width: width),
    ];
  }

  static List<XppStrokePoint>? _recognizeCircle(
      List<Offset> pts, double width) {
    double cx = 0, cy = 0;
    for (final p in pts) {
      cx += p.dx;
      cy += p.dy;
    }
    final center = Offset(cx / pts.length, cy / pts.length);
    final radii = pts.map((p) => (p - center).distance).toList();
    final meanR = radii.reduce((a, b) => a + b) / radii.length;
    if (meanR < 10) return null;
    double variance = 0;
    for (final r in radii) {
      variance += (r - meanR) * (r - meanR);
    }
    final std = sqrt(variance / radii.length);
    if (std / meanR > 0.16) return null;
    const segments = 36;
    return List.generate(segments + 1, (i) {
      final angle = 2 * pi * i / segments;
      return XppStrokePoint(
          x: center.dx + meanR * cos(angle),
          y: center.dy + meanR * sin(angle),
          width: width);
    });
  }

  static List<XppStrokePoint>? _recognizePolygon(
      List<Offset> pts, double width, double perimeter) {
    final epsilon = 0.025 * perimeter;
    List<Offset> corners = _ramerDouglasPeucker(pts, epsilon);
    // merge first/last corner of a closed shape
    if (corners.length > 2 &&
        (corners.first - corners.last).distance < epsilon * 2) {
      corners.removeLast();
    }
    if (corners.length < 3 || corners.length > 5) return null;
    final result = <XppStrokePoint>[];
    for (final c in corners) {
      result.add(XppStrokePoint(x: c.dx, y: c.dy, width: width));
    }
    // close the polygon
    result.add(
        XppStrokePoint(x: corners.first.dx, y: corners.first.dy, width: width));
    return result;
  }

  static List<Offset> _ramerDouglasPeucker(List<Offset> pts, double epsilon) {
    if (pts.length < 3) return List.of(pts);
    double maxDistance = 0;
    int index = 0;
    for (int i = 1; i < pts.length - 1; i++) {
      final d = _distanceToSegment(pts[i], pts.first, pts.last);
      if (d > maxDistance) {
        maxDistance = d;
        index = i;
      }
    }
    if (maxDistance > epsilon) {
      final left = _ramerDouglasPeucker(pts.sublist(0, index + 1), epsilon);
      final right = _ramerDouglasPeucker(pts.sublist(index), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [pts.first, pts.last];
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) return (p - a).distance;
    double t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSquared;
    t = t.clamp(0.0, 1.0);
    final projection = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - projection).distance;
  }
}
