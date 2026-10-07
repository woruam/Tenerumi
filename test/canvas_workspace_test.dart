import 'dart:io';
import 'dart:async';

import 'package:flutter/gestures.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/autosave_store.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/document_export.dart';
import 'package:xournalpp/widgets/infinite_canvas.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/layers_panel.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';

import 'plugin_system_test.dart' as plugin_tests show source;

XppStroke stroke([double x = 50, double y = 50]) => XppStrokePen(
  color: Colors.black,
  points: [
    XppStrokePoint(x: x, y: y, width: 4),
    XppStrokePoint(x: x + 30, y: y, width: 4),
  ],
);
Future<FilePickerCross> unavailable(String? path) async =>
    throw StateError('Missing $path');
CanvasController canvas() =>
    CanvasController(autosaveEnabled: false)..file = XppFile.empty();

class DocumentsProvider extends PathProviderPlatform {
  final String path;
  DocumentsProvider(this.path);
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('untrusted document IDs cannot turn checkpoint names into paths', () {
    final file = XppFile(documentId: '../../outside', pages: []);
    expect(file.documentId, matches(RegExp(r'^[a-zA-Z0-9_-]{1,100}$')));
    expect(file.documentId, isNot('../../outside'));
  });

  test('plugins commit to the active layer and reject locked layers without persisting state', () async {
    final ctrl = canvas();
    final plugins = PluginController();
    addTearDown(ctrl.dispose);
    addTearDown(plugins.dispose);
    await plugins.install(
      plugin_tests.source([
        {
          'action': 'text.add',
          'args': {'text': 'Formula'},
        },
      ]),
    );
    ctrl.addLayer(0);
    await plugins.execute('test.plugin', 'run', ctrl);
    expect(ctrl.file!.pages!.first.layers!.first.content, isEmpty);
    expect(ctrl.activeLayer(0).content, hasLength(1));
    ctrl.undo();
    expect(ctrl.activeLayer(0).content, isEmpty);
    ctrl.updateLayer(0, 1, locked: true);
    final snapshots = ctrl.undoStack.length;
    await expectLater(
      plugins.execute('test.plugin', 'run', ctrl),
      throwsStateError,
    );
    expect(ctrl.activeLayer(0).content, isEmpty);
    expect(ctrl.undoStack.length, snapshots);
  });

  test('autosave debounce runs without a manual save request', () async {
    final directory = await Directory.systemTemp.createTemp('osipp-debounce-');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = DocumentsProvider(directory.path);
    final ctrl = CanvasController()..init(XppFile.empty());
    final completed = Completer<void>();
    ctrl.addListener(() {
      if (ctrl.lastAutosave != null && !completed.isCompleted) {
        completed.complete();
      }
    });
    try {
      ctrl.addNewContent(0, stroke());
      await completed.future.timeout(const Duration(seconds: 8));
      expect(ctrl.autosaveError, isNull);
      final restored = await AutosaveStore.restore(
        (await AutosaveStore.list()).single,
      );
      expect(restored.pages!.first.layers!.first.content, hasLength(1));
      await ctrl.discardRecovery();
    } finally {
      ctrl.dispose();
      PathProviderPlatform.instance = previous;
      await directory.delete(recursive: true);
    }
  });

  test(
    'plugins render infinite notes using the visible crop dimensions',
    () async {
      final ctrl = canvas();
      ctrl.file!.pages!.first.infinite = true;
      ctrl.addNewContent(0, stroke(-1000, -700));
      Map<String, dynamic>? image;
      final plugins = PluginController(
        extendApi: (api, session) {
          api.register('test.capture', {}, (args) {
            image = args;
            return null;
          });
        },
      );
      addTearDown(ctrl.dispose);
      addTearDown(plugins.dispose);
      await plugins.install(
        plugin_tests.source(
          [
            {'action': 'page.render', 'as': 'png'},
            {
              'action': 'test.capture',
              'args': {'var': 'png'},
            },
          ],
          permissions: ['document.read'],
        ),
      );
      await plugins.execute('test.plugin', 'run', ctrl);
      expect(image!['width'], lessThan(150));
      expect(image!['height'], lessThan(150));
      expect(image!['base64'], isNotEmpty);
      expect(
        (ctrl.activeLayer(0).content!.first as XppStroke).points!.first.x,
        -1000,
      );
    },
  );

