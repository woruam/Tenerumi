import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';

Future<void> mount(
  WidgetTester tester,
  TransformationController transform, {
  Size scene = const Size(800, 3000),
  VoidCallback? onEndReached,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ZoomableWidget(
          controller: transform,
          sceneSize: scene,
          onEndReached: onEndReached,
          child: SizedBox(width: scene.width, height: scene.height),
        ),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    transform.dispose();
  });
}

Future<void> wheelTo(
  WidgetTester tester,
  TransformationController transform,
  double scale, {
  Offset focal = const Offset(400, 300),
}) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: focal,
      scrollDelta: Offset(
        0,
        -500 * math.log(scale / transform.value.getMaxScaleOnAxis()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'zooming out centers a narrow document even at an off-center focal point',
    (tester) async {
      final transform = TransformationController();
      await mount(tester, transform);
      await wheelTo(tester, transform, .5, focal: const Offset(120, 200));
      expect(transform.value.entry(0, 3), closeTo(200, .001));
      await wheelTo(tester, transform, .2, focal: const Offset(650, 400));
      expect(transform.value.entry(0, 3), closeTo(320, .001));
      await wheelTo(tester, transform, .1);
      expect(transform.value.entry(0, 3), closeTo(360, .001));
      expect(transform.value.entry(1, 3), closeTo(150, .001));
    },
  );

  testWidgets(
    'zooming back in from a centered overview keeps the paper centered',
    (tester) async {
      final transform = TransformationController();
      await mount(tester, transform);
      await wheelTo(tester, transform, .25);
      await wheelTo(tester, transform, .5);
      await wheelTo(tester, transform, 1);
      expect(transform.value.entry(0, 3), closeTo(0, .001));
      await wheelTo(tester, transform, 2);
      expect(transform.toScene(const Offset(400, 300)).dx, closeTo(400, .001));
      expect(transform.value.entry(0, 3), closeTo(-400, .001));
    },
  );

  testWidgets(
    'zoom keeps the touched scene point stationary away from bounds',
    (tester) async {
      final transform = TransformationController(
        Matrix4.identity()
          ..translate(-400.0, -900.0)
          ..scale(2.0),
      );
      await mount(tester, transform);
      const focal = Offset(270, 230);
      final anchor = transform.toScene(focal);
      await wheelTo(tester, transform, 3, focal: focal);
      expect((transform.toScene(focal) - anchor).distance, lessThan(.001));
      await wheelTo(tester, transform, 1.5, focal: focal);
      expect((transform.toScene(focal) - anchor).distance, lessThan(.001));
    },
  );

  testWidgets('a page smaller than the viewport is centered on both axes', (
    tester,
  ) async {
    final transform = TransformationController();
    await mount(tester, transform, scene: const Size(800, 1000));
    await wheelTo(tester, transform, .5);
    expect(transform.value.entry(0, 3), closeTo(200, .001));
    expect(transform.value.entry(1, 3), closeTo(50, .001));
    final finger = await tester.startGesture(const Offset(400, 300));
    await finger.moveBy(const Offset(35, 35));
    await finger.moveBy(const Offset(90, 90));
    await finger.up();
    expect(transform.value.entry(0, 3), closeTo(200, .001));
    expect(transform.value.entry(1, 3), closeTo(50, .001));
  });

  testWidgets(
    'horizontal pan works as soon as the document exceeds the viewport',
    (tester) async {
      final transform = TransformationController(
        Matrix4.identity()
          ..translate(-16.0, -100.0)
          ..scale(1.04),
      );
      await mount(tester, transform);
      final finger = await tester.startGesture(const Offset(400, 300));
      await finger.moveBy(const Offset(-25, 0));
      await finger.moveBy(const Offset(-10, 0));
      expect(transform.value.entry(0, 3), lessThan(-16));
      expect(transform.value.entry(0, 3), greaterThanOrEqualTo(-32.001));
      await finger.up();
    },
  );

  testWidgets(
    'reversing a pan at an edge responds without retracing the overshoot',
    (tester) async {
      final transform = TransformationController(
        Matrix4.identity()
          ..translate(-100.0, -100.0)
          ..scale(2.0),
      );
      await mount(tester, transform);
      final finger = await tester.startGesture(const Offset(300, 300));
      await finger.moveBy(const Offset(30, 0));
      await finger.moveBy(const Offset(300, 0));
      expect(transform.value.entry(0, 3), 0);
      await finger.moveBy(const Offset(-10, 0));
      expect(transform.value.entry(0, 3), closeTo(-10, .001));
      await finger.up();
    },
  );

  testWidgets(
    'pinch centers the overview and responds immediately at minimum scale',
    (tester) async {
      final transform = TransformationController();
      await mount(tester, transform);
      final left = await tester.startGesture(
        const Offset(200, 300),
        pointer: 1,
      );
      final right = await tester.startGesture(
        const Offset(600, 300),
        pointer: 2,
      );
      await left.moveTo(const Offset(230, 300));
      await right.moveTo(const Offset(570, 300));
      await left.moveTo(const Offset(380, 300));
      await right.moveTo(const Offset(420, 300));
      await left.moveTo(const Offset(390, 300));
      await right.moveTo(const Offset(410, 300));
      expect(transform.value.getMaxScaleOnAxis(), closeTo(.1, .001));
      expect(transform.value.entry(0, 3), closeTo(360, .001));
      await left.moveTo(const Offset(410, 300)); // Fingers overlap (zero span).
      expect(transform.value.getMaxScaleOnAxis(), closeTo(.1, .001));
      await left.moveTo(const Offset(390, 300));
      expect(transform.value.getMaxScaleOnAxis(), closeTo(.1, .001));
      await left.moveTo(const Offset(385, 300));
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(.1));
      final scale = transform.value.getMaxScaleOnAxis();
      expect(
        transform.value.entry(0, 3),
        closeTo((800 - 800 * scale) / 2, .001),
      );
      await left.up();
      final before = transform.value.clone();
      await right.moveBy(const Offset(0, -100));
      expect(
        transform.value,
        before,
      ); // Lifting one finger must not fling pages.
      await right.up();
    },
  );

  testWidgets('scrolling beyond the last page still requests the next page', (
    tester,
  ) async {
    final transform = TransformationController(
      Matrix4.translationValues(0, -2400, 0),
    );
    var requests = 0;
    await mount(tester, transform, onEndReached: () => requests++);
    final finger = await tester.startGesture(const Offset(400, 400));
    await finger.moveBy(const Offset(0, -35));
    await finger.moveBy(const Offset(0, -100));
    expect(transform.value.entry(1, 3), -2400);
    await finger.up();
    expect(requests, 1);
  });
}
