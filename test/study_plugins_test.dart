import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';
import 'package:xournalpp/plugins/plugin_manager_page.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/app_features.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/src/note_flashcards.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/canvas_toolbar.dart';
import 'package:xournalpp/widgets/note_flashcards_panel.dart';

NoteFlashcard card({String id = 'card-1', String front = 'Domanda'}) =>
    NoteFlashcard(
      id: id,
      front: FlashcardSide(text: front),
      back: FlashcardSide(text: 'Risposta'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('shape properties survive switching tools without changing pen', () {
    final c = CanvasController(autosaveEnabled: false)..file = XppFile.empty();
    addTearDown(c.dispose);
    c.setPenProps(Colors.blue, 3);
    c.setShapeProps(Colors.red, 7);
    c.setTool(EditingTool.SHAPE_RECT);
    expect(c.getCurrentToolColor(), Colors.red);
    expect(c.getCurrentToolWidth(), 7);
    c.setTool(EditingTool.STYLUS);
    expect(c.getCurrentToolColor(), Colors.blue);
    expect(c.getCurrentToolWidth(), 3);
    c.setPenProps(Colors.green, 2);
    c.setTool(EditingTool.SHAPE_CIRCLE);
    expect(c.getCurrentToolColor(), Colors.red);
    expect(c.getCurrentToolWidth(), 7);
  });

  test('built-in activation persists independently', () async {
    final plugins = PluginController();
    addTearDown(plugins.dispose);
    await plugins.load();
    expect(plugins.pomodoroEnabled, isFalse);
    expect(plugins.ankiEnabled, isFalse);
    await plugins.setBuiltInEnabled('pomodoro', true);
    await plugins.setBuiltInEnabled('anki', true);
    await plugins.setBuiltInEnabled('pomodoro', false);
    final reload = PluginController();
    addTearDown(reload.dispose);
    await reload.load();
    expect(reload.pomodoroEnabled, isFalse);
    expect(reload.ankiEnabled, isTrue);
  });

  test(
    'flashcards round trip with crops; snapshots and notes stay independent',
    () async {
      final c = CanvasController(autosaveEnabled: false)
        ..file = XppFile.empty();
      addTearDown(c.dispose);
      c.saveFlashcard(
        NoteFlashcard(
          id: 'crop-1',
          front: FlashcardSide(
            image: Uint8List.fromList(kTransparentImage),
            page: 2,
          ),
          back: FlashcardSide(text: 'Risposta con < & \n'),
        ),
      );
      expect(c.hasUnsavedChanges, isTrue);
      final snapshot = c.file!.snapshot();
      c.deleteFlashcard('crop-1');
      expect(snapshot.flashcards, hasLength(1));
      final restored = await XppFile.fromFilePickerCross(
        FilePickerCross(await snapshot.toUint8ListAsync()),
        null,
        (_) async => throw StateError('Missing file'),
      );
      expect(restored.flashcards['crop-1']!.front.image, kTransparentImage);
      expect(restored.flashcards['crop-1']!.front.page, 2);
      expect(restored.flashcards['crop-1']!.back.text, 'Risposta con < & \n');
      expect(XppFile.empty().flashcards, isEmpty);
    },
  );

  test('Anki bundle escapes text, contains media and a JSON backup', () {
    final imageCard = NoteFlashcard(
      id: 'image-card',
      front: FlashcardSide(image: Uint8List.fromList(kTransparentImage)),
      back: FlashcardSide(text: 'A < B\nC\tD'),
    );
    final bundle = flashcardsAnkiBundle([imageCard], 'Lezione\n#injected');
    final zip = ZipDecoder().decodeBytes(bundle);
    final txt = utf8.decode(zip.find('flashcard.txt')!.readBytes()!);
    expect(txt, contains('#deck:Lezione #injected\n'));
    expect(
      txt,
      contains('<img src="osipp_image-card_front.png">\tA &lt; B<br>C&#9;D'),
    );
    expect(
      zip.find('media/osipp_image-card_front.png')!.readBytes(),
      kTransparentImage,
    );
    final json = jsonDecode(
      utf8.decode(zip.find('flashcard.json')!.readBytes()!),
    ) as Map;
    expect(json['cards'][0]['id'], 'image-card');
  });

  testWidgets('double-selection tool emits rectangles and never ink', (
    tester,
  ) async {
    final rects = <Rect>[];
    var strokes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: PointerListener(
              toolData: const {PointerDeviceKind.mouse: EditingTool.FLASHCARD},
              onFlashcardSelection: rects.add,
              onNewContent: (_) => strokes++,
              child: const SizedBox.expand(
                child: ColoredBox(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(PointerListener));
    for (final x in [20.0, 140.0]) {
      final gesture = await tester.startGesture(
        origin + Offset(x, 20),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(origin + Offset(x + 60, 90));
      await gesture.up();
    }
    expect(rects, [
      const Rect.fromLTRB(20, 20, 80, 90),
      const Rect.fromLTRB(140, 20, 200, 90),
    ]);
    expect(strokes, 0);
    final cancelled = await tester.startGesture(
      origin + const Offset(20, 20),
      kind: PointerDeviceKind.mouse,
    );
    await cancelled.moveTo(origin + const Offset(100, 100));
    await cancelled.cancel();
    expect(rects, hasLength(2));
    expect(strokes, 0);
  });

  testWidgets('plugin activation controls toolbar and selection UI', (
    tester,
  ) async {
    final c = CanvasController(autosaveEnabled: false)..file = XppFile.empty();
    final p = PluginController();
    final theme = ThemeController();
    await p.load();
    addTearDown(c.dispose);
    addTearDown(p.dispose);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CanvasController>.value(value: c),
          ChangeNotifierProvider<PluginController>.value(value: p),
          ChangeNotifierProvider<ThemeController>.value(value: theme),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: CanvasToolbar(
              penKey: GlobalKey(),
              highlighterKey: GlobalKey(),
              shapeKey: GlobalKey(),
              eraserKey: GlobalKey(),
              onPenTap: () {},
              onHighlighterTap: () {},
              onShapeTap: () {},
              onEraserTap: () {},
              onImportPdf: () {},
              onToolSelect: c.setTool,
              onPomodoroTap: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Pomodoro'), findsNothing);
    expect(find.byTooltip('Flashcard: doppia selezione'), findsNothing);
    await p.setBuiltInEnabled('pomodoro', true);
    await p.setBuiltInEnabled('anki', true);
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Pomodoro'),
      AppFeatures.plugins ? findsOneWidget : findsNothing,
    );
    expect(
      find.byTooltip('Flashcard: doppia selezione'),
      AppFeatures.plugins ? findsOneWidget : findsNothing,
    );
    c.beginFlashcard();
    await tester.pumpAndSettle();
    expect(
      find.text('1 · Titolo'),
      AppFeatures.plugins ? findsOneWidget : findsNothing,
    );
    await p.setBuiltInEnabled('pomodoro', false);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pomodoro'), findsNothing);
  });

  testWidgets('cards can be edited and deleted only in their note', (
    tester,
  ) async {
    final c = CanvasController(autosaveEnabled: false)
      ..file = XppFile.empty(title: 'Lezione');
    final other = XppFile.empty();
    c.saveFlashcard(card());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showNoteFlashcards(context, c),
              child: const Text('Apri'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Domanda'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Titolo corretto');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(c.file!.flashcards['card-1']!.front.text, 'Titolo corretto');
    expect(find.text('Titolo corretto'), findsOneWidget);
    expect(other.flashcards, isEmpty);
    await tester.tap(find.byTooltip('Elimina flashcard'));
    await tester.pumpAndSettle();
    expect(c.file!.flashcards, isEmpty);
  }, skip: !AppFeatures.plugins);

  testWidgets('native plugins are listed without installation', (tester) async {
    final p = PluginController();
    await p.load();
    addTearDown(p.dispose);
    await tester.pumpWidget(MaterialApp(home: PluginManagerPage(plugins: p)));
    expect(find.text('Timer Pomodoro'), findsOneWidget);
    expect(find.text('Flashcard per Anki'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plugin-pomodoro')));
    await tester.pumpAndSettle();
    expect(p.pomodoroEnabled, isTrue);
  });

  testWidgets(
    'two captures create a reviewed card without changing source text',
    (tester) async {
      final p = PluginController();
      await p.setBuiltInEnabled('anki', true);
      final c = CanvasController(autosaveEnabled: false)
        ..file = XppFile.empty();
      c.file!.pages!.first.layers!.first.content!.addAll([
        XppText(text: 'Titolo', offset: const Offset(20, 20), size: 16),
        XppText(text: 'Risposta', offset: const Offset(20, 100), size: 16),
      ]);
      addTearDown(c.dispose);
      addTearDown(p.dispose);
      late BuildContext host;
      await tester.pumpWidget(
        ChangeNotifierProvider<PluginController>.value(
          value: p,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                host = context;
                return const Scaffold();
              },
            ),
          ),
        ),
      );
      c.beginFlashcard();
      await tester.runAsync(
        () => captureFlashcardSelection(
          host,
          c,
          0,
          const Rect.fromLTRB(10, 10, 200, 70),
        ),
      );
      expect(c.flashcardFront!.text, 'Titolo');
      expect(c.file!.flashcards, isEmpty);
      Future<void>? capture;
      await tester.runAsync(() async {
        capture = captureFlashcardSelection(
          host,
          c,
          0,
          const Rect.fromLTRB(10, 90, 200, 160),
        );
        final end = DateTime.now().add(const Duration(seconds: 5));
        // Rasterization is real asynchronous work; wait for the editor route.
        while (ModalRoute.of(host)!.isCurrent && DateTime.now().isBefore(end)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Modifica flashcard'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Risposta corretta');
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => capture!);
      expect(c.file!.flashcards.values.single.front.text, 'Titolo');
      expect(c.file!.flashcards.values.single.back.text, 'Risposta corretta');
      expect(
        (c.file!.pages!.first.layers!.first.content!.last as XppText).text,
        'Risposta',
      );
      expect(c.flashcardFront, isNull);
    },
    skip: !AppFeatures.plugins,
  );
}
