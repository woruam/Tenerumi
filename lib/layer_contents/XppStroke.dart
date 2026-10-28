import 'package:xournalpp/src/note_audio.dart';

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/HexColor.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/src/ink_geometry.dart';

abstract class XppStroke extends XppContent {
  XppStroke({
    this.tool = XppStrokeTool.PEN,
    List<XppStrokePoint>? points,
    this.color,
    this.editingTool,
  }) : _points = points == null ? null : List.unmodifiable(points);

  XppStrokeTool tool;
  List<XppStrokePoint>? _points;
  List<XppStrokePoint>? get points => _points;
  set points(List<XppStrokePoint>? value) =>
      _points = value == null ? null : List.unmodifiable(value);

  /// Points are immutable; translations/scales replace the complete list.
  /// History and background saves share this buffer without copying each point.
  XppStroke copyWithSharedPoints() => newStroke(color: color)
    .._points = _points
    ..audioLink = audioLink
    ..editingTool = editingTool
    ..widthIsDiameter = widthIsDiameter
    ..isShape = isShape
    ..smooth = smooth
    ..erasures = List.of(erasures);
  Color? color;

  /// Old documents store the legacy pressure proxy; new ink stores diameters.
  bool widthIsDiameter = false;
  EditingTool? editingTool;
  StrokeAudioLink? audioLink;
  bool isShape = false; // forma geometrica: linea netta a spessore uniforme
  bool smooth =
      false; // forma curva (cerchio/ellisse): render con curva Bezier liscia

  /// Page-coordinate cuts. They remove only this stroke, never the background.
  List<StrokeErasure> erasures = [];
  Path _erasurePathIn(Rect visible) {
    final mask = Path();
    for (final cut in erasures) {
      if (cut.bounds.overlaps(visible)) mask.addPath(cut.path, Offset.zero);
    }
    return mask;
  }

  Path get inkPath {
    final samples = points ?? <XppStrokePoint>[];
    if (!isShape) {
      return inkStrokePath(
        samples.map((p) => (position: p.offset, width: p.width)),
        pressureSensitive: tool == XppStrokeTool.PEN && !widthIsDiameter,
      );
    }
    if (samples.isEmpty) return Path();
    final positions = samples.map((p) => p.offset).toList();
    final closed = (positions.first - positions.last).distance < 1;
    final centerline = smooth && positions.length >= 4
        ? _smoothPath(positions, closed)
        : (Path()..addPolygon(positions, closed));
    final outline = Path();
    final radius = (samples.first.width ?? 2.5).clamp(1.0, double.infinity) / 2;
    for (final metric in centerline.computeMetrics()) {
      Offset? previous;
      for (double d = 0; d < metric.length; d += .5) {
        final p = metric.getTangentForOffset(d)!.position;
        outline.addPath(
          StrokeErasure(previous ?? p, p, radius).path,
          Offset.zero,
        );
        previous = p;
      }
      final end = metric.getTangentForOffset(metric.length)?.position;
      if (end != null)
        outline.addPath(
          StrokeErasure(previous ?? end, end, radius).path,
          Offset.zero,
        );
    }
    if (positions.length == 1)
      outline.addOval(Rect.fromCircle(center: positions.first, radius: radius));
    return outline;
  }

  bool containsVisibleInk(Offset point) =>
      inkPath.contains(point) && !erasures.any((cut) => cut.contains(point));

  bool intersectsErasure(StrokeErasure cut) {
    if (!cut.isValid || erasures.any((old) => old.covers(cut))) return false;
    final samples = points;
    if (samples == null || samples.isEmpty) return false;
    double radius(XppStrokePoint p) => isShape
        ? (p.width ?? 2.5).clamp(1.0, double.infinity) / 2
        : inkRadius(
            p.width,
            pressureSensitive: tool == XppStrokeTool.PEN && !widthIsDiameter,
          );
    if (isShape && smooth && samples.length >= 4) {
      final positions = samples.map((p) => p.offset).toList();
      final curve = _smoothPath(
        positions,
        (positions.first - positions.last).distance < 1,
      );
      for (final metric in curve.computeMetrics()) {
        var previous = metric.getTangentForOffset(0)?.position;
        if (previous == null) continue;
        for (double d = .5; d < metric.length + .5; d += .5) {
          final next = metric
              .getTangentForOffset(math.min(d, metric.length))
              ?.position;
          if (next == null) continue;
          if (_segmentDistance(previous!, next, cut.start, cut.end) <=
              radius(samples.first) + cut.radius)
            return true;
          previous = next;
        }
      }
      return false;
    }
    for (int i = 0; i < samples.length; i++) {
      final a = samples[i];
      final b = samples[math.min(i + 1, samples.length - 1)];
      if (_segmentDistance(a.offset, b.offset, cut.start, cut.end) <=
          math.max(radius(a), radius(b)) + cut.radius)
        return true;
    }
    return false;
  }

