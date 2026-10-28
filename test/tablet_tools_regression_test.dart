import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:xournalpp/controllers/workspace_controller.dart';
import 'package:xournalpp/widgets/split_screen_view.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/cartesian_axes.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/src/ink_geometry.dart';
import 'package:xournalpp/src/stylus_shortcut.dart';
import 'package:xournalpp/widgets/delete_page_dialog.dart';
import 'package:xournalpp/widgets/ink_options_panel.dart';
import 'package:xournalpp/widgets/page_scrollbar.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/stylus_menu_settings.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';

XppStroke ink({double y = 40}) => XppStroke.byTool(
  tool: XppStrokeTool.PEN,
  color: Colors.black,
  widthIsDiameter: true,
  points: [
    XppStrokePoint(x: 30, y: y, width: 2.5),
    XppStrokePoint(x: 80, y: y, width: 2.5),
  ],
);

CanvasController controller() =>
    CanvasController(autosaveEnabled: false)..init(XppFile.empty());

Future<void> penStroke(WidgetTester tester) async {
  await tester.sendEventToBinding(
    const PointerDownEvent(
      pointer: 71,
      kind: PointerDeviceKind.stylus,
      position: Offset(30, 40),
      pressure: 0,
    ),
  );
  await tester.sendEventToBinding(
    const PointerMoveEvent(
      pointer: 71,
      kind: PointerDeviceKind.stylus,
      position: Offset(180, 160),
      pressure: 1,
    ),
  );
  await tester.sendEventToBinding(
    const PointerUpEvent(
      pointer: 71,
      kind: PointerDeviceKind.stylus,
      position: Offset(180, 160),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'deleting a middle PDF page shifts layer selection and undo safely',
    (tester) async {
      final ctrl = controller();
      ctrl.addPage();
      ctrl.addPage();
      await tester.pump();
      final pages = ctrl.file!.pages!;
      final first = pages.first, last = pages.last;
      last.background = XppBackgroundPdf(
        filename: 'embedded.pdf',
        page: 9,
        onUnavailable: (_) async =>
            throw StateError('PDF not rendered in this test'),
      );
      ctrl.saveSnapshot(2);
      ctrl.addNewContent(2, ink());
      ctrl.goToPage(1);
      expect(ctrl.deletePage(1), isTrue);
      expect(ctrl.file!.pages, [first, last]);
      expect((last.background as XppBackgroundPdf).page, 9);
      expect(ctrl.activePageIndex, 1);
      ctrl.undo();
      expect(ctrl.activeLayer(1).content, isEmpty);
      expect(ctrl.hasUnsavedChanges, isTrue);
      expect(ctrl.deletePage(1), isTrue);
      expect(ctrl.deletePage(0), isFalse);
      await tester.pump();
      ctrl.dispose();
    },
  );

  testWidgets(
    'annotated hidden pages require confirmation; cancel preserves everything',
    (tester) async {
      final ctrl = controller();
      ctrl.addPage();
      ctrl.file!.pages!.last.layers!.add(
        XppLayer(visible: false, locked: true, content: [ink()]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => requestDeleteCurrentPage(context, ctrl),
              child: const Text('Delete'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Eliminare la pagina?'), findsOneWidget);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(ctrl.file!.pages!.length, 2);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-delete-page')));
      await tester.pumpAndSettle();
      expect(ctrl.file!.pages!.length, 1);
      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
    },
  );

  testWidgets('unannotated PDF page deletes without confirmation', (
    tester,
  ) async {
    final ctrl = controller();
    ctrl.addPage();
    ctrl.file!.pages!.last.background = XppBackgroundPdf(
      filename: 'test.pdf',
      page: 2,
      onUnavailable: (_) async =>
          throw StateError('PDF not rendered in this test'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => requestDeleteCurrentPage(context, ctrl),
            child: const Text('Delete'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(ctrl.file!.pages!.length, 1);
    await tester.pumpWidget(const SizedBox());
    ctrl.dispose();
  });

  for (final pressure in [false, true]) {
    testWidgets('pressure setting changes only new pen ink: $pressure', (
      tester,
    ) async {
      XppStroke? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: PointerListener(
            color: Colors.black,
            strokeWidth: 2.5,
            penPressureEnabled: pressure,
            toolData: const {PointerDeviceKind.stylus: EditingTool.STYLUS},
            onNewContent: (value) => saved = value as XppStroke,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await penStroke(tester);
      expect(saved!.widthIsDiameter, isTrue);
      final widths = saved!.points!.map((p) => p.width).toSet();
      if (pressure) {
        expect(widths.length, greaterThan(1));
      } else {
        expect(widths, {2.5});
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('pressure toggle has a grey panel and survives reopening', (
    tester,
  ) async {
    final ctrl = controller();
    final anchor = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: anchor,
              child: const Text('Penna'),
              onPressed: () => showInkOptionsPanel(
                context,
                ctrl,
                anchor,
                'Penna',
                const [Colors.black, Colors.white],
                ctrl.penColor,
                ctrl.penWidth,
                ctrl.setPenProps,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Penna'));
    await tester.pumpAndSettle();
    final material = tester.widget<Material>(
      find.byKey(const ValueKey('ink-options-panel')),
    );
    expect(material.color, const Color(0xFF424242));
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pen-pressure-toggle')));
    await tester.pumpAndSettle();
    expect(ctrl.penPressureEnabled, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        CanvasController.penPressurePreference,
      ),
      isFalse,
    );
    final restored = controller();
    await tester.pumpAndSettle();
    expect(restored.penPressureEnabled, isFalse);
    await tester.pumpWidget(const SizedBox());
    ctrl.dispose();
    restored.dispose();
  });

  testWidgets('axes commit the same unlabelled segments shown by the preview', (
    tester,
  ) async {
    final strokes = <XppStroke>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PointerListener(
          color: Colors.blue,
          strokeWidth: 2.5,
          toolData: const {PointerDeviceKind.stylus: EditingTool.SHAPE_AXES},
          onNewContent: (value) => strokes.add(value as XppStroke),
          child: const SizedBox.expand(),
        ),
      ),
    );
    await penStroke(tester);
    final geometry = cartesianAxes(
      const Offset(30, 40),
      const Offset(180, 160),
    );
    expect(strokes.length, 4);
    for (var i = 0; i < strokes.length; i++) {
      expect(strokes[i].isShape, isTrue);
      expect(strokes[i].points!.map((p) => p.offset), geometry[i]);
    }
    final file = XppFile.empty();
    file.pages!.first.layers!.first.content!.addAll(strokes);
    expect(file.toXmlString(), isNot(contains('<text')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'radial menu opens without clipboard, does not commit the held dot, selects a preset',
    (tester) async {
      final emitted = <XppContent?>[];
      StylusShortcut? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: PointerListener(
            strokeWidth: 2.5,
            color: Colors.black,
            toolData: const {PointerDeviceKind.stylus: EditingTool.STYLUS},
            stylusShortcuts: StylusShortcut.defaults,
            onStylusShortcut: (value) => selected = value,
            onNewContent: emitted.add,
            child: const SizedBox.expand(),
          ),
        ),
      );
      final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await pen.down(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stylus-radial-menu')), findsOneWidget);
      await pen.moveTo(
        tester.getCenter(find.byKey(const ValueKey('radial-slot-2'))),
      );
      await tester.pump();
      expect(selected, isNull);
      await pen.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stylus-radial-menu')), findsNothing);
      expect(selected!.tool, EditingTool.HIGHLIGHT);
      expect(emitted, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('radial presets persist tool, exact color and width', (
    tester,
  ) async {
    final ctrl = controller();
    await tester.pump();
    final presets = List<StylusShortcut>.of(StylusShortcut.defaults);
    presets[0] = const StylusShortcut(EditingTool.HIGHLIGHT, Colors.purple, 17);
    await ctrl.setStylusShortcuts(presets);
    final restored = controller();
    await tester.pumpAndSettle();
    final value = restored.stylusShortcuts.first;
    expect(value.tool, EditingTool.HIGHLIGHT);
    expect(value.color.toARGB32(), Colors.purple.toARGB32());
    expect(value.width, 17);
    restored.applyStylusShortcut(value);
    expect(restored.getCurrentToolWidth(), 17);
    expect(restored.getCurrentToolColor().toARGB32(), Colors.purple.toARGB32());
    final prefs = await SharedPreferences.getInstance();
    expect(
      (jsonDecode(
        prefs.getString(StylusShortcut.preferenceKey)!,
      ) as List).length,
      5,
    );
    ctrl.dispose();
    restored.dispose();
  });

  testWidgets('radial settings allow editing and saving all five slots', (
    tester,
  ) async {
    List<StylusShortcut>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            child: const Text('Settings'),
            onPressed: () async => result = await showStylusShortcutSettings(
              context,
              StylusShortcut.defaults,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-radial-slot-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<EditingTool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gomma').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(result!.length, 5);
    expect(result!.first.tool, EditingTool.ERASER);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'scrollbar rejects pen-adjacent palms across split panels and recovers',
    (tester) async {
      final transform = TransformationController();
      final otherCanvas = CanvasTouchSession();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: PageScrollbar(
                transform: transform,
                viewport: const Size(800, 600),
                sceneHeight: 3000,
                currentPage: 0,
                pageCount: 3,
              ),
            ),
          ),
        ),
      );
      otherCanvas.observePen(
        const PointerDownEvent(
          pointer: 92,
          device: 5,
          kind: PointerDeviceKind.stylus,
        ),
        {},
      );
      final before = transform.value.clone();
      final palm = await tester.startGesture(const Offset(780, 400));
      await palm.moveBy(const Offset(0, -100));
      await palm.up();
      expect(transform.value, before);
      otherCanvas.endPointer(
        const PointerUpEvent(
          pointer: 92,
          device: 5,
          kind: PointerDeviceKind.stylus,
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      final finger = await tester.startGesture(const Offset(780, 400));
      await finger.up();
      expect(transform.value.entry(1, 3), lessThan(0));
      expect(transform.value.getMaxScaleOnAxis(), 1);
      await tester.pumpWidget(const SizedBox());
      otherCanvas.dispose();
      transform.dispose();
    },
  );

  test('duplicate stationary samples do not grow geometry; pressure changes still do', () {
    final geometry = InkGeometry();
    geometry.append(const Offset(20, 20), 2, pressureSensitive: false);
    final contours = geometry.path.computeMetrics().length;
    for (var i = 0; i < 1000; i++) {
      geometry.append(const Offset(20, 20), 2, pressureSensitive: false);
    }
    expect(geometry.path.computeMetrics().length, contours);
    geometry.append(const Offset(20, 20), 4, pressureSensitive: false);
    expect(geometry.path.getBounds().width, 4);
  });

  testWidgets('large palm and second contact cannot manipulate the scrollbar', (
    tester,
  ) async {
    final transform = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: PageScrollbar(
              transform: transform,
              viewport: const Size(800, 600),
              sceneHeight: 3000,
              currentPage: 0,
              pageCount: 3,
            ),
          ),
        ),
      ),
    );
    final before = transform.value.clone();
    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 1,
        position: Offset(780, 400),
        radiusMajor: 40,
      ),
    );
    await tester.sendEventToBinding(
      const PointerMoveEvent(
        pointer: 1,
        position: Offset(780, 200),
        radiusMajor: 1,
      ),
    );
    await tester.sendEventToBinding(
      const PointerUpEvent(pointer: 1, position: Offset(780, 200)),
    );
    expect(transform.value, before);
    final first = await tester.startGesture(const Offset(780, 200), pointer: 2);
    final position = transform.value.clone();
    final second = await tester.startGesture(
      const Offset(780, 400),
      pointer: 3,
    );
    await first.moveBy(const Offset(0, 70));
    await second.moveBy(const Offset(0, -70));
    expect(transform.value, position);
    await first.up();
    await second.up();
    await tester.pumpWidget(const SizedBox());
    transform.dispose();
  });

  testWidgets(
    'a scrollbar drag stays cancelled after the pen arrives and leaves',
    (tester) async {
      final transform = TransformationController();
      final other = CanvasTouchSession();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: PageScrollbar(
                transform: transform,
                viewport: const Size(800, 600),
                sceneHeight: 3000,
                currentPage: 0,
                pageCount: 3,
              ),
            ),
          ),
        ),
      );
      final finger = await tester.startGesture(const Offset(780, 200));
      final before = transform.value.clone();
      other.observePen(
        const PointerDownEvent(pointer: 99, kind: PointerDeviceKind.stylus),
        {},
      );
      await finger.moveBy(const Offset(0, 60));
      other.endPointer(
        const PointerUpEvent(pointer: 99, kind: PointerDeviceKind.stylus),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await finger.moveBy(const Offset(0, 60));
      expect(transform.value, before);
      await finger.up();
      await tester.pumpWidget(const SizedBox());
      other.dispose();
      transform.dispose();
    },
  );

  testWidgets('deletion confirmation never deletes a replacement document', (
    tester,
  ) async {
    final ctrl = controller();
    ctrl.addPage();
    ctrl.addNewContent(1, ink());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => requestDeleteCurrentPage(context, ctrl),
            child: const Text('Delete'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final replacement = XppFile.empty();
    ctrl.file = replacement;
    await tester.tap(find.byKey(const ValueKey('confirm-delete-page')));
    await tester.pumpAndSettle();
    expect(ctrl.file, same(replacement));
    expect(replacement.pages!.length, 1);
    await tester.pumpWidget(const SizedBox());
    ctrl.dispose();
  });

  testWidgets('scrollbar recovers from suspension without an old pointer-up', (
    tester,
  ) async {
    final transform = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: PageScrollbar(
              transform: transform,
              viewport: const Size(800, 600),
              sceneHeight: 3000,
              currentPage: 0,
              pageCount: 3,
            ),
          ),
        ),
      ),
    );
    final lost = await tester.startGesture(const Offset(780, 200), pointer: 12);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final before = transform.value.clone();
    final fresh = await tester.startGesture(
      const Offset(780, 400),
      pointer: 13,
    );
    expect(transform.value, isNot(before));
    await fresh.up();
    await lost.cancel();
    await tester.pumpWidget(const SizedBox());
    transform.dispose();
  });

  for (final size in [const Size(1000, 600), const Size(400, 1000)]) {
    testWidgets(
      'split divider rejects pen-adjacent palms and permits fresh drag at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final ws = WorkspaceController(autosaveEnabled: false);
        final other = CanvasTouchSession();
        await tester.pumpWidget(
          ChangeNotifierProvider<WorkspaceController>.value(
            value: ws,
            child: const MaterialApp(
              home: Scaffold(
                body: SplitScreenView(
                  primaryWidget: SizedBox.expand(),
                  secondaryWidget: SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final divider = find.byKey(const ValueKey('split-divider'));
        final delta = size.width > size.height
            ? const Offset(80, 0)
            : const Offset(0, 80);
        other.observePen(
          const PointerDownEvent(pointer: 99, kind: PointerDeviceKind.stylus),
          {},
        );
        final palm = await tester.startGesture(tester.getCenter(divider));
        await palm.moveBy(delta);
        await palm.moveBy(delta);
        await palm.up();
        await tester.pump();
        expect(ws.dividerRatio, .5);
        other.endPointer(
          const PointerUpEvent(pointer: 99, kind: PointerDeviceKind.stylus),
        );
        await tester.pump(const Duration(milliseconds: 350));
        final finger = await tester.startGesture(tester.getCenter(divider));
        await finger.moveBy(delta);
        await tester.pump();
        await finger.moveBy(delta);
        await tester.pump();
        await finger.up();
        await tester.pump(const Duration(milliseconds: 350));
        expect(ws.dividerRatio, greaterThan(.5));
        await tester.pumpWidget(const SizedBox());
        other.dispose();
        ws.dispose();
      },
    );
  }

  test('offscreen ink avoids constructing its render path', () {
    final stroke = ink(y: 10000);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 300, 300));
    final origin = stroke.getOffset();
    canvas.translate(origin.dx, origin.dy);
    final before = XppStrokePainter.debugPathBuilds;
    stroke.paintToCanvas(canvas, const Size(300, 11000));
    expect(XppStrokePainter.debugPathBuilds, before);
    recorder.endRecording().dispose();
  });
}
