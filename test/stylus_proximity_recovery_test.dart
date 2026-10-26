import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';
import 'package:xournalpp/widgets/infinite_canvas.dart';

class InputSpy extends CanvasController {
  InputSpy() : super(autosaveEnabled: false);
  final active = <int>{};
  @override
  void beginInput(int pointer) {
    active.add(pointer);
    super.beginInput(pointer);
  }

  @override
  void endInput(int pointer) {
    active.remove(pointer);
    super.endInput(pointer);
  }
}

Future<void> native(WidgetTester tester, String method, [Object? args]) async {
  final completed = Completer<void>();
  tester.binding.channelBuffers.push(
    PointerListenerState.platform.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (_) => completed.complete(),
  );
  await completed.future;
  await tester.pump();
}

Future<void> mount(
  WidgetTester tester,
  bool infinite,
  CanvasController canvas,
  TransformationController transform, {
  bool touchDrawing = false,
}) async {
  canvas.file = XppFile.empty();
  canvas.file!.pages!.first.infinite = infinite;
  canvas.touchDrawingEnabled = touchDrawing;
  canvas.toolData[PointerDeviceKind.stylus] = EditingTool.STYLUS;
  canvas.toolData[PointerDeviceKind.touch] = touchDrawing
      ? EditingTool.STYLUS
      : EditingTool.MOVE;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: infinite
            ? InfiniteCanvas(canvas: canvas, transform: transform)
            : ZoomableWidget(
                controller: transform,
                touchDrawingEnabled: touchDrawing,
                sceneSize: const Size(800, 3000),
                child: PointerListener(
                  toolData: canvas.toolData,
                  color: Colors.black,
                  onNewContent: (content) => canvas
                      .file!
                      .pages!
                      .first
                      .layers!
                      .first
                      .content!
                      .add(content),
                  child: const SizedBox(width: 800, height: 3000),
                ),
              ),
      ),
    ),
  );
}

