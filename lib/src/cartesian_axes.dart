import 'dart:math' as math;
import 'dart:ui';

/// Unlabelled axes fitted to the dragged rectangle, shared by preview/export.
List<List<Offset>> cartesianAxes(Offset start, Offset end) {
  final box = Rect.fromPoints(start, end);
  if (box.width < 1 || box.height < 1) return const [];
  final c = box.center;
  final arrow = math.min(10.0, math.min(box.width, box.height) / 8);
  return [
    [Offset(box.left, c.dy), Offset(box.right, c.dy)],
    [Offset(c.dx, box.bottom), Offset(c.dx, box.top)],
    [
      Offset(box.right - arrow, c.dy - arrow / 2),
      Offset(box.right, c.dy),
      Offset(box.right - arrow, c.dy + arrow / 2),
    ],
    [
      Offset(c.dx - arrow / 2, box.top + arrow),
      Offset(c.dx, box.top),
      Offset(c.dx + arrow / 2, box.top + arrow),
    ],
  ];
}
