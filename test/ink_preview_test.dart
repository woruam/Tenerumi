import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/widgets/PointerListener.dart';

void main() {
  testWidgets('ink burst paints without rebuilding listener or losing samples',
      (tester) async {
    final key = GlobalKey<PointerListenerState>();
    final strokes = <XppStroke>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PointerListener(
          key: key,
          strokeWidth: 2,
          color: Colors.black,
          onNewContent: (content) => strokes.add(content! as XppStroke),
          child: const SizedBox(width: 500, height: 500),
        ),
      ),
    ));
    final paintFinder = find.descendant(
        of: find.byKey(key), matching: find.byType(CustomPaint));
    final initialPainter = tester.widget<CustomPaint>(paintFinder).painter;
    final gesture = await tester.startGesture(const Offset(30, 30),
        pointer: 1, kind: PointerDeviceKind.stylus);
    // More events than frames, representative of a high sample rate pen.
    for (var frame = 0; frame < 10; frame++) {
      for (var sample = 0; sample < 40; sample++) {
        await gesture.updateWithCustomEvent(PointerMoveEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          position: Offset(31 + frame * 40 + sample.toDouble(), 40),
          pressure: sample.isEven ? 0.2 : 0.8,
          pressureMax: 1,
        ));
      }
      await tester.pump(const Duration(microseconds: 8333));
      // Reusing the delegate proves the pointer listener did not rebuild.
      expect(tester.widget<CustomPaint>(paintFinder).painter,
          same(initialPainter));
      expect(key.currentState!.points.length, 1 + (frame + 1) * 40);
    }
    await gesture.up();
    await tester.pump();
    expect(strokes, hasLength(1));
    expect(strokes.single.points, hasLength(401));
    expect(strokes.single.points![1].width,
        lessThan(strokes.single.points![2].width!));
    expect(key.currentState!.points, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel clears preview and does not commit stale ink',
      (tester) async {
    final key = GlobalKey<PointerListenerState>();
    final strokes = <XppStroke>[];
    await tester.pumpWidget(MaterialApp(
      home: PointerListener(
        key: key,
        color: Colors.black,
        onNewContent: (content) => strokes.add(content! as XppStroke),
        child: const SizedBox(width: 300, height: 300),
      ),
    ));
    final gesture = await tester.startGesture(const Offset(30, 30),
        kind: PointerDeviceKind.stylus);
    await gesture.moveTo(const Offset(50, 50));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    expect(key.currentState!.points, isEmpty);
    expect(strokes, isEmpty);
    final next = await tester.startGesture(const Offset(70, 70),
        kind: PointerDeviceKind.stylus);
    await next.up();
    await tester.pump();
    expect(strokes.single.points, hasLength(1));
    expect(strokes.single.points!.single.offset, const Offset(70, 70));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