Future<void> scroll(
  WidgetTester tester,
  TransformationController transform, {
  int pointer = 20,
}) async {
  final before = transform.value.entry(1, 3);
  final finger = await tester.startGesture(
    const Offset(180, 400),
    pointer: pointer,
  );
  await finger.moveBy(const Offset(0, -40));
  await tester.pump();
  await finger.moveBy(const Offset(0, -90));
  await tester.pump();
  expect(transform.value.entry(1, 3), lessThan(before));
  await finger.up();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CanvasTouchSession.nativeProximityExit(null);
  });

  for (final infinite in [false, true]) {
    testWidgets(
      'native hover exit releases touch without pen contact: infinite=$infinite',
      (tester) async {
        final canvas = CanvasController(autosaveEnabled: false);
        final transform = TransformationController();
        await mount(tester, infinite, canvas, transform);
        final pen = await tester.createGesture(
          kind: PointerDeviceKind.stylus,
          pointer: 7,
        );
        await pen.addPointer(location: const Offset(250, 200));
        await pen.moveTo(const Offset(251, 200));
        await tester.pump(const Duration(seconds: 5));
        final palm = await tester.startGesture(
          const Offset(420, 220),
          pointer: 8,
        );
        await palm.moveBy(const Offset(0, -100));
        await tester.pump();
        expect(transform.value, Matrix4.identity());
        await palm.up();
        // Android does not deliver this as a Flutter hover-exit/remove event.
        await native(tester, 'stylusProximityExit', 1000);
        await scroll(tester, transform);
        final scale = transform.value.getMaxScaleOnAxis();
        final left = await tester.startGesture(
          const Offset(200, 250),
          pointer: 21,
        );
        final right = await tester.startGesture(
          const Offset(400, 250),
          pointer: 22,
        );
        await left.moveBy(const Offset(-30, 0));
        await right.moveBy(const Offset(30, 0));
        await tester.pump();
        await left.moveBy(const Offset(-50, 0));
        await right.moveBy(const Offset(50, 0));
        await tester.pump();
        expect(transform.value.getMaxScaleOnAxis(), greaterThan(scale));
        await left.up();
        await right.up();
        expect(canvas.file!.pages!.first.layers!.first.content, isEmpty);
        await pen.removePointer();
        await tester.pumpWidget(const SizedBox());
        transform.dispose();
        canvas.dispose();
      },
    );

    testWidgets(
      'lifecycle drops missing contacts and cancels active pinch: infinite=$infinite',
      (tester) async {
        final canvas = CanvasController(autosaveEnabled: false);
        final transform = TransformationController();
        await mount(tester, infinite, canvas, transform);
        final left = await tester.startGesture(
          const Offset(200, 250),
          pointer: 30,
        );
        final right = await tester.startGesture(
          const Offset(400, 250),
          pointer: 31,
        );
        await left.moveBy(const Offset(-50, 0));
        await right.moveBy(const Offset(50, 0));
        await tester.pump();
        final before = transform.value.clone();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        // Neither old contact sends UP before the app returns.
        await left.moveBy(const Offset(-100, 0));
        await right.moveBy(const Offset(100, 0));
        await tester.pump();
        expect(transform.value.storage, orderedEquals(before.storage));
        await scroll(tester, transform, pointer: 32);
        await left.up();
        await right.up();
        expect(canvas.file!.pages!.first.layers!.first.content, isEmpty);
        await tester.pumpWidget(const SizedBox());
        transform.dispose();
        canvas.dispose();
      },
    );

    testWidgets('focus reset discards unfinished pen ink: infinite=$infinite', (
      tester,
    ) async {
      final canvas = CanvasController(autosaveEnabled: false);
      final transform = TransformationController();
      await mount(tester, infinite, canvas, transform);
      final pen = await tester.startGesture(
        const Offset(200, 200),
        pointer: 40,
        kind: PointerDeviceKind.stylus,
      );
      await pen.moveBy(const Offset(50, 0));
      await native(tester, 'stylusButtonsReset');
      await pen.up();
      expect(canvas.file!.pages!.first.layers!.first.content, isEmpty);
      await scroll(tester, transform, pointer: 41);
      await tester.pumpWidget(const SizedBox());
      transform.dispose();
      canvas.dispose();
    });
  }

  testWidgets(
    'real hover reentry renews grants while stale enter and delayed exits do not',
    (tester) async {
      final session = CanvasTouchSession();
      session.observePen(
        const PointerHoverEvent(
          kind: PointerDeviceKind.stylus,
          device: 3,
          timeStamp: Duration(microseconds: 10),
        ),
        [],
      );
      await tester.pump(const Duration(seconds: 5));
      expect(session.penNear, isTrue);
      CanvasTouchSession.nativeProximityExit(20);
      session.enterProximity(
        const PointerEnterEvent(
          kind: PointerDeviceKind.stylus,
          device: 3,
          timeStamp: Duration(microseconds: 10),
        ),
      );
      session.observePen(
        const PointerHoverEvent(
          kind: PointerDeviceKind.stylus,
          device: 3,
          timeStamp: Duration(microseconds: 10),
        ),
        [],
      );
      expect(session.penNear, isFalse);
      session.observePen(
        const PointerHoverEvent(
          kind: PointerDeviceKind.stylus,
          device: 3,
          timeStamp: Duration(microseconds: 30),
        ),
        [],
      );
      CanvasTouchSession.nativeProximityExit(
        20,
      ); // delayed method-channel delivery
      await tester.pump(const Duration(seconds: 5));
      expect(session.penNear, isTrue);
      CanvasTouchSession.nativeProximityExit(40);
      final mountedLater = CanvasTouchSession();
      mountedLater.enterProximity(
        const PointerEnterEvent(
          kind: PointerDeviceKind.stylus,
          device: 3,
          timeStamp: Duration(microseconds: 30),
        ),
      );
      expect(mountedLater.penNear, isFalse);
      session.dispose();
      mountedLater.dispose();
    },
  );

  testWidgets(
    'device removal releases a hover grant outside the canvas hit region',
    (tester) async {
      final session = CanvasTouchSession();
      session.observePen(
        const PointerHoverEvent(kind: PointerDeviceKind.stylus, device: 3),
        [],
      );
      GestureBinding.instance.pointerRouter.route(
        const PointerRemovedEvent(kind: PointerDeviceKind.stylus, device: 3),
      );
      expect(session.penNear, isFalse);
      session.dispose();
    },
  );

  testWidgets(
    'page releases autosave input leases when the app loses focus without UP',
    (tester) async {
      final canvas = InputSpy()..file = XppFile.empty();
      final transform = TransformationController();
      await tester.pumpWidget(
        MaterialApp(
          home: CanvasPage(
            controller: canvas,
            zoomController: transform,
            showInternalToolbar: false,
          ),
        ),
      );
      final finger = await tester.startGesture(
        const Offset(200, 300),
        pointer: 50,
      );
      expect(canvas.active, contains(50));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(canvas.active, isEmpty);
      await finger.up();
      await tester.pumpWidget(const SizedBox());
      transform.dispose();
      canvas.dispose();
    },
  );
}