  @override
  Offset getOffset() {
    final samples = points;
    if (samples == null || samples.isEmpty) return Offset.zero;
    return _sampleExtrema(samples).rect.topLeft;
  }

  Offset get bottomRight {
    final samples = points;
    if (samples == null || samples.isEmpty) return Offset.zero;
    return _sampleExtrema(samples).rect.bottomRight;
  }

  // --- NUOVO METODO AD ALTE PRESTAZIONI ---
  @override
  void paintToCanvas(Canvas canvas, Size size) {
    if (points == null || points!.isEmpty) return;
    // Cached sample bounds let dense pages skip offscreen ink before building
    // or drawing its path. Smooth shapes keep their full spline bounds below.
    if (!isShape || !smooth) {
      final extrema = _sampleExtrema(points!);
      final radius = isShape
          ? extrema.shapeRadius
          : tool == XppStrokeTool.PEN && !widthIsDiameter
          ? extrema.penRadius
          : extrema.flatRadius;
      final localBounds = extrema.rect.inflate(radius).shift(-getOffset());
      if (!localBounds.overlaps(canvas.getLocalClipBounds())) return;
    }
    canvas.save();
    final offset = getOffset();
    final masked = erasures.isNotEmpty;
    Rect? layerRegion;
    if (masked) {
      // Isolate only visible ink: dstOut must never erase the PDF or another
      // stroke, and zoom must not allocate an offscreen image of the whole page.
      final region = bounds()!
          .shift(-offset)
          .inflate(1)
          .intersect(canvas.getLocalClipBounds());
      if (region.isEmpty) {
        canvas.restore();
        return;
      }
      layerRegion = region;
      canvas.saveLayer(region, Paint());
    }
    try {
      // Calcoliamo il colore corretto senza sovrascrivere la variabile originale
      Color colorToUse = color ?? Colors.black;
      if (tool == XppStrokeTool.ERASER) colorToUse = Colors.white;
      if (tool == XppStrokeTool.HIGHLIGHTER) {
        colorToUse = colorToUse.withOpacity(.5);
      }

      // Forme geometriche: linea NETTA a spessore uniforme (niente perfect_freehand).
      if (isShape) {
        final Offset off = offset;
        double sw = points!.first.width ?? 2.5;
        if (sw < 1.0) sw = 1.0;
        final Paint sp = Paint()
          ..color = colorToUse
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
        final XppStrokePoint a = points!.first, b = points!.last;
        final bool closed = ((a.x! - b.x!).abs() + (a.y! - b.y!).abs()) < 1.0;
        final List<Offset> pts = [
          for (final pt in points!) Offset(pt.x! - off.dx, pt.y! - off.dy),
        ];
        Path shapePath;
        if (smooth && pts.length >= 4) {
          // forme curve (cerchio/sfera/cilindro): curva Bezier liscia a ogni zoom
          shapePath = _smoothPath(pts, closed);
        } else {
          shapePath = Path()..moveTo(pts.first.dx, pts.first.dy);
          for (int i = 1; i < pts.length; i++) {
            shapePath.lineTo(pts[i].dx, pts[i].dy);
          }
          if (closed) shapePath.close();
        }
        canvas.drawPath(shapePath, sp);
        return;
      }

      // Usiamo il pittore esistente per disegnare DIRETTAMENTE sul Canvas
      final painter = XppStrokePainter._committed(
        points: points,
        color: colorToUse,
        topLeft: offset, // Reuse the origin already calculated for this paint.
        smoothPressure: tool == XppStrokeTool.PEN && !widthIsDiameter,
      );

      painter.paint(canvas, size);
    } finally {
      if (masked) {
        canvas.translate(-offset.dx, -offset.dy);
        canvas.drawPath(
          _erasurePathIn(layerRegion!.shift(offset)),
          Paint()
            ..color = Colors.black
            ..blendMode = BlendMode.dstOut
            ..isAntiAlias = true,
        );
        canvas.restore();
      }
      canvas.restore();
    }
  }