  test('XOPP preserves infinite mode, negative coordinates, layers and document identity', () async {
    final file = XppFile.empty(title: 'Infinito');
    file.pages!.first.infinite = true;
    file.pages!.first.layers = [
      XppLayer(
        content: [stroke(-500, -200)],
        name: 'Bozza & idee',
        locked: true,
      ),
      XppLayer(content: [], name: 'Nascosto', visible: false),
    ];
    final parsed = await XppFile.fromFilePickerCross(
      FilePickerCross(await file.toUint8ListAsync()),
      null,
      unavailable,
    );
    expect(parsed.documentId, file.documentId);
    expect(parsed.pages!.first.infinite, isTrue);
    final layers = parsed.pages!.first.layers!;
    expect(layers.first.name, 'Bozza & idee');
    expect(layers.first.locked, isTrue);
    expect(layers.last.visible, isFalse);
    expect((layers.first.content!.first as XppStroke).points!.first.x, -500);
  });

  test('active layer isolates drawing, erasing and undo across layers', () {
    final ctrl = canvas();
    addTearDown(ctrl.dispose);
    ctrl.addNewContent(0, stroke());
    ctrl.addLayer(0);
    ctrl.addNewContent(0, stroke(200, 200));
    ctrl.eraserMode = EraserMode.stroke;
    expect(ctrl.file!.pages!.first.layers!.first.content, hasLength(1));
    ctrl.filterEraser(
      pageIndex: 0,
      coordinates: const Offset(215, 200),
      radius: 50,
    );
    expect(ctrl.activeLayer(0).content, isEmpty);
    expect(ctrl.file!.pages!.first.layers!.first.content, hasLength(1));
    ctrl.undo();
    expect(ctrl.activeLayer(0).content, hasLength(1));
    ctrl.undo();
    expect(ctrl.activeLayer(0).content, isEmpty);
    ctrl.undo();
    expect(ctrl.file!.pages!.first.layers, hasLength(1));
    expect(ctrl.activeLayerIndex(0), 0);
    ctrl.redo();
    expect(ctrl.file!.pages!.first.layers, hasLength(2));
    expect(ctrl.activeLayerIndex(0), 1);
  });

  test(
    'locked and hidden layers reject writing, deleting, erasing and paste',
    () {
      final ctrl = canvas();
      addTearDown(ctrl.dispose);
      final original = stroke();
      ctrl.addNewContent(0, original);
      ctrl.clipboard.copy([original]);
      for (final locked in [true, false]) {
        ctrl.updateLayer(0, 0, locked: locked, visible: locked);
        final revision = ctrl.pluginRevision;
        ctrl.addNewContent(0, stroke(100));
        ctrl.deleteContent(0, [original]);
        ctrl.removeLastContent(0);
        ctrl.filterEraser(
          pageIndex: 0,
          coordinates: const Offset(60, 50),
          radius: 100,
        );
        expect(ctrl.pasteSelection(0, const Offset(200, 200)), isEmpty);
        expect(ctrl.activeLayer(0).content, [original]);
        expect(ctrl.pluginRevision, revision);
      }
    },
  );

  test('layer rename, order, visibility and delete are undoable and keep active object', () {
    final ctrl = canvas();
    addTearDown(ctrl.dispose);
    ctrl.addLayer(0);
    final selected = ctrl.activeLayer(0);
    ctrl.updateLayer(0, 1, name: 'Finale', visible: false, locked: true);
    ctrl.moveLayer(0, 1, 0);
    expect(ctrl.activeLayer(0), same(selected));
    ctrl.deleteLayer(0, 1);
    expect(ctrl.activeLayer(0).name, 'Finale');
    ctrl.undo();
    expect(ctrl.file!.pages!.first.layers, hasLength(2));
    ctrl.undo();
    expect(ctrl.activeLayerIndex(0), 1);
    ctrl.undo();
    expect(ctrl.activeLayer(0).visible, isTrue);
    expect(ctrl.activeLayer(0).locked, isFalse);
    ctrl.deleteLayer(0, 0);
    ctrl.deleteLayer(0, 0);
    expect(ctrl.file!.pages!.first.layers, hasLength(1));
  });

