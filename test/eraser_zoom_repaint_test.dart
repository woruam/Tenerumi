import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

void main() {
  for (final zoom in [1.0, 2.5, 5.0]) {
    testWidgets('eraser repaints at fixed ${zoom}x before any pan or zoom', (
      tester,
    ) async {
      final file = XppFile.empty();
      final page = file.pages!.first;
      page.pageSize = XppPageSize(width: 100, height: 100);
      page.background = XppBackground.none;
      page.layers!.first.content = [
        XppStrokePen(
          color: Colors.black,
          points: [
            XppStrokePoint(x: 10, y: 50, width: 5),
            XppStrokePoint(x: 90, y: 50, width: 5),
          ],
        ),
      ];
      final controller = CanvasController(autosaveEnabled: false)..file = file;
      final pageKey = GlobalKey<XppPageStackState>();
      final viewportKey = GlobalKey();
      final inputKey = GlobalKey<PointerListenerState>();
      controller.pageStackKeys[0] = pageKey;
      // Keep the middle of the stroke visible at every tested magnification.
      // This matrix never changes during erase, repaint, or undo.
      final transform = Matrix4.translationValues(
        60 - zoom * 50,
        80 - zoom * 50,
        0,
      )..scale(zoom);
      final originalTransform = transform.clone();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: viewportKey,
                child: SizedBox(
                  width: 200,
                  height: 160,
                  child: ColoredBox(
                    color: const Color(0xff0000ff),
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Transform(
                          transform: transform,
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: 100,
                            height: 100,
                            child: PointerListener(
                              key: inputKey,
                              toolData: const {
                                ui.PointerDeviceKind.stylus: EditingTool.ERASER,
                              },
                              eraserWidth: 8,
                              onEraserStart: () =>
                                  controller.eraserSnapshotTaken = false,
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
                              child: XppPageStack(key: pageKey, page: page),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      Future<Uint8List> capture({bool proof = false}) async {
        final boundary =
            viewportKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        return (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            if (proof) {
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('docs/validation').create(recursive: true);
              await File('docs/validation/eraser-zoom-$zoom.png')
                  .writeAsBytes(png!.buffer.asUint8List());
            }
            return rgba;
          } finally {
            image.dispose();
          }
        }))!;
      }

      final viewportOrigin = tester.getTopLeft(find.byKey(viewportKey));
      Offset screenPoint(double pageX) => Offset(60 + (pageX - 50) * zoom, 80);
      List<int> pixel(Uint8List bytes, double pageX) {
        final point = screenPoint(pageX);
        final offset = (point.dy.round() * 200 + point.dx.round()) * 4;
        return bytes.sublist(offset, offset + 4);
      }

      final before = await capture();
      expect(pixel(before, 40), [0, 0, 0, 255]);
      expect(pixel(before, 60), [0, 0, 0, 255]);

      Future<void> erase(double pageX) async {
        final gesture = await tester.startGesture(
          viewportOrigin + screenPoint(pageX),
          kind: ui.PointerDeviceKind.stylus,
        );
        // Verify the committed page repaint while the eraser is still down.
        await tester.pump();
        final bytes = await capture();
        expect(pixel(bytes, pageX), [0, 0, 255, 255]);
        expect(transform, originalTransform);
        await gesture.up();
        await tester.pump();
      }

      await erase(40);
      await erase(60);
      final after = await capture(proof: true);
      expect(pixel(after, 40), [0, 0, 255, 255]);
      expect(pixel(after, 60), [0, 0, 255, 255]);
      expect(pixel(after, 50), [0, 0, 0, 255]);
      expect(controller.undoStack, hasLength(2));
      controller.undo();
      await tester.pump();
      final undo = await capture();
      expect(pixel(undo, 40), [0, 0, 255, 255]);
      expect(pixel(undo, 60), [0, 0, 0, 255]);
      expect(transform, originalTransform);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }
}
