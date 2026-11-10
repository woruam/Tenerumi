import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:xournalpp/widgets/bounded_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/workspace_controller.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/src/recent_documents.dart';
import 'package:xournalpp/widgets/document_library_card.dart';
import 'package:xournalpp/widgets/note_tag_picker.dart';

import 'document_storage_test.dart' show TestDocumentsProvider;
import 'pomodoro_appearance_test.dart' show capture;

XppStroke redLine() => XppStrokePen(
  color: Colors.red,
  points: [
    XppStrokePoint(x: 40, y: 80, width: 12),
    XppStrokePoint(x: 500, y: 80, width: 12),
  ],
);

Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  int count = 1,
}) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.pump();
    if (finder.evaluate().length >= count) {
      await tester.pumpAndSettle();
      return;
    }
    // Let actual disk I/O, preview rasterization and parsing isolates finish.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('The application did not display $finder');
}

WorkspaceController workspace(WidgetTester tester) =>
    tester.element(find.byType(CanvasPage)).read<WorkspaceController>();

void main() {
  test('numeric modified dates work without initialized locale symbols', () {
    final previous = Intl.defaultLocale;
    addTearDown(() => Intl.defaultLocale = previous);
    for (final locale in ['en', 'de', 'pt', 'it_IT']) {
      Intl.defaultLocale = locale;
      expect(
        documentModifiedLabel('2026-01-02T03:04:00'),
        'Modificato il 02/01/2026 03:04',
      );
    }
    expect(documentModifiedLabel('invalid'), 'Data non disponibile');
    expect(documentModifiedLabel(null), 'Data non disponibile');
    final utc = DateTime.utc(2026, 10, 8, 23, 5);
    expect(
      documentModifiedLabel(utc.toIso8601String()),
      documentModifiedLabel(utc.toLocal().toIso8601String()),
    );
  });

  testWidgets(
    'cold-start home previews and reopens old and newly saved files',
    (tester) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousProvider = PathProviderPlatform.instance;
      late Directory directory;
      late String oldPath;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('osipp-home-reopen-');
        PathProviderPlatform.instance = TestDocumentsProvider(directory.path);
        oldPath = '${directory.path}/old.xopp';
        final old = XppFile.empty(title: 'Appunto precedente');
        old.pages!.first.layers!.first.content!.add(redLine());
        await File(oldPath).writeAsBytes(await old.toUint8ListAsync());
        for (final font in {
          'VT323': 'fonts/VT323/VT323-Regular.ttf',
          'Inter': 'fonts/Inter/Inter-Variable.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          await (FontLoader(
            font.key,
          )..addFont(rootBundle.load(font.value))).load();
        }
      });
      addTearDown(() async {
        PathProviderPlatform.instance = previousProvider;
        await directory.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({
        'app_language': 'it',
        PreferencesKeys.kRecentFiles: jsonEncode([
          {
            'name': 'Appunto precedente',
            'path': oldPath,
            'tag': 'Appunti',
            'preview': '',
          },
        ]),
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: const XournalppMobile()),
      );
      final previews = find.descendant(
        of: find.byType(DocumentLibraryCard),
        matching: find.byType(BoundedImage),
      );
      await waitFor(tester, previews);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Appunto precedente'));
      await waitFor(tester, find.byType(CanvasPage));
      expect(workspace(tester).active.file!.sourcePath, oldPath);
      expect(
        workspace(tester).active.file!.pages!.first.layers!.first.content,
        hasLength(1),
      );
      await tester.tap(find.byIcon(Icons.arrow_back_outlined));
      await waitFor(tester, find.byType(OpenPage));
      await tester.tap(find.text('Nuovo Appunto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Appunto appena salvato');
      await tester.tap(find.text('Crea tag'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Università');
      await tester.tap(find.text('Crea'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NoteTagPicker>(find.byType(NoteTagPicker)).value,
        'Università',
      );
      await tester.tap(find.text('Crea Foglio'));
      await waitFor(tester, find.byType(CanvasPage));
      expect(workspace(tester).active.file!.tag, 'Università');
      workspace(tester).active.addNewContent(0, redLine());
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('document-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salva'));
      await waitFor(tester, find.text('Documento salvato e verificato'));
      final savedPath = workspace(tester).active.file!.sourcePath!;
      expect(workspace(tester).active.hasUnsavedChanges, isFalse);
      await tester.tap(find.byIcon(Icons.arrow_back_outlined));
      await waitFor(tester, find.byType(OpenPage));
      // Restart the real app: metadata and preview must come from persistence.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: const XournalppMobile()),
      );
      await waitFor(tester, find.text('Appunto appena salvato'));
      expect(previews, findsNWidgets(2));
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
      // Wait for the image providers' normal asynchronous decode, then check
      // displayed pixels, rather than just the existence of Image widgets.
      await waitFor(
        tester,
        find.descendant(
          of: find.byType(DocumentLibraryCard),
          matching: find.byType(RawImage),
        ),
        count: previews.evaluate().length,
      );
      final renderedPreviews = find.descendant(
        of: find.byType(DocumentLibraryCard),
        matching: find.byType(RawImage),
      );
      expect(renderedPreviews, findsNWidgets(2));
      expect(
        tester
            .widgetList<RawImage>(renderedPreviews)
            .every((image) => image.image != null),
        isTrue,
      );
      await capture(tester, key, 'library-grey-fixed-home');
      await tester.runAsync(() async {
        final entry = (await RecentDocuments.list()).singleWhere(
          (e) => e['path'] == savedPath,
        );
        expect(hasDocumentPreview(entry['preview']), isTrue);
        final codec = await ui.instantiateImageCodec(
          base64Decode(entry['preview'] as String),
        );
        final frame = await codec.getNextFrame();
        final pixels = (await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var redPixels = 0;
        for (var i = 0; i < pixels.lengthInBytes; i += 4) {
          if (pixels.getUint8(i) > 180 &&
              pixels.getUint8(i + 1) < 100 &&
              pixels.getUint8(i + 2) < 100) {
            redPixels++;
          }
        }
        expect(redPixels, greaterThan(20));
        frame.image.dispose();
        codec.dispose();
      });
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Università'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Università'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentLibraryCard), findsOneWidget);
      expect(find.text('Appunto precedente'), findsNothing);
      await tester.tap(find.byTooltip('Cambia tag'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scuola').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();
      expect(
        (await RecentDocuments.list()).singleWhere(
          (entry) => entry['path'] == savedPath,
        )['tag'],
        'Scuola',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: const XournalppMobile()),
      );
      await waitFor(tester, find.text('Appunto appena salvato'));
      await tester.tap(find.widgetWithText(FilterChip, 'Scuola'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentLibraryCard), findsOneWidget);
      await waitFor(
        tester,
        find.descendant(
          of: find.byType(DocumentLibraryCard),
          matching: find.byType(RawImage),
        ),
        count: previews.evaluate().length,
      );
      await capture(tester, key, 'osi-edited-note-tag');
      await tester.tap(find.text('Appunto appena salvato'));
      await waitFor(tester, find.byType(CanvasPage));
      expect(workspace(tester).active.file!.tag, 'Scuola');
      expect(workspace(tester).active.file!.sourcePath, savedPath);
      expect(
        workspace(tester).active.file!.pages!.first.layers!.first.content,
        hasLength(1),
      );
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'library-grey-fixed-note');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