  test('infinite PDF crop includes negative content without modifying the original', () async {
    final file = XppFile.empty();
    final page = file.pages!.first..infinite = true;
    page.layers = [
      XppLayer(content: [stroke(-900, -500)]),
      XppLayer(content: [stroke(100000, 100000)], visible: false),
    ];
    final exported = exportPageSnapshot(page);
    expect(exported.pageSize!.width, lessThan(100));
    expect(exported.pageSize!.height, lessThan(100));
    expect(
      (page.layers!.first.content!.first as XppStroke).points!.first.x,
      -900,
    );
    final png = await rasterizeExportPage(page);
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, lessThan(200));
    final pixels = (await frame.image.toByteData())!.buffer.asUint8List();
    expect(pixels.where((value) => value == 0).length, greaterThan(0));
    frame.image.dispose();
    codec.dispose();
    final pdf = await buildNotesPdf(file, loadBackground: (_, _) async => null);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });

  test(
    'checkpoint survives controller disposal and restores latest revision',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'osipp-recovery-',
      );
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = DocumentsProvider(directory.path);
      final ctrl = CanvasController()..init(XppFile.empty(title: 'Bozza'));
      try {
        ctrl.addNewContent(0, stroke());
        await ctrl.flushAutosave();
        ctrl.addLayer(0);
        ctrl.addNewContent(0, stroke(-400));
        await Future.wait([ctrl.flushAutosave(), ctrl.flushAutosave()]);
        expect(ctrl.autosaveError, isNull);
        expect(ctrl.hasUnsavedChanges, isTrue);
        ctrl.dispose();
        final entries = await AutosaveStore.list();
        expect(entries, hasLength(1));
        final restored = await AutosaveStore.restore(entries.single);
        expect(restored.title, 'Bozza');
        expect(restored.pages!.first.layers, hasLength(2));
        expect(restored.pages!.first.layers!.last.content, hasLength(1));
        final files = Directory('${directory.path}/xournalpp').listSync();
        expect(files.whereType<File>(), hasLength(1));
        await AutosaveStore.remove(restored.documentId);
        expect(await AutosaveStore.list(), isEmpty);
      } finally {
        PathProviderPlatform.instance = previous;
        await directory.delete(recursive: true);
      }
    },
  );

  test('named document autosaves original; failure keeps the recovery and dirty state', () async {
    final directory = await Directory.systemTemp.createTemp(
      'osipp-auto-original-',
    );
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = DocumentsProvider(directory.path);
    final ctrl = CanvasController()
      ..file = (XppFile.empty()..sourcePath = '${directory.path}/notes.xopp');
    try {
      ctrl.addNewContent(0, stroke());
      await ctrl.flushAutosave();
      expect(ctrl.hasUnsavedChanges, isFalse);
      final parsed = await XppFile.fromFilePickerCross(
        FilePickerCross(await File(ctrl.file!.sourcePath!).readAsBytes()),
        null,
        unavailable,
      );
      expect(parsed.pages!.first.layers!.first.content, hasLength(1));
      ctrl.addNewContent(0, stroke(100));
      await ctrl.flushAutosave();
      final updated = await XppFile.fromFilePickerCross(
        FilePickerCross(await File(ctrl.file!.sourcePath!).readAsBytes()),
        null,
        unavailable,
      );
      expect(updated.pages!.first.layers!.first.content, hasLength(2));
      ctrl.file!.sourcePath =
          directory.path; // Cannot replace a directory with a document.
      ctrl.addNewContent(0, stroke(150));
      await ctrl.flushAutosave();
      expect(ctrl.hasUnsavedChanges, isTrue);
      expect(ctrl.autosaveError, isNotNull);
      final restored = await AutosaveStore.restore(
        (await AutosaveStore.list()).single,
      );
      expect(restored.pages!.first.layers!.first.content, hasLength(3));
      await ctrl.discardRecovery();
      expect(await AutosaveStore.list(), isEmpty);
    } finally {
      ctrl.dispose();
      PathProviderPlatform.instance = previous;
      await directory.delete(recursive: true);
    }
  });

  testWidgets(
    'infinite viewport writes at negative and far-away coordinates at different zooms',
    (tester) async {
      final ctrl = canvas();
      ctrl.file!.pages!.first.infinite = true;
      ctrl.setTool(EditingTool.STYLUS);
      final transform = TransformationController(
        Matrix4.identity()
          ..translate(300.0, 200.0)
          ..scale(2.0),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InfiniteCanvas(canvas: ctrl, transform: transform),
          ),
        ),
      );
      final pen = await tester.startGesture(
        const Offset(100, 100),
        kind: PointerDeviceKind.stylus,
      );
      await pen.moveTo(const Offset(140, 120));
      await pen.up();
      await tester.pump();
      final first = ctrl.activeLayer(0).content!.first as XppStroke;
      expect(first.points!.first.x, closeTo(-100, 1));
      expect(first.points!.first.y, closeTo(-50, 1));
      transform.value = Matrix4.identity()..translate(-1000000.0, -2000000.0);
      await tester.pump();
      final second = await tester.startGesture(
        const Offset(100, 100),
        kind: PointerDeviceKind.stylus,
      );
      await second.moveTo(const Offset(130, 100));
      await second.up();
      await tester.pump();
      expect(
        (ctrl.activeLayer(0).content!.last as XppStroke).points!.first.x,
        closeTo(1000100, 1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
      transform.dispose();
    },
  );

  testWidgets(
    'infinite viewport pans horizontally and vertically at 100 percent without adding ink',
    (tester) async {
      final ctrl = canvas();
      ctrl.setTool(EditingTool.STYLUS);
      final transform = TransformationController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InfiniteCanvas(canvas: ctrl, transform: transform),
          ),
        ),
      );
      final touch = await tester.startGesture(const Offset(200, 200));
      await touch.moveTo(const Offset(225, 220));
      await touch.moveTo(const Offset(345, 300));
      await touch.up();
      await tester.pump();
      final translation = transform.value.getTranslation();
      expect(translation.x, greaterThan(50));
      expect(translation.y, greaterThan(30));
      expect(ctrl.activeLayer(0).content, isEmpty);
      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
      transform.dispose();
    },
  );

  testWidgets(
    'locking a selected layer removes edit controls and rejects stylus ink',
    (tester) async {
      final ctrl = canvas();
      ctrl.setTool(EditingTool.STYLUS);
      final transform = TransformationController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: ctrl,
              builder: (_, _) =>
                  InfiniteCanvas(canvas: ctrl, transform: transform),
            ),
          ),
        ),
      );
      ctrl.updateLayer(0, 0, locked: true);
      await tester.pump();
      final pen = await tester.startGesture(
        const Offset(100, 100),
        kind: PointerDeviceKind.stylus,
      );
      await pen.moveTo(const Offset(150, 100));
      await pen.up();
      await tester.pump();
      expect(ctrl.activeLayer(0).content, isEmpty);
      expect(
        tester.widget<PointerListener>(find.byType(PointerListener)).readOnly,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
      transform.dispose();
    },
  );

  testWidgets('layer controls add, select, hide and lock on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ctrl = canvas();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLayersPanel(context, ctrl),
              child: const Text('Livelli'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Livelli'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aggiungi livello'));
    await tester.pumpAndSettle();
    expect(ctrl.file!.pages!.first.layers, hasLength(2));
    await tester.tap(find.byTooltip('Blocca').first);
    await tester.pumpAndSettle();
    expect(ctrl.activeLayer(0).locked, isTrue);
    await tester.tap(find.byTooltip('Nascondi').first);
    await tester.pumpAndSettle();
    expect(ctrl.activeLayer(0).visible, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    ctrl.dispose();
  });
}
