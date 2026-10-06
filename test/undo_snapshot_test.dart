import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/content_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('move and resize do not mutate undo or redo geometry', () {
    final stroke = XppStrokePen(color: Colors.black, points: [
      XppStrokePoint(x: 10, y: 20, width: 2),
      XppStrokePoint(x: 30, y: 40, width: 2),
    ])
      ..isShape = true;
    final file = XppFile.empty();
    file.pages!.first.layers!.first.content = [stroke];
    final controller = CanvasController()..file = file;
    controller.saveSnapshot(0);
    stroke.translate(const Offset(20, 10));
    stroke.scaleBy(2, Offset.zero);
    final changed = List<XppStrokePoint>.of(stroke.points!);
    controller.undo();
    final restored =
        file.pages!.first.layers!.first.content!.first as XppStroke;
    expect(restored.points!.first.offset, const Offset(10, 20));
    expect(restored.isShape, isTrue);
    controller.redo();
    final redone = file.pages!.first.layers!.first.content!.first as XppStroke;
    expect(redone.points!.first.offset, changed.first.offset);
    controller.undo();
    expect(
        (file.pages!.first.layers!.first.content!.first as XppStroke)
            .points!
            .first
            .offset,
        const Offset(10, 20));
    controller.dispose();
  });
  test('text snapshot retains location and font size after transforms', () {
    final text = XppText(offset: const Offset(5, 6), size: 12, text: 'Hello');
    final snapshot = cloneContent(text) as XppText;
    text.translate(const Offset(10, 10));
    text.scaleBy(3, Offset.zero);
    expect(snapshot.offset, const Offset(5, 6));
    expect(snapshot.size, 12);
  });
}
