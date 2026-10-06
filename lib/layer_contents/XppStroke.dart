import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/HexColor.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPageContentWidget.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/src/ink_geometry.dart';

abstract class XppStroke extends XppContent {
  XppStroke({
    this.tool = XppStrokeTool.PEN,
    this.points,
    this.color,
    this.editingTool,
  });

  XppStrokeTool tool;
  List<XppStrokePoint>? points;
  Color? color;
  EditingTool? editingTool;
  bool isShape = false; // forma geometrica: linea netta a spessore uniforme
  bool smooth =
      false; // forma curva (cerchio/ellisse): render con curva Bezier liscia

  /// Page-coordinate cuts. They remove only this stroke, never the background.
  List<StrokeErasure> erasures = [];
  static final _cutCaches =
      LinkedHashMap<XppStroke, _StrokeCutCache>.identity();
  static int _cutCachedSamples = 0;

  _StrokeCutCache get _cutCache {
    var cached = _cutCaches.remove(this);
    if (cached != null) _cutCachedSamples -= cached.cost;
    if (cached == null || !cached.matches(this)) cached = _StrokeCutCache(this);
    if (cached.cost <= 25000) {
      while (_cutCaches.isNotEmpty &&
          (_cutCaches.length >= 64 ||
              _cutCachedSamples + cached.cost > 25000)) {
        final removed = _cutCaches.remove(_cutCaches.keys.first)!;
        _cutCachedSamples -= removed.cost;
      }
      _cutCaches[this] = cached;
      _cutCachedSamples += cached.cost;
    }
    return cached;
  }

  void _invalidateCuts() {
    final removed = _cutCaches.remove(this);
    if (removed != null) _cutCachedSamples -= removed.cost;
  }

  Path get erasurePath {
    final cached = _cutCache.mask;
    if (cached != null) return cached;
    var mask = Path();
    for (final cut in erasures) {
      mask = Path.combine(PathOperation.union, mask, cut.path);
    }
    _cutCache.mask = mask;
    return mask;
  }

