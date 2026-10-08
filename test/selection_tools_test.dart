import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/selection_clipboard.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

const inputKey = ValueKey('selection-input');

XppStroke stroke({Offset offset = const Offset(60, 95)}) => XppStrokePen(
  color: Colors.black,
  points: [
    for (final x in [0.0, 20.0, 40.0])
      XppStrokePoint(x: offset.dx + x, y: offset.dy, width: 2),
  ],
);

CanvasController controller({
  SelectionClipboard? clipboard,
  bool empty = false,
}) {
  final file = XppFile.empty();
  file.pages!.first.pageSize = XppPageSize(width: 300, height: 260);
  file.pages!.first.layers!.first.content = empty ? [] : [stroke()];
  return CanvasController(autosaveEnabled: false, clipboard: clipboard)
    ..file = file;
}

Future<void> mount(
  WidgetTester tester,
  CanvasController ctrl, {
  EditingTool tool = EditingTool.SELECT,
  double scale = 1,
}) async {
  ctrl.setTool(tool);
  final pageKey = GlobalKey<XppPageStackState>();
  ctrl.pageStackKeys[0] = pageKey;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300 * scale,
            height: 260 * scale,
            child: FittedBox(
              alignment: Alignment.topLeft,
              child: AnimatedBuilder(
                animation: ctrl,
                builder: (context, _) => RawGestureDetector(
                  gestures: {
                    StylusGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          StylusGestureRecognizer
                        >(
                          () => StylusGestureRecognizer(blockStylusPan: true),
                          (recognizer) => recognizer.blockStylusPan = true,
                        ),
                  },
                  child: PointerListener(
                    key: inputKey,
                    toolData: ctrl.toolData,
                    strokeWidth: ctrl.getCurrentToolWidth(),
                    highlighterWidth: ctrl.highlighterWidth,
                    highlighterColor: ctrl.highlighterColor,
                    color: ctrl.getCurrentToolColor(),
                    clipboard: ctrl.clipboard,
                    getPageContent: () =>
                        ctrl.file!.pages!.first.layers!.first.content ?? [],
                    onNewContent: (content) => ctrl.addNewContent(0, content),
                    onDeleteContent: (content) =>
                        ctrl.deleteContent(0, content),
                    onBeforeContentChanged: () => ctrl.saveSnapshot(0),
                    onContentChanged: () => ctrl.markContentChanged(0),
                    onPasteContent: (position) =>
                        ctrl.pasteSelection(0, position),
                    child: SizedBox(
                      width: 300,
                      height: 260,
                      child: XppPageStack(
                        key: pageKey,
                        page: ctrl.file!.pages!.first,
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
}

Offset screen(WidgetTester tester, Offset local) =>
    (tester.renderObject(find.byKey(inputKey)) as RenderBox).localToGlobal(
      local,
    );

Future<void> penTap(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    kind: ui.PointerDeviceKind.stylus,
  );
  await gesture.up();
  await tester.pump();
}

Future<void> lasso(
  WidgetTester tester, {
  Rect region = const Rect.fromLTRB(40, 70, 125, 125),
}) async {
  final gesture = await tester.startGesture(
    screen(tester, region.topLeft),
    kind: ui.PointerDeviceKind.stylus,
  );
  for (final point in [
    region.topRight,
    region.bottomRight,
    region.bottomLeft,
    region.topLeft,
  ]) {
    await gesture.moveTo(screen(tester, point));
  }
  await gesture.up();
  await tester.pump();
  expect(find.byKey(const ValueKey('selection-done')), findsOneWidget);
}

List<XppContent?> contents(CanvasController ctrl) =>
    ctrl.file!.pages!.first.layers!.first.content!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('highlighter width changes committed ink and ignores pressure', (
    tester,
  ) async {
    final ctrl = controller(empty: true);
    addTearDown(ctrl.dispose);
    await mount(tester, ctrl, tool: EditingTool.HIGHLIGHT);
    for (final width in [8.0, 24.0]) {
      ctrl.setHighlighterProps(null, width);
      await tester.pump();
      final start = screen(tester, const Offset(30, 100));
      final gesture = await tester.startGesture(
        start,
        pointer: 700,
        kind: ui.PointerDeviceKind.stylus,
      );
      await tester.sendEventToBinding(
        PointerMoveEvent(
          pointer: 700,
          kind: ui.PointerDeviceKind.stylus,
          position: screen(tester, const Offset(120, 100)),
          pressure: .1,
          pressureMax: 1,
        ),
      );
      await tester.sendEventToBinding(
        PointerMoveEvent(
          pointer: 700,
          kind: ui.PointerDeviceKind.stylus,
          position: screen(tester, const Offset(160, 100)),
          pressure: .9,
          pressureMax: 1,
        ),
      );
      await gesture.up();
      await tester.pump();
      final saved = contents(ctrl).last! as XppStroke;
      expect(saved.tool, XppStrokeTool.HIGHLIGHTER);
      expect(saved.points!.map((p) => p.width), everyElement(width));
      expect(saved.inkPath.getBounds().height, closeTo(width, .01));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final origin = saved.getOffset();
      canvas.translate(origin.dx, origin.dy);
      saved.paintToCanvas(canvas, const Size(300, 260));
      final picture = recorder.endRecording();
      await tester.runAsync(() async {
        final image = await picture.toImage(300, 260);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final coveredRows = [
          for (var y = 0; y < 260; y++)
            if (bytes[(y * 300 + 100) * 4 + 3] > 0) y,
        ];
        expect(coveredRows.length, width.toInt());
        image.dispose();
      });
      picture.dispose();
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'stylus can finish and delete a lasso under the pan interceptor',
    (tester) async {
      final ctrl = controller();
      addTearDown(ctrl.dispose);
      await mount(tester, ctrl);
      await lasso(tester);
      await penTap(tester, find.byKey(const ValueKey('selection-done')));
      expect(find.byKey(const ValueKey('selection-done')), findsNothing);
      expect(contents(ctrl).length, 1);
      expect(ctrl.undoStack, isEmpty);
      await lasso(tester);
      await penTap(tester, find.byKey(const ValueKey('selection-delete')));
      expect(contents(ctrl), isEmpty);
      expect(ctrl.hasUnsavedChanges, isTrue);
      expect(ctrl.undoStack.length, 1);
      ctrl.undo();
      await tester.pump();
      expect(contents(ctrl).length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final scale in [1.0, 2.5]) {
    testWidgets(
      'move selected ink at zoom $scale is visible and one undo step',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final ctrl = controller();
        addTearDown(ctrl.dispose);
        await mount(tester, ctrl, scale: scale);
        await lasso(tester);
        await penTap(tester, find.byKey(const ValueKey('selection-move')));
        final gesture = await tester.startGesture(
          screen(tester, const Offset(160, 160)),
          kind: ui.PointerDeviceKind.stylus,
        );
        for (final point in [const Offset(175, 170), const Offset(190, 180)]) {
          await gesture.moveTo(screen(tester, point));
          await tester.pump();
        }
        await gesture.up();
        await tester.pump();
        expect(
          (contents(ctrl).single as XppStroke).points!.first.offset,
          const Offset(90, 115),
        );
        expect(ctrl.undoStack.length, 1);
        ctrl.undo();
        await tester.pump();
        expect(
          (contents(ctrl).single as XppStroke).points!.first.offset,
          const Offset(60, 95),
        );
        expect(find.byKey(const ValueKey('selection-done')), findsNothing);
        ctrl.redo();
        expect(
          (contents(ctrl).single as XppStroke).points!.first.offset,
          const Offset(90, 115),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final scale in [1.0, 2.5]) {
    testWidgets(
      'copy and stylus paste at zoom $scale without committing a dot',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final ctrl = controller();
        addTearDown(ctrl.dispose);
        await mount(tester, ctrl, scale: scale);
        await lasso(tester);
        await penTap(tester, find.byKey(const ValueKey('selection-copy')));
        expect(ctrl.clipboard.hasContent, isTrue);
        expect(ctrl.undoStack, isEmpty);
        await penTap(tester, find.byKey(const ValueKey('selection-done')));
        ctrl.setTool(EditingTool.STYLUS);
        await tester.pump();
        final gesture = await tester.startGesture(
          screen(tester, const Offset(150, 170)),
          kind: ui.PointerDeviceKind.stylus,
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Incolla'), findsNothing);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Incolla'), findsOneWidget);
        await gesture.up();
        await tester.pump();
        expect(contents(ctrl).length, 1);
        await penTap(tester, find.byKey(const ValueKey('selection-paste')));
        expect(contents(ctrl).length, 2);
        expect(ctrl.undoStack.length, 1);
        expect(find.text('Incolla'), findsNothing);
        final original = contents(ctrl).first as XppStroke;
        final pasted = contents(ctrl).last as XppStroke;
        expect(pasted.bounds()!.topLeft, const Offset(150, 170));
        expect(identical(original.points, pasted.points), isFalse);
        ctrl.undo();
        await tester.pump();
        expect(contents(ctrl).length, 1);
        ctrl.redo();
        await tester.pump();
        expect(contents(ctrl).length, 2);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('paste in navigation mode can move without drawing extra ink', (
    tester,
  ) async {
    final ctrl = controller();
    addTearDown(ctrl.dispose);
    ctrl.clipboard.copy([contents(ctrl).single!]);
    await mount(tester, ctrl, tool: EditingTool.MOVE);
    final pan = await tester.startGesture(
      screen(tester, const Offset(30, 180)),
      kind: ui.PointerDeviceKind.stylus,
    );
    await pan.moveTo(screen(tester, const Offset(60, 180)));
    await pan.up();
    await tester.pump();
    expect(contents(ctrl).length, 1);
    expect(ctrl.undoStack, isEmpty);
    final hold = await tester.startGesture(
      screen(tester, const Offset(150, 170)),
      kind: ui.PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await hold.up();
    await tester.pump();
    await penTap(tester, find.byKey(const ValueKey('selection-paste')));
    final move = await tester.startGesture(
      screen(tester, const Offset(100, 200)),
      kind: ui.PointerDeviceKind.stylus,
    );
    await move.moveTo(screen(tester, const Offset(120, 210)));
    await move.up();
    await tester.pump();
    expect(contents(ctrl).length, 2);
    expect(
      (contents(ctrl).last as XppStroke).bounds()!.topLeft,
      const Offset(170, 180),
    );
    expect(ctrl.undoStack.length, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'moving pen cancels paste hold; hold without a copy draws normally',
    (tester) async {
      final ctrl = controller(empty: true);
      addTearDown(ctrl.dispose);
      await mount(tester, ctrl, tool: EditingTool.STYLUS);
      final first = await tester.startGesture(
        screen(tester, const Offset(20, 140)),
        kind: ui.PointerDeviceKind.stylus,
      );
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Incolla'), findsNothing);
      await first.up();
      await tester.pump();
      expect(contents(ctrl).length, 1);
      ctrl.clipboard.copy([contents(ctrl).first!]);
      final gesture = await tester.startGesture(
        screen(tester, const Offset(30, 180)),
        kind: ui.PointerDeviceKind.stylus,
      );
      await gesture.moveTo(screen(tester, const Offset(70, 180)));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Incolla'), findsNothing);
      await gesture.up();
      expect(contents(ctrl).length, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'clipboard snapshots mixed content and repeated pastes across documents',
    () {
      final clipboard = SelectionClipboard();
      final source = controller(clipboard: clipboard);
      final target = controller(clipboard: clipboard, empty: true);
      final ink = contents(source).first as XppStroke;
      final text = XppText(
        text: 'Testo',
        offset: const Offset(70, 110),
        size: 12,
      );
      clipboard.copy([ink, text]);
      ink.translate(const Offset(400, 400));
      text.translate(const Offset(400, 400));
      final first = target.pasteSelection(0, const Offset(10, 20));
      final firstInk = first.first as XppStroke;
      final firstPosition = firstInk.points!.first.offset;
      final second = target.pasteSelection(0, const Offset(10, 20));
      firstInk.translate(const Offset(100, 100));
      expect((second.first as XppStroke).points!.first.offset, firstPosition);
      expect((second.last as XppText).text, 'Testo');
      expect((second.last as XppText).offset!.dx, lessThan(100));
      expect(target.undoStack.length, 2);
      target.undo();
      expect(contents(target).length, 2);
      target.undo();
      expect(contents(target), isEmpty);
      source.dispose();
      target.dispose();
    },
  );
}