  @override
  XmlElement toXmlElement() {
    late String toolString;
    switch (tool) {
      case XppStrokeTool.PEN:
        toolString = 'pen';
        break;
      case XppStrokeTool.HIGHLIGHTER:
        toolString = 'highlighter';
        break;
      case XppStrokeTool.ERASER:
        toolString = 'eraser';
        break;
    }
    XmlElement node = XmlElement(
      XmlName('stroke'),
      [
        XmlAttribute(XmlName('tool'), toolString),
        ...?audioLink?.attributes,
        XmlAttribute(XmlName('color'), color!.toHexTriplet()),
        if (isShape) XmlAttribute(XmlName('osipp-shape'), 'true'),
        if (smooth) XmlAttribute(XmlName('osipp-smooth'), 'true'),
        if (widthIsDiameter) XmlAttribute(XmlName('osipp-width'), 'diameter'),
        if (erasures.isNotEmpty)
          XmlAttribute(
            XmlName('osipp-erasures'),
            erasures.map((e) => e.encode()).join(';'),
          ),
        XmlAttribute(
          XmlName('width'),
          points!.map((e) => e.width.toString()).join(' '),
        ),
      ],
      [
        XmlText(
          points!.map((e) => e.x.toString() + ' ' + e.y.toString()).join(' '),
        ),
      ],
    );
    return node;
  }

  @override
  XppContentEraseData eraseWhere({Offset? coordinates, double? radius}) =>
      coordinates == null
      ? XppContentEraseData()
      : eraseAlong(coordinates: coordinates, radius: radius ?? 5);

  XppContentEraseData eraseAlong({
    required Offset coordinates,
    Offset? previousCoordinates,
    required double radius,
  }) {
    if (!radius.isFinite || radius <= 0) return XppContentEraseData();
    final cut = StrokeErasure(
      previousCoordinates ?? coordinates,
      coordinates,
      radius,
    );
    if (!intersectsErasure(cut)) return XppContentEraseData();
    final cuts = List<StrokeErasure>.of(erasures);
    if (cuts.isNotEmpty && cuts.last.canMerge(cut)) {
      cuts[cuts.length - 1] = StrokeErasure(cuts.last.start, cut.end, radius);
    } else {
      cuts.add(cut);
    }
    final replacement = newStroke(color: color)
      .._points = _points
      ..audioLink = audioLink
      ..isShape = isShape
      ..smooth = smooth
      ..editingTool = editingTool
      ..widthIsDiameter = widthIsDiameter
      ..erasures = cuts;

    return XppContentEraseData(affected: true, newContent: [replacement]);
  }

  @override
  bool inRegion({Offset? topLeft, Offset? bottomRight}) {
    final rect = Rect.fromPoints(topLeft!, bottomRight!);
    return points!.any((p) => rect.contains(p.offset));
  }

  @override
  bool shouldSelectAt({Offset? coordinates, EditingTool? tool}) {
    if (coordinates == null) return false;
    return points!.any(
      (p) => (p.offset - coordinates).distance < (p.width ?? 5) + 8,
    );
  }

  @override
  Rect? bounds() {
    if (points == null || points!.isEmpty) return null;
    if (isShape && smooth) {
      final positions = points!.map((p) => p.offset).toList();
      return _smoothPath(
        positions,
        (positions.first - positions.last).distance < 1,
      ).getBounds().inflate(
        (points!.first.width ?? 2.5).clamp(1.0, double.infinity) / 2,
      );
    }
    final extrema = _sampleExtrema(points!);
    final radius = isShape
        ? extrema.shapeRadius
        : tool == XppStrokeTool.PEN && !widthIsDiameter
        ? extrema.penRadius
        : extrema.flatRadius;
    return extrema.rect.inflate(radius);
  }

  @override
  void translate(Offset delta) {
    erasures = erasures.map((e) => e.translate(delta)).toList();
    points = [
      for (final p in points!)
        XppStrokePoint(x: p.x! + delta.dx, y: p.y! + delta.dy, width: p.width),
    ];
  }