  Path get inkPath {
    final samples = points ?? <XppStrokePoint>[];
    if (!isShape) {
      return inkStrokePath(
        samples.map((p) => (position: p.offset, width: p.width)),
        pressureSensitive: tool == XppStrokeTool.PEN,
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

  Path get visibleInkPath {
    final cached = _cutCache.visible;
    if (cached != null) return cached;
    var path = inkPath;
    for (final cut in erasures) {
      path = Path.combine(PathOperation.difference, path, cut.path);
    }
    _cutCache.visible = path;
    return path;
  }

  bool intersectsErasure(StrokeErasure cut) => Path.combine(
    PathOperation.intersect,
    visibleInkPath,
    cut.path,
  ).computeMetrics().isNotEmpty;

  @override
  Offset getOffset() {
    if (points == null || points!.isEmpty) return const Offset(0, 0);
    double? x = points![0].x;
    points!.forEach((point) {
      if (point.x! < x!) x = point.x;
    });
    double y = points![0].y!;
    points!.forEach((point) {
      if (point.y! < y) y = point.y!;
    });
    return (Offset(x!, y));
  }

  Offset get bottomRight {
    if (points == null || points!.isEmpty) return const Offset(0, 0);
    double? x = points![0].x;
    points!.forEach((point) {
      if (point.x! > x!) x = point.x;
    });
    double y = points![0].y!;
    points!.forEach((point) {
      if (point.y! > y) y = point.y!;
    });
    return (Offset(x!, y));
  }

  // --- NUOVO METODO AD ALTE PRESTAZIONI ---
  @override
  void paintToCanvas(Canvas canvas, Size size) {
    if (points == null || points!.isEmpty) return;
    canvas.save();
    try {
      final offset = getOffset();
      if (erasures.isNotEmpty)
        canvas.clipPath(erasurePath.shift(-offset), clipOp: ClipOp.difference);

      // Calcoliamo il colore corretto senza sovrascrivere la variabile originale
      Color colorToUse = color ?? Colors.black;
      if (tool == XppStrokeTool.ERASER) colorToUse = Colors.white;
      if (tool == XppStrokeTool.HIGHLIGHTER) {
        colorToUse = colorToUse.withOpacity(.5);
      }

      // Forme geometriche: linea NETTA a spessore uniforme (niente perfect_freehand).
      if (isShape) {
        final Offset off = getOffset();
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
      final painter = XppStrokePainter(
        points: points,
        color: colorToUse,
        topLeft: getOffset(), // Il pittore disegna partendo da questo offset
        smoothPressure: tool == XppStrokeTool.PEN,
      );

      painter.paint(canvas, size);
    } finally {
      canvas.restore();
    }
  }

  // --- VECCHIO METODO (Mantenuto inattivo per evitare crash del resto dell'app) ---
  @override
  XppPageContentWidget render() {
    return XppPageContentWidget(
      tool: EditingTool.STYLUS,
      child:
          const SizedBox.shrink(), // Non crea piÃ¹ pesanti CustomPaint in un Widget
    );
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
        XmlAttribute(XmlName('color'), color!.toHexTriplet()),
        if (isShape) XmlAttribute(XmlName('osipp-shape'), 'true'),
        if (smooth) XmlAttribute(XmlName('osipp-smooth'), 'true'),
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
      eraseAlong(coordinates: coordinates!, radius: radius ?? 5);

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
    final replacement = newStroke(color: color, points: List.of(points!))
      ..isShape = isShape
      ..smooth = smooth
      ..editingTool = editingTool
      ..erasures = [...erasures, cut];
    final visible = Path.combine(
      PathOperation.difference,
      visibleInkPath,
      cut.path,
    );
    replacement._cutCache.visible = visible;
    replacement._cutCache.mask = Path.combine(
      PathOperation.union,
      erasurePath,
      cut.path,
    );
    final empty = visible.computeMetrics().isEmpty;
    return XppContentEraseData(
      affected: true,
      delete: empty,
      newContent: empty ? [] : [replacement],
    );
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
    if (isShape && smooth) return inkPath.getBounds();
    double radius = 0;
    for (final point in points!) {
      final r = isShape
          ? (point.width ?? 2.5).clamp(1.0, double.infinity) / 2
          : inkRadius(
              point.width,
              pressureSensitive: tool == XppStrokeTool.PEN,
            );
      if (r > radius) radius = r;
    }
    return Rect.fromPoints(getOffset(), bottomRight).inflate(radius);
  }

  @override
  void translate(Offset delta) {
    _invalidateCuts();
    erasures = erasures.map((e) => e.translate(delta)).toList();
    for (int i = 0; i < points!.length; i++) {
      final p = points![i];
      points![i] = XppStrokePoint(
        x: p.x! + delta.dx,
        y: p.y! + delta.dy,
        width: p.width,
      );
    }
  }

  @override
  void scaleBy(double factor, Offset anchor) {
    _invalidateCuts();
    erasures = erasures.map((e) => e.scale(factor, anchor)).toList();
    for (int i = 0; i < points!.length; i++) {
      final p = points![i];
      points![i] = XppStrokePoint(
        x: anchor.dx + (p.x! - anchor.dx) * factor,
        y: anchor.dy + (p.y! - anchor.dy) * factor,
        width: (p.width ?? 5) * factor,
      );
    }
  }

  XppStroke newStroke({Color? color, List<XppStrokePoint>? points});

  static XppStroke byTool({
    required XppStrokeTool tool,
    List<XppStrokePoint>? points,
    Color? color,
    bool isShape = false,
    bool smooth = false,
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
    return stroke;
  }
}

class XppStrokePen extends XppStroke {
  XppStrokeTool tool = XppStrokeTool.PEN;
  List<XppStrokePoint>? points;
  Color? color;

  EditingTool? editingTool;
  XppStrokePen({this.points, this.color})
    : super(
        points: points,
        color: color,
        tool: XppStrokeTool.PEN,
        editingTool: EditingTool.STYLUS,
      );

  @override
  XppStroke newStroke({Color? color, List<XppStrokePoint>? points}) {
    return XppStrokePen(points: points, color: color);
  }
}

class XppStrokeWhiteout extends XppStroke {
  XppStrokeTool tool = XppStrokeTool.ERASER;
  List<XppStrokePoint>? points;
  Color? color;

  EditingTool? editingTool;
  XppStrokeWhiteout({this.points, this.color})
    : super(
        points: points,
        color: color,
        tool: XppStrokeTool.ERASER,
        editingTool: EditingTool.WHITEOUT,
      );

  @override
  XppStroke newStroke({Color? color, List<XppStrokePoint>? points}) {
    return XppStrokeWhiteout(points: points, color: color);
  }
}

class XppStrokeHighlight extends XppStroke {
  XppStrokeTool tool = XppStrokeTool.HIGHLIGHTER;
  List<XppStrokePoint>? points;
  Color? color;

  EditingTool? editingTool;
  XppStrokeHighlight({this.points, this.color})
    : super(
        points: points,
        color: color,
        tool: XppStrokeTool.HIGHLIGHTER,
        editingTool: EditingTool.HIGHLIGHT,
      );

  @override
  XppStroke newStroke({Color? color, List<XppStrokePoint>? points}) {
    return XppStrokeHighlight(points: points, color: color);
  }
}

// MANTENIAMO IL PITTORE ORIGINALE perchÃ© il "PointerListener" lo usa
// in tempo reale per disegnare il tratto che hai sotto la punta della penna!
class XppStrokePainter extends CustomPainter {
  final List<XppStrokePoint>? points;
  final Color? color;
  final Offset? topLeft;
  final bool? smoothPressure;
  final bool isComplete;

  // Bound retained geometry across documents. Point identity checks invalidate
  // edits, translations and resizes; snapshots only copy references.
  static final _paths =
      LinkedHashMap<List<XppStrokePoint>, _CachedInkPath>.identity();
  static int _cachedSamples = 0;
  static const _maxCachedStrokes = 64;
  static const _maxCachedSamples = 25000;

  XppStrokePainter({
    this.points,
    this.color,
    this.topLeft,
    this.smoothPressure,
    this.isComplete = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final samples = points;
    if (samples == null || samples.isEmpty) return;
    final pressureSensitive = smoothPressure == true;
    var cached = _paths.remove(samples);
    if (cached != null) _cachedSamples -= cached.samples.length;
    if (cached == null || !cached.matches(samples, pressureSensitive)) {
      cached = _CachedInkPath(samples, pressureSensitive);
    }
    if (samples.length <= _maxCachedSamples) {
      while (_paths.isNotEmpty &&
          (_paths.length >= _maxCachedStrokes ||
              _cachedSamples + samples.length > _maxCachedSamples)) {
        final evicted = _paths.remove(_paths.keys.first)!;
        _cachedSamples -= evicted.samples.length;
      }
      _paths[samples] = cached;
      _cachedSamples += cached.samples.length;
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
  final List<XppStrokePoint> samples;
  final bool pressureSensitive;
  final Path path;

  _CachedInkPath(List<XppStrokePoint> points, this.pressureSensitive)
    : samples = List.of(points),
      path = inkStrokePath(
        points.map((point) => (position: point.offset, width: point.width)),
        pressureSensitive: pressureSensitive,
      );

  bool matches(List<XppStrokePoint> points, bool pressureSensitive) {
    if (this.pressureSensitive != pressureSensitive ||
        samples.length != points.length)
      return false;
    for (var i = 0; i < samples.length; i++) {
      if (!identical(samples[i], points[i])) return false;
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

/// Native paths stay outside the sendable document/snapshot model. Retention
/// is capped by stroke count and sample budget, matching the painter cache.
class _StrokeCutCache {
  _StrokeCutCache(XppStroke stroke)
    : samples = List.of(stroke.points ?? <XppStrokePoint>[]),
      cuts = List.of(stroke.erasures),
      shape = stroke.isShape,
      smooth = stroke.smooth,
      tool = stroke.tool;
  final List<XppStrokePoint> samples;
  final List<StrokeErasure> cuts;
  final bool shape;
  final bool smooth;
  final XppStrokeTool tool;
  Path? visible;
  Path? mask;
  int get cost => samples.length + cuts.length * 6;
  bool matches(XppStroke stroke) {
    final points = stroke.points ?? <XppStrokePoint>[];
    if (shape != stroke.isShape ||
        smooth != stroke.smooth ||
        tool != stroke.tool ||
        samples.length != points.length ||
        cuts.length != stroke.erasures.length)
      return false;
    for (int i = 0; i < samples.length; i++) {
      if (!identical(samples[i], points[i])) return false;
    }
    for (int i = 0; i < cuts.length; i++) {
      if (!identical(cuts[i], stroke.erasures[i])) return false;
    }
    return true;
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
