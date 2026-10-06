import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/content_snapshot.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

XppStroke line({double y = 50}) => XppStrokePen(
  color: Colors.black,
  points: [
    XppStrokePoint(x: 10, y: y, width: 5),
    XppStrokePoint(x: 90, y: y, width: 5),
  ],
);

Future<FilePickerCross> unavailable(String? path) async =>
    throw StateError('$path');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a circular cut reaches between sparse samples without deleting the stroke',
    () {
      final stroke = line();
      final result = stroke.eraseWhere(
        coordinates: const Offset(50, 50),
        radius: 3,
      );
      expect(result.affected, isTrue);
      final erased = result.newContent.single as XppStroke;
      expect(erased.visibleInkPath.contains(const Offset(50, 50)), isFalse);
      expect(erased.visibleInkPath.contains(const Offset(40, 50)), isTrue);
      expect(stroke.erasures, isEmpty);
      expect(erased.points!.length, 2);
    },
  );

  test('round eraser preserves diagonal pixels outside its circle', () {
    final stroke = XppStrokePen(
      color: Colors.black,
      points: [XppStrokePoint(x: 50, y: 50, width: 5)],
    );
    final erased =
        stroke
                .eraseWhere(coordinates: const Offset(50, 50), radius: 3)
                .newContent
                .single
            as XppStroke;
    expect(erased.visibleInkPath.contains(const Offset(52.3, 52.3)), isTrue);
    expect(erased.visibleInkPath.contains(const Offset(52, 50)), isFalse);
  });

  test('swept eraser leaves no gaps between distant events', () {
    final stroke = line();
    final erased =
        stroke
                .eraseAlong(
                  previousCoordinates: const Offset(30, 50),
                  coordinates: const Offset(70, 50),
                  radius: 3,
                )
                .newContent
                .single
            as XppStroke;
    for (double x = 30; x <= 70; x += 2) {
      expect(erased.visibleInkPath.contains(Offset(x, 50)), isFalse);
    }
    expect(erased.visibleInkPath.contains(const Offset(20, 50)), isTrue);
    expect(erased.visibleInkPath.contains(const Offset(80, 50)), isTrue);
  });

  test(
    'pixel mode erases every overlapping stroke and undo/redo retains cuts',
    () {
      final file = XppFile.empty();
      file.pages!.first.layers!.first.content = [line(), line()];
      final controller = CanvasController()..file = file;
      controller.filterEraser(
        pageIndex: 0,
        coordinates: const Offset(50, 50),
        radius: 3,
      );
      expect(
        file.pages!.first.layers!.first.content!.whereType<XppStroke>().every(
          (s) => !s.visibleInkPath.contains(const Offset(50, 50)),
        ),
        isTrue,
      );
      controller.undo();
      expect(
        file.pages!.first.layers!.first.content!.whereType<XppStroke>().every(
          (s) => s.erasures.isEmpty,
        ),
        isTrue,
      );
      controller.redo();
      expect(
        file.pages!.first.layers!.first.content!.whereType<XppStroke>().every(
          (s) => s.erasures.length == 1,
        ),
        isTrue,
      );
      controller.dispose();
    },
  );

  test('eraser hits rendered width outside centerline bounding rectangle', () {
    final file = XppFile.empty();
    file.pages!.first.layers!.first.content = [line()];
    final controller = CanvasController()..file = file;
    controller.filterEraser(
      pageIndex: 0,
      coordinates: const Offset(50, 53),
      radius: .5,
    );
    final stroke = file.pages!.first.layers!.first.content!.single as XppStroke;
    expect(stroke.erasures.length, 1);
    controller.dispose();
  });

  test(
    'cuts, shape flags and transforms survive a document round trip',
    () async {
      final stroke = line()..isShape = true;
      final erased =
          stroke
                  .eraseWhere(coordinates: const Offset(50, 50), radius: 3)
                  .newContent
                  .single
              as XppStroke;
      final snapshot = cloneContent(erased) as XppStroke;
      erased.translate(const Offset(10, 20));
      erased.scaleBy(2, Offset.zero);
      expect(snapshot.erasures.single.start, const Offset(50, 50));
      expect(erased.erasures.single.start, const Offset(120, 140));
      expect(erased.erasures.single.radius, 6);
      final file = XppFile.empty();
      file.pages!.first.layers!.first.content = [erased];
      final reopened = await XppFile.fromFilePickerCross(
        FilePickerCross(await file.toUint8ListAsync(), path: 'ink.xopp'),
        null,
        unavailable,
      );
      final restored =
          reopened.pages!.first.layers!.first.content!.single as XppStroke;
      expect(restored.isShape, isTrue);
      expect(restored.erasures.single.start, const Offset(120, 140));
      expect(restored.visibleInkPath.contains(const Offset(120, 140)), isFalse);
      expect(restored.visibleInkPath.contains(const Offset(100, 140)), isTrue);
    },
  );

  test(
    'erased ink reveals the background and leaves other content intact',
    () async {
      final erased =
          line()
                  .eraseWhere(coordinates: const Offset(50, 50), radius: 4)
                  .newContent
                  .single
              as XppStroke;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.blue, BlendMode.src);
      canvas.save();
      canvas.translate(erased.getOffset().dx, erased.getOffset().dy);
      erased.paintToCanvas(canvas, const Size(100, 100));
      canvas.restore();
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      Uint8List pixel(int x, int y) =>
          bytes.sublist((y * 100 + x) * 4, (y * 100 + x) * 4 + 4);
      expect(pixel(50, 50), [0, 0, 255, 255]);
      expect(pixel(40, 50), [0, 0, 0, 255]);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('docs/validation').create(recursive: true);
      await File(
        'docs/validation/pixel-eraser.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    },
  );

  testWidgets(
    'pen eraser gesture creates one undo step, uses diameter and resets on cancel',
    (tester) async {
      final file = XppFile.empty();
      file.pages!.first.layers!.first.content = [line()];
      final controller = CanvasController()..file = file;
      const key = ValueKey('eraser-input');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Listener(
                onPointerUp: (_) => controller.eraserSnapshotTaken = false,
                onPointerCancel: (_) => controller.eraserSnapshotTaken = false,
                child: PointerListener(
                  key: key,
                  toolData: const {
                    ui.PointerDeviceKind.stylus: EditingTool.ERASER,
                  },
                  strokeWidth: 1,
                  eraserWidth: 10,
                  onEraserStart: () => controller.eraserSnapshotTaken = false,
                  filterEraser:
                      ({
                        Offset? coordinates,
                        Offset? previousCoordinates,
                        double? radius,
                      }) => controller.filterEraser(
                        pageIndex: 0,
                        coordinates: coordinates,
                        previousCoordinates: previousCoordinates,
                        radius: radius,
                      ),
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        ),
      );
      final origin = tester.getTopLeft(find.byKey(key));
      final gesture = await tester.startGesture(
        origin + const Offset(20, 50),
        kind: ui.PointerDeviceKind.stylus,
      );
      await gesture.moveTo(origin + const Offset(40, 50));
      await gesture.up();
      expect(controller.undoStack.length, 1);
      final erased =
          file.pages!.first.layers!.first.content!.single as XppStroke;
      expect(erased.erasures.every((cut) => cut.radius == 5), isTrue);
      expect(controller.eraserSnapshotTaken, isFalse);
      final second = await tester.startGesture(
        origin + const Offset(60, 50),
        kind: ui.PointerDeviceKind.stylus,
      );
      await second.moveTo(origin + const Offset(70, 50));
      await second.cancel();
      expect(controller.undoStack.length, 2);
      expect(controller.eraserSnapshotTaken, isFalse);
      controller.undo();
      final undone =
          file.pages!.first.layers!.first.content!.single as XppStroke;
      expect(undone.visibleInkPath.contains(const Offset(65, 50)), isTrue);
      expect(undone.visibleInkPath.contains(const Offset(30, 50)), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