  @override
  void scaleBy(double factor, Offset anchor) {
    erasures = erasures.map((e) => e.scale(factor, anchor)).toList();
    points = [
      for (final p in points!)
        XppStrokePoint(
          x: anchor.dx + (p.x! - anchor.dx) * factor,
          y: anchor.dy + (p.y! - anchor.dy) * factor,
          width: (p.width ?? 5) * factor,
        ),
    ];
  }

  XppStroke newStroke({Color? color, List<XppStrokePoint>? points});

  static XppStroke byTool({
    required XppStrokeTool tool,
    List<XppStrokePoint>? points,
    Color? color,
    bool isShape = false,
    bool smooth = false,
    bool widthIsDiameter = false,
  }) {
    XppStroke? stroke;
    switch (tool) {
      case XppStrokeTool.PEN:
        stroke = XppStrokePen(color: color, points: points);
        break;
      case XppStrokeTool.HIGHLIGHTER:
        stroke = XppStrokeHighlight(color: color, points: points);
        break;
      case XppStrokeTool.ERASER:
        stroke = XppStrokeWhiteout(color: color, points: points);
        break;
    }
    stroke.isShape = isShape;
    stroke.smooth = smooth;
    stroke.widthIsDiameter = widthIsDiameter;
    return stroke;
  }
}

class XppStrokePen extends XppStroke {
  XppStrokePen({List<XppStrokePoint>? points, Color? color})
    : super(points: points, color: color, tool: XppStrokeTool.PEN);

  @override
  XppStroke newStroke({Color? color, List<XppStrokePoint>? points}) {
    return XppStrokePen(points: points, color: color);
  }
}

class XppStrokeWhiteout extends XppStroke {
  XppStrokeWhiteout({List<XppStrokePoint>? points, Color? color})
    : super(points: points, color: color, tool: XppStrokeTool.ERASER);

  @override
  XppStroke newStroke({Color? color, List<XppStrokePoint>? points}) {
    return XppStrokeWhiteout(points: points, color: color);
  }
}

class XppStrokeHighlight extends XppStroke {
  XppStrokeHighlight({List<XppStrokePoint>? points, Color? color})
    : super(points: points, color: color, tool: XppStrokeTool.HIGHLIGHTER);

  @override
  XppStroke newStroke({Color? color, List<XppStrokePoint>? points}) {
    return XppStrokeHighlight(points: points, color: color);
  }
}

// Committed freehand ink shares the live preview geometry.
class XppStrokePainter extends CustomPainter {
  @visibleForTesting
  static int debugPathBuilds = 0;
  @visibleForTesting
  static int debugBoundsBuilds = 0;
  @visibleForTesting
  static int get debugRetainedSamples => _retainedSamples;
  @visibleForTesting
  static int get debugRetainedPaths => _workingPaths.length;
  final List<XppStrokePoint>? points;
  final Color? color;
  final Offset? topLeft;
  final bool? smoothPressure;
  final bool isComplete;
  final bool _immutableSamples;

  // A bounded strong working set protects recently used paths. Evicted entries
  // remain weakly discoverable until memory pressure collects them, avoiding
  // sequential repaint thrash without retaining every visited document's paths.
  static final _paths = Expando<WeakReference<_CachedInkPath>>();
  static final _workingPaths = LinkedHashMap<_CachedInkPath, int>.identity();
  static int _retainedSamples = 0;
  static const _maxCachedStrokes = 64;
  static const _maxCachedSamples = 25000;

  XppStrokePainter({
    this.points,
    this.color,
    this.topLeft,
    this.smoothPressure,
    this.isComplete = true,
  }) : _immutableSamples = false;

  XppStrokePainter._committed({
    this.points,
    this.color,
    this.topLeft,
    this.smoothPressure,
  }) : isComplete = true,
       _immutableSamples = true;

