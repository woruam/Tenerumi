import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/content_snapshot.dart';
import 'package:xournalpp/src/editing_tool.dart';

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
      expect(snapshot.points, isNot(same(stroke.points)));
      expect(snapshot.points!.first, isNot(same(stroke.points!.first)));
      stroke.translate(const Offset(12, 3));
      stroke.color = Colors.green;
      expect(snapshot.points!.first.x, -20);
      expect(snapshot.color, Colors.blue);
      expect(snapshot.isShape && snapshot.smooth, isTrue);
      expect(snapshot.erasures.single.start, const Offset(-20, 8));
    }
  });
}
