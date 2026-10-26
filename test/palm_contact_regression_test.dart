import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';

import 'stylus_proximity_recovery_test.dart' show mount, scroll;

Future<void> moveTouch(
  TestGesture gesture,
  int pointer,
  Offset position,
  double radius,
) => gesture.updateWithCustomEvent(
  PointerMoveEvent(
    pointer: pointer,
    kind: PointerDeviceKind.touch,
    position: position,
    radiusMajor: radius,
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CanvasTouchSession.nativeProximityExit(null);
  });

  for (final infinite in [false, true]) {
    testWidgets('growing palm stops pan until release: infinite=$infinite', (
      tester,
    ) async {
      final canvas = CanvasController(autosaveEnabled: false);
      final transform = TransformationController();
      await mount(tester, infinite, canvas, transform);
      final finger = await tester.startGesture(
        const Offset(180, 400),
        pointer: 11,
      );
      await moveTouch(finger, 11, const Offset(180, 360), 8);
      await moveTouch(finger, 11, const Offset(180, 320), 8);
      await tester.pump();
      expect(transform.value.entry(1, 3), lessThan(0));
      final before = transform.value.clone();
      await moveTouch(finger, 11, const Offset(180, 240), 40);
      await moveTouch(finger, 11, const Offset(180, 160), 5);
      await tester.pump();
      expect(transform.value.storage, orderedEquals(before.storage));
      await finger.up();
      await scroll(tester, transform, pointer: 12);
      expect(canvas.file!.pages!.first.layers!.first.content, isEmpty);
      await tester.pumpWidget(const SizedBox());
      transform.dispose();
      canvas.dispose();
    });

    testWidgets('growing palm cancels an accepted pinch: infinite=$infinite', (
      tester,
    ) async {
      final canvas = CanvasController(autosaveEnabled: false);
      final transform = TransformationController();
      await mount(tester, infinite, canvas, transform);
      final left = await tester.startGesture(
        const Offset(200, 250),
        pointer: 21,
      );
      final right = await tester.startGesture(
        const Offset(400, 250),
        pointer: 22,
      );
      await moveTouch(left, 21, const Offset(160, 250), 8);
      await moveTouch(right, 22, const Offset(440, 250), 8);
      await moveTouch(left, 21, const Offset(130, 250), 8);
      await moveTouch(right, 22, const Offset(470, 250), 8);
      await tester.pump();
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
      final before = transform.value.clone();
      await moveTouch(right, 22, const Offset(520, 250), 40);
      await moveTouch(left, 21, const Offset(90, 250), 8);
      await moveTouch(right, 22, const Offset(560, 250), 5);
      await tester.pump();
      expect(transform.value.storage, orderedEquals(before.storage));
      await right.up();
      await moveTouch(left, 21, const Offset(90, 180), 8);
      await tester.pump();
      expect(transform.value.storage, orderedEquals(before.storage));
      await left.up();
      await scroll(tester, transform, pointer: 23);
      await tester.pumpWidget(const SizedBox());
      transform.dispose();
      canvas.dispose();
    });

    testWidgets(
      'growing palm discards touch ink without affecting pen ink: infinite=$infinite',
      (tester) async {
        final canvas = CanvasController(autosaveEnabled: false);
        final transform = TransformationController();
        await mount(tester, infinite, canvas, transform, touchDrawing: true);
        final finger = await tester.startGesture(
          const Offset(100, 100),
          pointer: 31,
        );
        await moveTouch(finger, 31, const Offset(120, 110), 8);
        await moveTouch(finger, 31, const Offset(140, 120), 40);
        await moveTouch(finger, 31, const Offset(160, 130), 5);
        await finger.up();
        await tester.pump();
        final contents = canvas.file!.pages!.first.layers!.first.content!;
        expect(contents, isEmpty);

        final pen = await tester.startGesture(
          const Offset(200, 200),
          pointer: 32,
          kind: PointerDeviceKind.stylus,
        );
        final palm = await tester.startGesture(
          const Offset(400, 200),
          pointer: 33,
        );
        await moveTouch(palm, 33, const Offset(420, 210), 40);
        await moveTouch(palm, 33, const Offset(440, 220), 5);
        await pen.moveTo(const Offset(230, 220));
        await palm.up();
        await pen.up();
        await tester.pump();
        final saved = canvas.file!.pages!.first.layers!.first.content!;
        expect(saved, hasLength(1));
        expect((saved.single as XppStroke).points, hasLength(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        transform.dispose();
        canvas.dispose();
      },
    );
  }

  for (final exitKind in ['widget', 'native', 'removed']) {
    testWidgets('post-contact grace survives $exitKind exit and expires', (
      tester,
    ) async {
      final session = CanvasTouchSession();
      addTearDown(session.dispose);
      session.observePen(
        const PointerDownEvent(
          kind: PointerDeviceKind.stylus,
          device: 7,
          pointer: 1,
        ),
        [],
      );
      session.endPointer(
        const PointerUpEvent(
          kind: PointerDeviceKind.stylus,
          device: 7,
          pointer: 1,
        ),
      );
      if (exitKind == 'widget') {
        session.leaveProximity(
          const PointerExitEvent(kind: PointerDeviceKind.stylus, device: 7),
        );
      } else if (exitKind == 'native') {
        CanvasTouchSession.nativeProximityExit(1000);
      } else {
        tester.binding.pointerRouter.route(
          const PointerRemovedEvent(kind: PointerDeviceKind.stylus, device: 7),
        );
      }
      await tester.pump(const Duration(milliseconds: 50));
      expect(session.rejects(const PointerDownEvent(pointer: 2)), isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(session.rejects(const PointerDownEvent(pointer: 3)), isFalse);
    });
  }

  testWidgets('local reset does not mark another canvas pen as outside', (
    tester,
  ) async {
    final first = CanvasTouchSession();
    final second = CanvasTouchSession();
    second.observePen(
      const PointerHoverEvent(
        kind: PointerDeviceKind.stylus,
        device: 4,
        timeStamp: Duration(microseconds: 100),
      ),
      [],
    );
    first.reset();
    final newlyMounted = CanvasTouchSession();
    newlyMounted.enterProximity(
      const PointerEnterEvent(
        kind: PointerDeviceKind.stylus,
        device: 4,
        timeStamp: Duration(microseconds: 100),
      ),
    );
    expect(second.penNear, isTrue);
    expect(newlyMounted.penNear, isTrue);
    first.dispose();
    second.dispose();
    newlyMounted.dispose();
  });

  testWidgets(
    'pen samples do not allocate timers or repeatedly invalidate touch input',
    (tester) async {
      final session = CanvasTouchSession();
      addTearDown(session.dispose);
      var timers = 0, resets = 0;
      session.addListener(() => resets++);
      runZoned(
        () {
          for (var i = 0; i < 240; i++) {
            session.observePen(
              PointerHoverEvent(
                kind: PointerDeviceKind.stylus,
                device: 7,
                timeStamp: Duration(microseconds: i + 1),
              ),
              [],
            );
          }
          session.observePen(
            const PointerDownEvent(
              kind: PointerDeviceKind.stylus,
              device: 7,
              pointer: 1,
            ),
            [],
          );
          for (var i = 0; i < 240; i++) {
            session.observePen(
              const PointerMoveEvent(
                kind: PointerDeviceKind.stylus,
                device: 7,
                pointer: 1,
              ),
              [],
            );
          }
          expect(session.cancellationEpoch, 0);
          expect(timers, 0);
          session.observePen(
            const PointerMoveEvent(
              kind: PointerDeviceKind.stylus,
              device: 7,
              pointer: 1,
            ),
            [8, 9],
          );
          final epoch = session.cancellationEpoch;
          session.observePen(
            const PointerMoveEvent(
              kind: PointerDeviceKind.stylus,
              device: 7,
              pointer: 1,
            ),
            [],
          );
          expect(session.cancellationEpoch, epoch);
          session.endPointer(
            const PointerUpEvent(
              kind: PointerDeviceKind.stylus,
              device: 7,
              pointer: 1,
            ),
          );
          expect(timers, 1);
          expect(resets, 0);
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            timers++;
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(session.penNear, isFalse);
    },
  );
}
