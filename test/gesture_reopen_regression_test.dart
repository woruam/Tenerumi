import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';
import 'package:xournalpp/widgets/infinite_canvas.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final scale in [1.0, 2.5]) {
    testWidgets(
      'double touch leaves zoom and page position unchanged at $scale',
      (tester) async {
        final transform = TransformationController(
          Matrix4.identity()
            ..translate(-80.0, -120.0)
            ..scale(scale),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ZoomableWidget(
                controller: transform,
                sceneSize: const Size(800, 3000),
                child: const SizedBox(width: 800, height: 3000),
              ),
            ),
          ),
        );
        final before = transform.value.clone();
        await tester.tapAt(const Offset(200, 200));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(const Offset(200, 200));
        await tester.pumpAndSettle();
        expect(transform.value.storage, orderedEquals(before.storage));
        // A rapid next gesture must still scroll, without a double-tap arena delay.
        final finger = await tester.startGesture(const Offset(200, 350));
        await finger.moveBy(const Offset(0, -35));
        await finger.moveBy(const Offset(0, -100));
        await finger.up();
        await tester.pumpAndSettle();
        expect(transform.value.entry(1, 3), lessThan(before.entry(1, 3)));
        expect(transform.value.getMaxScaleOnAxis(), scale);
        await tester.pumpWidget(const SizedBox());
        transform.dispose();
      },
    );
  }
  for (final infinite in [false, true]) {
    for (final keepPalm in [false, true]) {
      testWidgets(
        'finger scroll recovers after writing without hover exit: infinite=$infinite palm=$keepPalm',
        (tester) async {
          final transform = TransformationController();
          final controller = CanvasController(autosaveEnabled: false)
            ..file = XppFile.empty();
          controller.toolData[PointerDeviceKind.stylus] = EditingTool.STYLUS;
          controller.toolData[PointerDeviceKind.touch] = EditingTool.MOVE;
          controller.file!.pages!.first.infinite = infinite;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: infinite
                    ? InfiniteCanvas(canvas: controller, transform: transform)
                    : ZoomableWidget(
                        controller: transform,
                        sceneSize: const Size(800, 3000),
                        child: const SizedBox(width: 800, height: 3000),
                      ),
              ),
            ),
          );
          final pen = await tester.createGesture(
            kind: PointerDeviceKind.stylus,
            pointer: 7,
          );
          await pen.addPointer(location: const Offset(250, 200));
          await pen.moveTo(const Offset(251, 200));
          await pen.down(const Offset(251, 200));
          final palm = keepPalm
              ? await tester.startGesture(const Offset(420, 220), pointer: 8)
              : null;
          await pen.moveTo(const Offset(275, 230));
          await pen.up();
          // No removePointer/hover exit: Android can end contact without it.
          await tester.pump(const Duration(milliseconds: 350));
          final before = transform.value.clone();
          final finger = await tester.startGesture(
            const Offset(180, 400),
            pointer: 9,
          );
          await finger.moveBy(const Offset(0, -35));
          await tester.pump();
          await finger.moveBy(const Offset(0, -110));
          await tester.pump();
          expect(transform.value.entry(1, 3), lessThan(before.entry(1, 3)));
          expect(transform.value.getMaxScaleOnAxis(), 1);
          if (palm != null) {
            final scrolled = transform.value.clone();
            await palm.moveBy(const Offset(0, -100));
            await tester.pump();
            expect(transform.value.storage, orderedEquals(scrolled.storage));
            await palm.up();
          }
          await finger.up();
          await pen.removePointer();
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox());
          transform.dispose();
          controller.dispose();
        },
      );
    }
  }
  testWidgets('contact ends stale hover grant but stationary hover survives', (
    tester,
  ) async {
    final session = CanvasTouchSession();
    session.enterProximity(
      const PointerEnterEvent(kind: PointerDeviceKind.stylus, device: 3),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(session.penNear, isTrue);
    session.observePen(
      const PointerDownEvent(
        kind: PointerDeviceKind.stylus,
        device: 3,
        pointer: 4,
      ),
      [],
    );
    session.endPointer(
      const PointerUpEvent(
        kind: PointerDeviceKind.stylus,
        device: 3,
        pointer: 4,
      ),
    );
    expect(session.penNear, isTrue); // post-contact grace
    await tester.pump(const Duration(milliseconds: 350));
    expect(session.penNear, isFalse);
    session.dispose();
  });
  testWidgets(
    'touch gesture cancelled by pen cannot resume with contacts held',
    (tester) async {
      final session = CanvasTouchSession();
      session.observePen(
        const PointerDownEvent(
          kind: PointerDeviceKind.stylus,
          device: 3,
          pointer: 4,
        ),
        [1, 2],
      );
      session.endPointer(
        const PointerUpEvent(
          kind: PointerDeviceKind.stylus,
          device: 3,
          pointer: 4,
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(session.rejects(const PointerDownEvent(pointer: 9)), isTrue);
      session.endPointer(const PointerUpEvent(pointer: 1));
      expect(session.rejects(const PointerDownEvent(pointer: 9)), isTrue);
      session.endPointer(const PointerUpEvent(pointer: 2));
      expect(session.rejects(const PointerDownEvent(pointer: 9)), isFalse);
      session.dispose();
    },
  );
}
