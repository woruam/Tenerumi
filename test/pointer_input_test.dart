import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';

void main() {
  testWidgets(
      'hardware pen routes to interacted or hovered listener and clears disposed owner',
      (tester) async {
    final firstActions = <EditingTool>[];
    final secondActions = <EditingTool>[];
    const firstKey = ValueKey('first-listener');
    const secondKey = ValueKey('second-listener');
    Widget build({bool showSecond = true}) => MaterialApp(
            home: Scaffold(
                body: Column(children: [
          PointerListener(
              key: firstKey,
              toolData: const {PointerDeviceKind.stylus: EditingTool.MOVE},
              onToolChanged: firstActions.add,
              child: const SizedBox(width: 300, height: 150)),
          if (showSecond)
            PointerListener(
                key: secondKey,
                toolData: const {PointerDeviceKind.stylus: EditingTool.MOVE},
                onToolChanged: secondActions.add,
                child: const SizedBox(width: 300, height: 150)),
        ])));
    Future<void> hardware(String method) async {
      final done = Completer<void>();
      tester.binding.channelBuffers.push(
          PointerListenerState.platform.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
          (_) => done.complete());
      await done.future;
      await tester.pump();
    }

    await tester.pumpWidget(build());
    await hardware('redmiPenPageDown');
    expect(firstActions, isEmpty);
    expect(secondActions, isEmpty);
    final first = await tester.startGesture(const Offset(30, 30),
        kind: PointerDeviceKind.stylus);
    await first.up();
    await hardware('redmiPenPageDown');
    expect(firstActions, [EditingTool.ERASER]);
    expect(secondActions, isEmpty);
    await first.moveTo(const Offset(41, 201));
    await hardware('redmiPenPageUp');
    expect(secondActions, [EditingTool.SELECT]);
    await first.removePointer();
    await tester.pumpWidget(build(showSecond: false));
    await hardware('redmiPenPageDown');
    expect(firstActions, [EditingTool.ERASER]);
    expect(secondActions, [EditingTool.SELECT]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pinch spanning pages cancels pending ink on both pages',
      (tester) async {
    final strokes = <XppContent?>[];
    final zoom = TransformationController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ZoomableWidget(
      controller: zoom,
      touchDrawingEnabled: true,
      child: Column(
          children: List.generate(
              2,
              (index) => PointerListener(
                    toolData: const {
                      PointerDeviceKind.touch: EditingTool.STYLUS
                    },
                    strokeWidth: 2,
                    color: Colors.black,
                    onNewContent: strokes.add,
                    child: const SizedBox(width: 300, height: 150),
                  ))),
    ))));
    final first = await tester.startGesture(const Offset(30, 30), pointer: 1);
    await first.moveTo(const Offset(40, 40));
    final second = await tester.startGesture(const Offset(80, 200), pointer: 2);
    await second.up();
    await first.up();
    await tester.pump();
    expect(strokes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    zoom.dispose();
  });
  for (final enabled in [false, true]) {
    testWidgets('touch drawing preference: $enabled', (tester) async {
      final strokes = <XppContent?>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PointerListener(
        toolData: {
          PointerDeviceKind.touch:
              enabled ? EditingTool.STYLUS : EditingTool.MOVE
        },
        strokeWidth: 2,
        color: Colors.black,
        onNewContent: strokes.add,
        child: const SizedBox(width: 300, height: 300),
      ))));
      final gesture = await tester.startGesture(const Offset(30, 30),
          kind: PointerDeviceKind.touch);
      await gesture.moveTo(const Offset(70, 70));
      await gesture.up();
      await tester.pump();
      expect(strokes.length, enabled ? 1 : 0);
    });
  }
  testWidgets('two fingers cancel pending ink until both lift', (tester) async {
    final strokes = <XppContent?>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PointerListener(
      toolData: const {PointerDeviceKind.touch: EditingTool.STYLUS},
      strokeWidth: 2,
      color: Colors.black,
      onNewContent: strokes.add,
      child: const SizedBox(width: 300, height: 300),
    ))));
    final first = await tester.startGesture(const Offset(30, 30), pointer: 1);
    await first.moveTo(const Offset(40, 40));
    final second = await tester.startGesture(const Offset(80, 80), pointer: 2);
    await second.up();
    await first.moveTo(const Offset(60, 60));
    await first.up();
    await tester.pump();
    expect(strokes, isEmpty);
  });
}
