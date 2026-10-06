import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/HexColor.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPageContentWidget.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

import 'package:perfect_freehand/perfect_freehand.dart' as pf;

abstract class XppStroke extends XppContent {
  XppStroke(
      {this.tool = XppStrokeTool.PEN,
      this.points,
      this.color,
      this.editingTool});

  XppStrokeTool tool;
  List<XppStrokePoint>? points;
  Color? color;
  EditingTool? editingTool;
  bool isShape = false; // forma geometrica: linea netta a spessore uniforme
  bool smooth =
      false; // forma curva (cerchio/ellisse): render con curva Bezier liscia

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
        for (final pt in points!) Offset(pt.x! - off.dx, pt.y! - off.dy)
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
  }

  // --- VECCHIO METODO (Mantenuto inattivo per evitare crash del resto dell'app) ---
  @override
  XppPageContentWidget render() {
    return XppPageContentWidget(
      tool: EditingTool.STYLUS,
      child: const SizedBox
          .shrink(), // Non crea più pesanti CustomPaint in un Widget
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
    XmlElement node = XmlElement(XmlName('stroke'), [
      XmlAttribute(XmlName('tool'), toolString),
      XmlAttribute(XmlName('color'), color!.toHexTriplet()),
      XmlAttribute(
          XmlName('width'), points!.map((e) => e.width.toString()).join(' ')),
    ], [
      XmlText(
          points!.map((e) => e.x.toString() + ' ' + e.y.toString()).join(' '))
    ]);
    return node;
  }

  bool _shouldErase({Offset? coordinates, double? radius}) {
    bool erase = false;
    points!.forEach((element) {
      if (_shouldRemovePoint(element, coordinates!, radius!)) erase = true;
    });
    return (erase);
  }

  @override
  XppContentEraseData eraseWhere({Offset? coordinates, double? radius}) {
    if (!_shouldErase(coordinates: coordinates, radius: radius))
      return XppContentEraseData();
    List<XppStroke> newStrokes = [];
    bool lastPointRemoved = true;
    for (int i = 0; i < points!.length; i++) {
      if (_shouldRemovePoint(points![i], coordinates!, radius!)) {
        lastPointRemoved = true;
      } else {
        if (lastPointRemoved) {
          newStrokes.add(newStroke(color: color, points: [points![i]]));
        } else {
          newStrokes.last.points!.add(points![i]);
        }
        lastPointRemoved = false;
      }
    }
    return XppContentEraseData(
        affected: true, delete: newStrokes.isEmpty, newContent: newStrokes);
  }

  @override
  bool inRegion({Offset? topLeft, Offset? bottomRight}) {
    final rect = Rect.fromPoints(topLeft!, bottomRight!);
    return points!.any((p) => rect.contains(p.offset));
  }

  @override
  bool shouldSelectAt({Offset? coordinates, EditingTool? tool}) {
    if (coordinates == null) return false;
    return points!
        .any((p) => (p.offset - coordinates).distance < (p.width ?? 5) + 8);
  }

  @override
  Rect? bounds() {
    if (points!.isEmpty) return null;
    return Rect.fromPoints(getOffset(), bottomRight);
  }

  @override
  void translate(Offset delta) {
    for (int i = 0; i < points!.length; i++) {
      final p = points![i];
      points![i] = XppStrokePoint(
          x: p.x! + delta.dx, y: p.y! + delta.dy, width: p.width);
    }
  }

  @override
  void scaleBy(double factor, Offset anchor) {
    for (int i = 0; i < points!.length; i++) {
      final p = points![i];
      points![i] = XppStrokePoint(
          x: anchor.dx + (p.x! - anchor.dx) * factor,
          y: anchor.dy + (p.y! - anchor.dy) * factor,
          width: (p.width ?? 5) * factor);
    }
  }

  XppStroke newStroke({Color? color, List<XppStrokePoint>? points});

  bool _shouldRemovePoint(
      XppStrokePoint element, Offset coordinates, double radius) {
    return ((element.x! - coordinates.dx).abs() <
            (element.width! + radius) / 2 &&
        (element.y! - coordinates.dy).abs() < (element.width! + radius) / 2);
  }

  static XppStroke byTool(
      {required XppStrokeTool tool,
      List<XppStrokePoint>? points,
      Color? color,
      bool isShape = false,
      bool smooth = false}) {
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
            editingTool: EditingTool.STYLUS);

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
            editingTool: EditingTool.WHITEOUT);

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
            editingTool: EditingTool.HIGHLIGHT);

  @override
  XppStroke newStroke({Color? color, List<XppStrokePoint>? points}) {
    return XppStrokeHighlight(points: points, color: color);
  }
}

// MANTENIAMO IL PITTORE ORIGINALE perché il "PointerListener" lo usa
// in tempo reale per disegnare il tratto che hai sotto la punta della penna!
class XppStrokePainter extends CustomPainter {
  @required
  final List<XppStrokePoint>? points;
  @required
  final Color? color;
  @required
  final Offset? topLeft;
  @required
  final bool? smoothPressure;

  // Aggiungiamo questa variabile per decidere se il tratto è finito o in corso
  final bool isComplete;

  XppStrokePainter({
    this.points,
    this.color,
    this.topLeft,
    this.smoothPressure,
    this.isComplete =
        true, // Di default è true (i tratti vecchi salvati sono completi)
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points == null || points!.isEmpty) return;

    bool isHighlighter = smoothPressure == false;

    List<pf.Point> pfPoints = points!.map((p) {
      return pf.Point(
          p.x! - topLeft!.dx,
          p.y! - topLeft!.dy,
          (smoothPressure == true && p.width != null)
              ? (p.width! / 5.0).clamp(0.1, 1.0)
              : 0.5);
    }).toList();

    final outlinePoints = pf.getStroke(
      pfPoints,
      options: pf.StrokeOptions(
        size: 5,
        thinning: isHighlighter ? 0.0 : 0.7,
        smoothing: 0.5,
        isComplete: isComplete, // <--- Usa il parametro dinamico!
        simulatePressure: isHighlighter ? false : !smoothPressure!,
      ),
    );

    if (outlinePoints.isNotEmpty) {
      final path = Path();
      path.moveTo(outlinePoints.first.dx, outlinePoints.first.dy);
      for (int i = 1; i < outlinePoints.length; i++) {
        path.lineTo(outlinePoints[i].dx, outlinePoints[i].dy);
      }
      path.close();

      final paint = Paint()
        ..color = color!
        ..style = PaintingStyle.fill;

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}

enum XppStrokeTool {
  PEN,
  HIGHLIGHTER,
  ERASER,
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
  final List<Offset> q =
      (closed && (p.first - p.last).distance < 1.0) ? p.sublist(0, n - 1) : p;
  final int m = q.length;
  Offset at(int i) => closed ? q[((i % m) + m) % m] : q[i.clamp(0, m - 1)];
  path.moveTo(q[0].dx, q[0].dy);
  final int segs = closed ? m : m - 1;
  for (int i = 0; i < segs; i++) {
    final Offset p0 = at(i - 1);
    final Offset p1 = at(i);
    final Offset p2 = at(i + 1);
    final Offset p3 = at(i + 2);
    final Offset c1 =
        Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
    final Offset c2 =
        Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  if (closed) path.close();
  return path;
}
