import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/controllers/workspace_controller.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/WorkspacePage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/autosave_store.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/src/app_appearance.dart';
import 'package:xournalpp/src/note_audio.dart';
import 'package:xournalpp/src/workspace_session.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/document_navigator.dart';
import 'package:xournalpp/widgets/infinite_canvas.dart';
import 'package:xournalpp/widgets/saved_notes_dialog.dart';

import 'canvas_workspace_test.dart' show stroke, unavailable;
import 'pomodoro_appearance_test.dart' show capture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'insertion remaps layers and ink undo without changing PDF ordinals',
    () {
      final ctrl = CanvasController(autosaveEnabled: false)
        ..init(XppFile.empty());
      addTearDown(ctrl.dispose);
      ctrl.file!.autoGeneratePages = false;
      ctrl.file!.pages!.add(XppPage.empty());
      final original = ctrl.file!.pages![1];
      original.background = XppBackgroundPdf(
        onUnavailable: unavailable,
        filename: 'source.pdf',
        page: 7,
      );
      ctrl.addLayer(1);
      ctrl.addNewContent(1, stroke());
      ctrl.setActivePage(1);
      ctrl.insertPage(after: false);
      expect(ctrl.file!.pages, hasLength(3));
      expect(ctrl.file!.pages![2], same(original));
      expect((original.background as XppBackgroundPdf).page, 7);
      expect(ctrl.activeLayerIndex(2), 1);
      expect(ctrl.file!.pages![1].background, isNot(isA<XppBackgroundPdf>()));
      ctrl.undo();
      expect(ctrl.activeLayer(2).content, isEmpty);
      ctrl.redo();
      expect(ctrl.activeLayer(2).content, hasLength(1));
      expect(ctrl.activePageIndex, 1);
    },
  );
  test('native notes grow near bottom and prevent automatic blank chains; PDFs stay finite', () async {
    final ctrl = CanvasController(autosaveEnabled: false)
      ..init(XppFile.empty());
    addTearDown(ctrl.dispose);
    ctrl.addNewContent(0, stroke(40, 100));
    expect(ctrl.file!.pages, hasLength(1));
    ctrl.addNewContent(0, stroke(40, 800));
    expect(ctrl.file!.pages, hasLength(2));
    expect(ctrl.requestNextPageFromScroll(), isFalse);
    ctrl.addNewContent(1, stroke());
    expect(ctrl.requestNextPageFromScroll(), isTrue);
    expect(ctrl.requestNextPageFromScroll(), isFalse);
    final parsed = await XppFile.fromFilePickerCross(
      FilePickerCross(ctrl.file!.toUint8List()!, path: 'note.xopp'),
      null,
      unavailable,
    );
    expect(parsed.autoGeneratePages, isTrue);
    ctrl.file!.pages!.last.background = XppBackgroundPdf(
      onUnavailable: unavailable,
      filename: 'file.pdf',
      page: 1,
    );
    expect(ctrl.requestNextPageFromScroll(), isFalse);
    ctrl.file!.pages!.last.background = XppBackgroundSolidLined(
      size: ctrl.file!.pages!.last.pageSize,
      color: Colors.white,
    );
    ctrl.file!.pages!.last.infinite = true;
    expect(ctrl.requestNextPageFromScroll(), isFalse);
  });
  test('session restores saved files and focus, skipping missing tabs; explicit clear persists', () async {
    final dir = await Directory.systemTemp.createTemp('osi-session-');
    try {
      final f = XppFile.empty(title: 'Saved');
      final path = '${dir.path}/note.xopp';
      await File(path).writeAsBytes(f.toUint8List()!);
      await WorkspaceSession.save({
        'tabs': [
          {'id': 'missing', 'path': '${dir.path}/gone.xopp'},
          {
            'id': f.documentId,
            'title': f.title,
            'path': path,
            'page': 0,
            'zoom': (Matrix4.identity()..scale(2.0)).storage.toList(),
          },
        ],
        'primary': 1,
        'secondary': 0,
        'split': true,
      });
      final restored = (await WorkspaceSession.restore())!;
      expect(restored.files.single.title, 'Saved');
      expect(restored.state['primary'], 0);
      expect(restored.state['secondary'], isNull);
      expect((restored.tabs.single['zoom'] as List)[0], 2.0);
      await WorkspaceSession.save(null);
      expect(await WorkspaceSession.restore(), isNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('restoration prefers checkpoint over original and preserves audio synchronization', () async {
    // SharedPreferences recovery data uses the existing Web storage only on Web;
    // here use a real temporary checkpoint and index without path-provider writes.
    final dir = await Directory.systemTemp.createTemp('osi-recovery-');
    try {
      final file = XppFile.empty(title: 'Lezione');
      file.recordings['rec'] = NoteRecording(
        'rec',
        3600000,
        Uint8List.fromList([1, 2, 3]),
      );
      final ink = stroke()
        ..audioLink = StrokeAudioLink('rec', 100, 300, [100, 300]);
      file.pages!.first.layers!.first.content!.add(ink);
      final path = '${dir.path}/recovery.xopp';
      await File(path).writeAsBytes(file.toUint8List()!);
      SharedPreferences.setMockInitialValues({
        AutosaveStore.indexKey: jsonEncode([
          {
            'id': file.documentId,
            'title': file.title,
            'path': path,
            'source': null,
            'key': file.recoveryKey,
            'localId': file.localId,
            'time': 1,
          },
        ]),
      });
      await WorkspaceSession.save({
        'tabs': [
          {
            'id': file.documentId,
            'key': file.recoveryKey,
            'localId': file.localId,
          },
        ],
        'primary': 0,
      });
      final checkpoint = (await AutosaveStore.list()).single;
      expect(checkpoint['key'], file.recoveryKey);
      final parsedRecovery = await AutosaveStore.restore(checkpoint);
      expect(parsedRecovery.recordings, contains('rec'));
      final restored = (await WorkspaceSession.restore())!.files.single;
      expect(restored.recovered, isTrue);
      expect(restored.recordings['rec']!.durationMs, 3600000);
      expect(
        (restored.pages!.first.layers!.first.content!.single as XppStroke)
            .audioLink!
            .samples,
        [100, 300],
      );
      expect(maxRecordingMs, 7200000);
      expect(maxRecordingBytes, 48 * 1024 * 1024);
      expect(maxAudioBytes, 128 * 1024 * 1024);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  for (final infinite in [false, true]) {
    testWidgets(
      'pinch pointer drop remains stable and palm is rejected, infinite=$infinite',
      (tester) async {
        final transform = TransformationController();
        final canvas = CanvasController(autosaveEnabled: false)
          ..init(XppFile.empty());
        canvas.file!.pages!.first.infinite = infinite;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: infinite
                  ? InfiniteCanvas(canvas: canvas, transform: transform)
                  : ZoomableWidget(
                      controller: transform,
                      sceneSize: const Size(800, 2000),
                      child: const SizedBox(width: 800, height: 2000),
                    ),
            ),
          ),
        );
        final first = await tester.startGesture(
          const Offset(180, 200),
          pointer: 1,
        );
        final second = await tester.startGesture(
          const Offset(330, 200),
          pointer: 2,
        );
        await first.moveTo(const Offset(130, 200));
        await second.moveTo(const Offset(390, 200));
        await tester.pump();
        expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
        final before = transform.value.clone();
        final third = await tester.startGesture(
          const Offset(450, 300),
          pointer: 9,
        );
        await third.moveBy(const Offset(0, -100));
        await third.moveBy(const Offset(0, -90));
        await third.up();
        await tester.pump();
        expect(
          transform.value.storage,
          pairwiseCompare(
            before.storage,
            (double a, double b) => (a - b).abs() < 1e-8,
            "third contact ignored",
          ),
        );
        await second.up();
        await first.moveBy(const Offset(0, -180));
        await first.moveBy(const Offset(0, -100));
        await tester.pump();
        expect(
          transform.value.storage,
          pairwiseCompare(
            before.storage,
            (double a, double b) => (a - b).abs() < 1e-8,
            "stable matrix",
          ),
        );
        await first.up();
        await tester.pump(const Duration(seconds: 1));
        expect(
          transform.value.storage,
          pairwiseCompare(
            before.storage,
            (double a, double b) => (a - b).abs() < 1e-8,
            "stable matrix",
          ),
        );
        final pen = await tester.startGesture(
          const Offset(200, 200),
          kind: ui.PointerDeviceKind.stylus,
          pointer: 3,
        );
        final palm = await tester.startGesture(
          const Offset(350, 300),
          pointer: 4,
        );
        await palm.moveBy(const Offset(0, -150));
        await tester.pump();
        expect(
          transform.value.storage,
          pairwiseCompare(
            before.storage,
            (double a, double b) => (a - b).abs() < 1e-8,
            "stable matrix",
          ),
        );
        await palm.up();
        await pen.up();
        await tester.pumpWidget(const SizedBox());
        transform.dispose();
        canvas.dispose();
      },
    );
  }
  testWidgets('upward swipe on last native page grows once without inertia', (
    tester,
  ) async {
    final transform = TransformationController();
    int grows = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZoomableWidget(
            controller: transform,
            sceneSize: const Size(800, 600),
            onEndReached: () => grows++,
            child: const SizedBox(width: 800, height: 600),
          ),
        ),
      ),
    );
    final finger = await tester.startGesture(const Offset(200, 420));
    await finger.moveBy(const Offset(0, -20));
    await finger.moveBy(const Offset(0, -130));
    await finger.up();
    await tester.pump();
    expect(grows, 1);
    final end = transform.value.clone();
    await tester.pump(const Duration(seconds: 1));
    expect(transform.value.storage, orderedEquals(end.storage));
    await tester.pumpWidget(const SizedBox());
    transform.dispose();
  });
  testWidgets('saved app notes open without leaving workspace', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('osi-library-'),
    ))!;
    final f = XppFile.empty(title: 'Nota in libreria')..tag = 'Studio';
    final path = '${dir.path}/note.xopp';
    await tester.runAsync(() => File(path).writeAsBytes(f.toUint8List()!));
    SharedPreferences.setMockInitialValues({
      PreferencesKeys.kRecentFiles: jsonEncode([
        {'name': f.title, 'path': path, 'tag': f.tag},
      ]),
    });
    XppFile? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await openSavedNote(context);
            },
            child: const Text('Apri'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nota in libreria'));
    await tester.pumpAndSettle();
    for (var i = 0; selected == null && i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(selected!.sourcePath, path);
    expect(selected!.tag, 'Studio');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => dir.delete(recursive: true));
  });
  testWidgets(
    'sidebar stays open for layer switching, page insertion and thumbnails; workspace survives background',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        for (final font in {
          'Inter': 'fonts/Inter/Inter-Variable.ttf',
          'VT323': 'fonts/VT323/VT323-Regular.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          await (FontLoader(
            font.key,
          )..addFont(rootBundle.load(font.value))).load();
        }
      });
      final theme = ThemeController();
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<ThemeController>.value(
            value: theme,
            child: MaterialApp(
              theme: AppAppearance.buildTheme(theme, null),
              home: WorkspacePage(
                initialFile: XppFile.empty(title: 'Lezione OSI'),
                autosaveEnabled: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ws = tester
          .element(find.byType(CanvasPage))
          .read<WorkspaceController>();
      final ctrl = ws.active;
      ctrl.addLayer(0);
      ctrl.updateLayer(0, 1, name: 'Evidenziatore');
      ctrl.setPenProps(Colors.red, null);
      ctrl.setHighlighterProps(Colors.amber, null);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('layers-manager')));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentNavigator), findsOneWidget);
      await tester.tap(find.text('Livello'));
      await tester.pumpAndSettle();
      expect(ctrl.activeLayerIndex(0), 0);
      expect(find.byType(DocumentNavigator), findsOneWidget);
      await capture(tester, key, 'osi-sidebar-layers');
      ctrl.file!.autoGeneratePages = false;
      ctrl.addNewContent(0, stroke());
      await tester.tap(find.byTooltip('Aggiungi Pagina'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pagina dopo questa'));
      await tester.pumpAndSettle();
      expect(ctrl.file!.pages, hasLength(2));
      expect(ctrl.activePageIndex, 1);
      final paperCards = tester.widgetList<Card>(find.byType(Card));
      expect(
        paperCards.every((c) => c.shape == const RoundedRectangleBorder()),
        isTrue,
      );
      await tester.tap(find.text('Pagine'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      for (var i = 0; find.byType(Image).evaluate().length < 2 && i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.byType(Image), findsNWidgets(2));
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pump();
      await capture(tester, key, 'osi-sidebar-pages');
      tester.view.physicalSize = const Size(380, 800);
      await tester.pumpAndSettle();
      await capture(tester, key, 'osi-sidebar-pages-phone');
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(1100, 800);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pagina 1'));
      await tester.pumpAndSettle();
      expect(ctrl.activePageIndex, 0);
      // No disk autosave is required for this lifecycle test; the blank second tab
      // still has a template so it can be restored after a process restart.
      final other = XppFile.empty(title: 'Altra scheda');
      ws.addDocument(other);
      ws.setPrimary(1);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(ws.documents, hasLength(2));
      expect(ws.activeFile.title, 'Altra scheda');
      await tester.pumpWidget(const SizedBox());
      theme.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'workspace recreates both tabs, split focus, template and zoom after process loss',
    (tester) async {
      final theme = ThemeController();
      Widget mount(WorkspacePage page) =>
          ChangeNotifierProvider<ThemeController>.value(
            value: theme,
            child: MaterialApp(
              theme: AppAppearance.buildTheme(theme, null),
              home: page,
            ),
          );
      final first = XppFile.empty(title: 'Prima', tag: 'Studio');
      first.pages!.first.background = XppBackgroundSolidGraph(
        size: first.pages!.first.pageSize,
        color: Colors.white,
      );
      await tester.pumpWidget(
        mount(WorkspacePage(initialFile: first, autosaveEnabled: false)),
      );
      await tester.pumpAndSettle();
      final ws = tester
          .element(find.byType(CanvasPage))
          .read<WorkspaceController>();
      final zoom = tester
          .widget<ZoomableWidget>(find.byType(ZoomableWidget))
          .controller!;
      zoom.value = Matrix4.identity()
        ..translate(-20.0, -90.0)
        ..scale(2.0);
      ws.addDocument(XppFile.empty(title: 'Seconda'));
      ws.setPrimary(1);
      ws.toggleSplit();
      ws.focus(WorkspacePanel.secondary);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      final restored = (await tester.runAsync(
        () => WorkspaceSession.restore(),
      ))!;
      expect(restored.files, hasLength(2));
      expect(restored.files.first.documentId, first.documentId);
      expect(
        restored.files.first.pages!.first.background,
        isA<XppBackgroundSolidGraph>(),
      );
      expect(restored.files.first.tag, 'Studio');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        mount(WorkspacePage(restored: restored, autosaveEnabled: false)),
      );
      await tester.pumpAndSettle();
      final recreated = tester
          .element(find.byType(CanvasPage).first)
          .read<WorkspaceController>();
      expect(recreated.documents.map((f) => f.title), ['Prima', 'Seconda']);
      expect(recreated.primaryIndex, 1);
      expect(recreated.secondaryIndex, 0);
      expect(recreated.splitEnabled, isTrue);
      expect(recreated.activePanel, WorkspacePanel.secondary);
      final transforms = tester
          .widgetList<ZoomableWidget>(find.byType(ZoomableWidget))
          .map((w) => w.controller!.value.getMaxScaleOnAxis());
      expect(transforms, contains(2.0));
      await tester.pumpWidget(const SizedBox());
      theme.dispose();
    },
  );
  testWidgets(
    'stylus coordinates and undo stay aligned in the real finite canvas at zoom',
    (tester) async {
      final theme = ThemeController();
      final file = XppFile.empty(title: 'Stylo');
      final ctrl = CanvasController(autosaveEnabled: false)..init(file);
      final transform = TransformationController(
        Matrix4.identity()..scale(2.3),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: CanvasPage(
              file: file,
              controller: ctrl,
              zoomController: transform,
              showInternalToolbar: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final box = tester.renderObject<RenderBox>(
        find.byType(PointerListener).first,
      );
      final start = box.localToGlobal(const Offset(40, 60));
      final end = box.localToGlobal(const Offset(60, 90));
      final pen = await tester.startGesture(
        start,
        kind: ui.PointerDeviceKind.stylus,
      );
      await pen.moveTo(end);
      await pen.up();
      await tester.pump();
      final ink = file.pages!.first.layers!.first.content!.single as XppStroke;
      expect(ink.points!.first.x, closeTo(40, .001));
      expect(ink.points!.first.y, closeTo(60, .001));
      expect(ink.points!.last.x, closeTo(60, .001));
      expect(ink.points!.last.y, closeTo(90, .001));
      ctrl.undo();
      await tester.pump();
      expect(file.pages!.first.layers!.first.content, isEmpty);
      await tester.pumpWidget(const SizedBox());
      transform.dispose();
      ctrl.dispose();
      theme.dispose();
    },
  );
}