  @override
  void paint(Canvas canvas, Size size) {
    final samples = points;
    if (samples == null || samples.isEmpty) return;
    final pressureSensitive = smoothPressure == true;
    var cached = _paths[samples]?.target;
    if (cached == null ||
        !cached.matches(
          samples,
          pressureSensitive,
          immutable: _immutableSamples,
        )) {
      debugPathBuilds++;
      cached = _CachedInkPath(
        samples,
        pressureSensitive,
        immutable: _immutableSamples,
      );
    }
    if (samples.length <= _maxCachedSamples) {
      _paths[samples] = WeakReference(cached);
      _retainedSamples -= _workingPaths.remove(cached) ?? 0;
      while (_workingPaths.isNotEmpty &&
          (_workingPaths.length >= _maxCachedStrokes ||
              _retainedSamples + samples.length > _maxCachedSamples)) {
        _retainedSamples -= _workingPaths.remove(_workingPaths.keys.first)!;
      }
      _workingPaths[cached] = samples.length;
      _retainedSamples += samples.length;
    }
    final origin = topLeft ?? Offset.zero;
    canvas.save();
    canvas.translate(-origin.dx, -origin.dy);
    canvas.drawPath(
      cached.path,
      Paint()
        ..color = color ?? Colors.black
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class _CachedInkPath {
  final List<XppStrokePoint>? samples;
  final bool pressureSensitive;
  final Path path;

  _CachedInkPath(
    List<XppStrokePoint> points,
    this.pressureSensitive, {
    required bool immutable,
  }) : samples = immutable ? null : List.of(points),
       path = inkStrokePath(
         points.map((point) => (position: point.offset, width: point.width)),
         pressureSensitive: pressureSensitive,
       );

  bool matches(
    List<XppStrokePoint> points,
    bool pressureSensitive, {
    required bool immutable,
  }) {
    if (this.pressureSensitive != pressureSensitive) return false;
    if (immutable && samples == null) return true;
    final previous = samples;
    if (previous == null || previous.length != points.length) return false;
    for (var i = 0; i < previous.length; i++) {
      if (!identical(previous[i], points[i])) return false;
    }
    return true;
  }
}

enum XppStrokeTool { PEN, HIGHLIGHTER, ERASER }

/// Circular tip swept continuously between two delivered pointer samples.
class StrokeErasure {
  const StrokeErasure(this.start, this.end, this.radius);
  final Offset start;
  final Offset end;
  final double radius;

  bool get isValid =>
      radius.isFinite &&
      radius > 0 &&
      start.dx.isFinite &&
      start.dy.isFinite &&
      end.dx.isFinite &&
      end.dy.isFinite;
  Rect get bounds => Rect.fromPoints(start, end).inflate(radius);
  bool contains(Offset p) => _pointSegmentDistance(p, start, end) <= radius;
  bool covers(StrokeErasure other) =>
      isValid &&
      other.isValid &&
      _pointSegmentDistance(other.start, start, end) + other.radius <=
          radius + 1e-9 &&
      _pointSegmentDistance(other.end, start, end) + other.radius <=
          radius + 1e-9;
  bool canMerge(StrokeErasure other) {
    if (radius != other.radius || (end - other.start).distance > 1e-9)
      return false;
    final a = end - start;
    final b = other.end - other.start;
    if (a.distanceSquared == 0 || b.distanceSquared == 0) return true;
    return (a.dx * b.dy - a.dy * b.dx).abs() <= 1e-9 &&
        a.dx * b.dx + a.dy * b.dy >= 0;
  }

  Path get path {
    final path = Path()
      ..addOval(Rect.fromCircle(center: start, radius: radius))
      ..addOval(Rect.fromCircle(center: end, radius: radius));
    final delta = end - start;
    if (delta.distance > 0) {
      final normal = Offset(-delta.dy, delta.dx) / delta.distance * radius;
      path.addPolygon([
        start - normal,
        end - normal,
        end + normal,
        start + normal,
      ], true);
    }
    return path;
  }

  StrokeErasure translate(Offset delta) =>
      StrokeErasure(start + delta, end + delta, radius);
  StrokeErasure scale(double factor, Offset anchor) => StrokeErasure(
    anchor + (start - anchor) * factor,
    anchor + (end - anchor) * factor,
    radius * factor.abs(),
  );
  String encode() => '${start.dx} ${start.dy} ${end.dx} ${end.dy} $radius';
  static List<StrokeErasure> decode(String? value) {
    if (value == null || value.trim().isEmpty) return [];
    return value.split(';').map((part) {
      final numbers = part
          .trim()
          .split(RegExp(r'\s+'))
          .map(double.parse)
          .toList();
      if (numbers.length != 5 ||
          numbers.any((n) => !n.isFinite) ||
          numbers[4] <= 0) {
        throw const FormatException('Invalid stroke erasure');
      }
      return StrokeErasure(
        Offset(numbers[0], numbers[1]),
        Offset(numbers[2], numbers[3]),
        numbers[4],
      );
    }).toList();
  }
}

double _pointSegmentDistance(Offset p, Offset a, Offset b) {
  final delta = b - a;
  if (delta.distanceSquared == 0) return (p - a).distance;
  final t =
      (((p - a).dx * delta.dx + (p - a).dy * delta.dy) / delta.distanceSquared)
          .clamp(0.0, 1.0);
  return (p - (a + delta * t)).distance;
}

double _segmentDistance(Offset a, Offset b, Offset c, Offset d) {
  final ab = b - a;
  final cd = d - c;
  final cross = ab.dx * cd.dy - ab.dy * cd.dx;
  if (cross.abs() > 1e-12) {
    final ca = c - a;
    final t = (ca.dx * cd.dy - ca.dy * cd.dx) / cross;
    final u = (ca.dx * ab.dy - ca.dy * ab.dx) / cross;
    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) return 0;
  }
  return math.min(
    math.min(_pointSegmentDistance(a, c, d), _pointSegmentDistance(b, c, d)),
    math.min(_pointSegmentDistance(c, a, b), _pointSegmentDistance(d, a, b)),
  );
}

// Only committed strokes use this cache: their point buffers and points are
// immutable. Transformations replace the buffer, so history retains its bounds.
final _extrema = Expando<_StrokeExtrema>();
_StrokeExtrema _sampleExtrema(List<XppStrokePoint> points) =>
    _extrema[points] ??= _StrokeExtrema(points);

class _StrokeExtrema {
  late final Rect rect;
  double penRadius = 0, flatRadius = 0, shapeRadius = 0;
  _StrokeExtrema(List<XppStrokePoint> points) {
    XppStrokePainter.debugBoundsBuilds++;
    var left = points.first.x!, top = points.first.y!;
    var right = left, bottom = top;
    for (final point in points) {
      left = math.min(left, point.x!);
      top = math.min(top, point.y!);
      right = math.max(right, point.x!);
      bottom = math.max(bottom, point.y!);
      penRadius = math.max(
        penRadius,
        inkRadius(point.width, pressureSensitive: true),
      );
      flatRadius = math.max(
        flatRadius,
        inkRadius(point.width, pressureSensitive: false),
      );
      shapeRadius = math.max(
        shapeRadius,
        (point.width ?? 2.5).clamp(1.0, double.infinity) / 2,
      );
    }
    rect = Rect.fromLTRB(left, top, right, bottom);
  }
}

class XppStrokePoint {
  final double? x;
  final double? y;
  final double? width;

  XppStrokePoint({this.x, this.y, this.width});

  Offset get offset => Offset(x!, y!);
}

/// Curva liscia (Catmull-Rom -> Bezier cubiche) dai punti dati.
/// Usata per le forme curve (cerchi, ellissi): restano lisce a qualsiasi zoom.
Path _smoothPath(List<Offset> p, bool closed) {
  final Path path = Path();
  final int n = p.length;
  if (n < 3) {
    if (n > 0) {
      path.moveTo(p.first.dx, p.first.dy);
      for (int i = 1; i < n; i++) {
        path.lineTo(p[i].dx, p[i].dy);
      }
    }
    return path;
  }
  final List<Offset> q = (closed && (p.first - p.last).distance < 1.0)
      ? p.sublist(0, n - 1)
      : p;
  final int m = q.length;
  Offset at(int i) => closed ? q[((i % m) + m) % m] : q[i.clamp(0, m - 1)];
  path.moveTo(q[0].dx, q[0].dy);
  final int segs = closed ? m : m - 1;
  for (int i = 0; i < segs; i++) {
    final Offset p0 = at(i - 1);
    final Offset p1 = at(i);
    final Offset p2 = at(i + 1);
    final Offset p3 = at(i + 2);
    final Offset c1 = Offset(
      p1.dx + (p2.dx - p0.dx) / 6,
      p1.dy + (p2.dy - p0.dy) / 6,
    );
    final Offset c2 = Offset(
      p2.dx - (p3.dx - p1.dx) / 6,
      p2.dy - (p3.dy - p1.dy) / 6,
    );
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  if (closed) path.close();
  return path;
}
