import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/content_snapshot.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/src/ink_geometry.dart';

class _CountedPoints extends ListBase<XppStrokePoint> {
  final List<XppStrokePoint> values;
  int reads = 0;
  _CountedPoints(this.values);
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('Fixed test list');
  @override
  XppStrokePoint operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, XppStrokePoint value) => values[index] = value;
}

// Frozen pre-refactor oracle: independent scans for extrema and maximum radius.
Rect _previousBounds(XppStroke stroke) {
  final points = stroke.points!;
  var minX = points.first.x!, minY = points.first.y!;
  var maxX = minX, maxY = minY;
  for (final p in points) {
    if (p.x! < minX) minX = p.x!;
  }
  for (final p in points) {
    if (p.y! < minY) minY = p.y!;
  }
  for (final p in points) {
    if (p.x! > maxX) maxX = p.x!;
  }
  for (final p in points) {
    if (p.y! > maxY) maxY = p.y!;
  }
  double radius = 0;
  for (final p in points) {
    final value = stroke.isShape
        ? (p.width ?? 2.5).clamp(1.0, double.infinity) / 2
        : inkRadius(
            p.width,
            pressureSensitive: stroke.tool == XppStrokeTool.PEN,
          );
    if (value > radius) radius = value;
  }
  return Rect.fromPoints(
    Offset(minX, minY),
    Offset(maxX, maxY),
  ).inflate(radius);
}

void main() {
  test('stroke subclasses retain mutable state and independent snapshots', () {
    for (final tool in XppStrokeTool.values) {
      final stroke = XppStroke.byTool(
        tool: tool,
        color: Colors.red,
        points: [XppStrokePoint(x: 2, y: -4, width: 3)],
      );
      // Preserve the observable constructor default before property unification.
      expect(stroke.editingTool, isNull);
      stroke.editingTool = EditingTool.SELECT;
      stroke.color = Colors.blue;
      stroke.points = [XppStrokePoint(x: -20, y: 8, width: 1)];
      stroke.isShape = true;
      stroke.smooth = true;
      stroke.erasures = [
        const StrokeErasure(Offset(-20, 8), Offset(-18, 8), 2),
      ];
      final snapshot = cloneContent(stroke) as XppStroke;
      expect(snapshot.runtimeType, stroke.runtimeType);
      expect(snapshot.tool, tool);
      expect(snapshot.editingTool, EditingTool.SELECT);
      expect(
        snapshot.toXmlElement().toXmlString(),
        stroke.toXmlElement().toXmlString(),
      );
      expect(snapshot.points, same(stroke.points));
      expect(snapshot.points!.first, same(stroke.points!.first));
      stroke.translate(const Offset(12, 3));
      stroke.color = Colors.green;
      expect(snapshot.points!.first.x, -20);
      expect(snapshot.color, Colors.blue);
      expect(snapshot.isShape && snapshot.smooth, isTrue);
      expect(snapshot.erasures.single.start, const Offset(-20, 8));
    }
  });

  test(
    'single pass bounds match legacy geometry for all tools and mutations',
    () {
      final random = math.Random(819);
      for (final tool in XppStrokeTool.values) {
        for (final shape in [false, true]) {
          for (var trial = 0; trial < 60; trial++) {
            final stroke = XppStroke.byTool(
              tool: tool,
              isShape: shape,
              points: List.generate(
                1 + random.nextInt(100),
                (index) => XppStrokePoint(
                  x: random.nextDouble() * 2000 - 1000,
                  y: random.nextDouble() * 2000 - 1000,
                  width: index % 5 == 0 ? null : random.nextDouble() * 20 - 2,
                ),
              ),
            );
            void check() {
              final expected = _previousBounds(stroke);
              expect(stroke.bounds(), expected);
              final positions = stroke.points!.map((p) => p.offset);
              expect(
                stroke.getOffset(),
                Offset(
                  positions.map((p) => p.dx).reduce(math.min),
                  positions.map((p) => p.dy).reduce(math.min),
                ),
              );
              expect(
                stroke.bottomRight,
                Offset(
                  positions.map((p) => p.dx).reduce(math.max),
                  positions.map((p) => p.dy).reduce(math.max),
                ),
              );
            }

            check();
            stroke.translate(const Offset(30, -12));
            check();
            stroke.scaleBy(2.5, const Offset(-40, 80));
            check();
            // Geometry edits replace the immutable buffer.
            final updated = List<XppStrokePoint>.of(stroke.points!);
            updated[0] = XppStrokePoint(
              x: -9000,
              y: stroke.points!.first.y,
              width: 22,
            );
            stroke.points = updated;
            check();
            stroke.points = [
              ...stroke.points!,
              XppStrokePoint(x: 15000, y: -20000, width: .1),
            ];
            check();
          }
        }
      }
      for (final points in [null, <XppStrokePoint>[]]) {
        final empty = XppStrokePen(points: points);
        expect(empty.bounds(), isNull);
        expect(empty.getOffset(), Offset.zero);
        expect(empty.bottomRight, Offset.zero);
      }
    },
  );

  test('curved shape bounds preserve curve overshoot and stroke inflation', () {
    final shape =
        XppStrokePen(
            points: [
              XppStrokePoint(x: 0, y: 0, width: 4),
              XppStrokePoint(x: 90, y: 0, width: 4),
              XppStrokePoint(x: 90, y: 60, width: 4),
              XppStrokePoint(x: 0, y: 60, width: 4),
              XppStrokePoint(x: 0, y: 0, width: 4),
            ],
          )
          ..isShape = true
          ..smooth = true;
    final before = shape.bounds()!;
    expect(before.left, lessThan(-2));
    expect(before.right, greaterThan(92));
    shape.translate(const Offset(37, -19));
    final translated = shape.bounds()!;
    expect(translated.left, closeTo(before.left + 37, 0.0001));
    expect(translated.bottom, closeTo(before.bottom - 19, 0.0001));
  });

  test('geometry owns its immutable buffer and visits each sample once', () {
    final points = _CountedPoints(
      List.generate(
        10000,
        (i) => XppStrokePoint(x: i.toDouble(), y: -i.toDouble(), width: 2),
      ),
    );
    final stroke = XppStrokePen(points: points);
    expect(points.reads, lessThanOrEqualTo(10001));
    expect(stroke.bounds(), _previousBounds(stroke));
    expect(
      () => stroke.points!.add(XppStrokePoint(x: 0, y: 0, width: 2)),
      throwsUnsupportedError,
    );
    points[0] = XppStrokePoint(x: 9000, y: 9000, width: 2);
    expect(stroke.points!.first.x, 0);
  });
}
