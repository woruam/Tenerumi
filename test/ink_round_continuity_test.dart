import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

Future<Uint8List> raster(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(240, 180);
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  testWidgets('isolated pen contact has a round cap, not a square', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await raster(
        (canvas) => XppStrokePainter(
          points: [XppStrokePoint(x: 30, y: 30, width: 5)],
          color: Colors.black,
          topLeft: Offset.zero,
          smoothPressure: true,
        ).paint(canvas, const Size(240, 180)),
      );
      int alphaAt(int x, int y) => bytes[(y * 240 + x) * 4 + 3];
      expect(alphaAt(30, 30), 255);
      expect(alphaAt(33, 30), greaterThan(0));
      expect(alphaAt(33, 33), 0);
    });
  });

  for (final highlighter in [false, true]) {
    testWidgets('round preview stays identical after release: '
        '${highlighter ? "highlighter" : "pen"}', (tester) async {
      final key = GlobalKey<PointerListenerState>();
      XppStroke? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: PointerListener(
            key: key,
            color: Colors.blue,
            strokeWidth: 4,
            toolData: {
              ui.PointerDeviceKind.stylus: highlighter
                  ? EditingTool.HIGHLIGHT
                  : EditingTool.STYLUS,
            },
            onNewContent: (content) => saved = content as XppStroke,
            child: const SizedBox(width: 240, height: 180),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        const Offset(30, 80),
        pointer: 3,
        kind: ui.PointerDeviceKind.stylus,
      );
      // Corners, crossings and abrupt pressure changes expose polygonal caps
      // and alpha accumulation that a straight constant-pressure line misses.
      final positions = [
        const Offset(60, 35),
        const Offset(95, 105),
        const Offset(130, 40),
        const Offset(170, 110),
        const Offset(85, 75),
        const Offset(195, 75),
      ];
      for (var i = 0; i < positions.length; i++) {
        await gesture.updateWithCustomEvent(
          PointerMoveEvent(
            pointer: 3,
            kind: ui.PointerDeviceKind.stylus,
            position: positions[i],
            pressure: i.isEven ? 0.2 : 0.9,
            pressureMax: 1,
          ),
        );
      }
      await tester.pump();
      final painter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;
      final liveRecorder = ui.PictureRecorder();
      painter.paint(Canvas(liveRecorder), const Size(240, 180));
      final livePicture = liveRecorder.endRecording();
      await gesture.up();
      await tester.pump();
      expect(saved, isNotNull);
      await tester.runAsync(() async {
        final live = await livePicture.toImage(240, 180);
        final liveBytes = (await live.toByteData())!.buffer.asUint8List();
        final committed = await raster((canvas) {
          final origin = saved!.getOffset();
          canvas.translate(origin.dx, origin.dy);
          saved!.paintToCanvas(canvas, const Size(240, 180));
        });
        expect(committed, orderedEquals(liveBytes));
        if (!highlighter) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawColor(Colors.white, BlendMode.src);
          canvas.drawImage(live, const Offset(0, 0), Paint());
          canvas.save();
          canvas.translate(240, 0);
          final origin = saved!.getOffset();
          canvas.translate(origin.dx, origin.dy);
          saved!.paintToCanvas(canvas, const Size(240, 180));
          canvas.restore();
          final picture = recorder.endRecording();
          final proof = await picture.toImage(480, 180);
          final png = await proof.toByteData(format: ui.ImageByteFormat.png);
          await Directory('docs/validation').create(recursive: true);
          await File(
            'docs/validation/ink-round-continuity.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          proof.dispose();
          picture.dispose();
        }
        live.dispose();
        livePicture.dispose();
      });
    });
  }

  testWidgets(
    'cached freehand path invalidates appended and replaced samples',
    (tester) async {
      final points = [
        XppStrokePoint(x: 30, y: 70, width: 1),
        XppStrokePoint(x: 100, y: 70, width: 1),
      ];
      Future<Uint8List> render() => raster(
        (canvas) => XppStrokePainter(
          points: points,
          color: Colors.black,
          topLeft: Offset.zero,
          smoothPressure: true,
        ).paint(canvas, const Size(240, 180)),
      );
      await tester.runAsync(() async {
        final original = await render();
        expect(await render(), orderedEquals(original));
        points[1] = XppStrokePoint(x: 100, y: 70, width: 5);
        final pressureEdit = await render();
        expect(pressureEdit, isNot(orderedEquals(original)));
        points.add(XppStrokePoint(x: 160, y: 120, width: 5));
        expect(await render(), isNot(orderedEquals(pressureEdit)));
      });
    },
  );
}
