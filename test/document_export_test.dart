import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppTexImage.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/document_export.dart';

Future<FilePickerCross> unavailable(String? path) async =>
    throw StateError('Missing $path');

Future<Uint8List> solidPng(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

XppStroke line(Offset a, Offset b, {Color color = Colors.black}) =>
    XppStrokePen(
      color: color,
      points: [
        XppStrokePoint(x: a.dx, y: a.dy, width: 3),
        XppStrokePoint(x: b.dx, y: b.dy, width: 3),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('PDF export preserves bounded PNG bytes and propagates image budget',
      (tester) async {
    await tester.runAsync(() async {
      final png = await solidPng(Colors.blue);
      // A valid ancillary chunk makes re-encoding observable.
      final data = Uint8List.fromList([
        ...png.take(png.length - 12),
        0,0,0,34,116,69,88,116,67,111,109,109,101,110,116,0,112,114,101,115,101,114,118,101,32,111,114,105,103,105,110,97,108,32,101,110,99,111,100,105,110,103,178,99,117,143,
        ...png.skip(png.length - 12),
      ]);
      final file = XppFile.empty(title: 'Background budget');
      file.pages = List.generate(5, (_) => XppPage(
          pageSize: XppPageSize(width: 100, height: 100),
          background: XppBackgroundImage(filename: 'background.png'),
          layers: [XppLayer.empty()]));
      final budgets = <int>[];
      final result = await prepareNotesPdf(file,
          loadBackground: (_, _, budget) async {
        budgets.add(budget);
        return data;
      });
      try {
        expect(budgets, List.filled(5, 16 * 1024 * 1024 ~/ 5));
        final images = await Directory(result.root!).list()
            .where((entry) => entry.path.endsWith('.png')).toList();
        expect(images, hasLength(1));
        expect(await File(images.single.path).readAsBytes(), data);
      } finally {
        await result.dispose();
      }
    });
  });

  testWidgets('PDF keeps pressure ink, overlapping erasures and layer order', (
    tester,
  ) async {
    final file = XppFile.empty(title: 'PDF quality');
    final page = file.pages!.first;
    page.pageSize = XppPageSize(width: 160, height: 180);
    page.layers!.first.content!.addAll([
      XppStrokePen(
        color: Colors.red,
        points: [
          XppStrokePoint(x: 20, y: 30, width: .5),
          XppStrokePoint(x: 140, y: 30, width: 5),
        ],
      ),
      line(const Offset(20, 60), const Offset(140, 60))
        ..erasures = [
          StrokeErasure(const Offset(70, 55), const Offset(85, 65), 7),
          StrokeErasure(const Offset(80, 55), const Offset(95, 65), 7),
        ],
      XppStrokeHighlight(
        color: Colors.yellow,
        points: [
          XppStrokePoint(x: 20, y: 100, width: 16),
          XppStrokePoint(x: 140, y: 100, width: 16),
          XppStrokePoint(x: 20, y: 100, width: 16),
        ],
      ),
      XppText(
        text: 'OSI\nWWW',
        fontFamily: 'Inter',
        offset: const Offset(20, 125),
        size: 16,
        color: Colors.blue,
      ),
      line(const Offset(20, 150), const Offset(140, 150), color: Colors.green),
    ]);
    page.layers!.add(
      XppLayer(
        visible: false,
        content: [line(const Offset(0, 0), const Offset(160, 180))],
      ),
    );
    await tester.runAsync(() async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('fonts/Inter/Inter-Variable.ttf'))).load();
      final bytes = await buildNotesPdf(
        file,
        loadBackground: (_, _, _) async => null,
      );
      expect(latin1.decode(bytes), contains('%PDF-'));
      await File('docs/validation/pdf-quality.pdf').writeAsBytes(bytes);
      await File('docs/validation/pdf-quality-reference.png')
          .writeAsBytes(await rasterizeExportPage(page, maxScale: 4));
    });
    expect(page.layers!.first.content, hasLength(5));
  });

  testWidgets(
    'PDF exports paper, shapes and bundled text as vectors and retains original image resolution',
    (tester) async {
      final file = XppFile.empty(title: 'Vector shapes');
      final page = file.pages!.first;
      page.pageSize = XppPageSize(width: 160, height: 180);
      page.background = XppBackgroundSolidLined(color: Colors.white);
      page.layers!.first.content!.addAll([
        XppStrokePen(
          color: Colors.red,
          points: [
            XppStrokePoint(x: 20, y: 20, width: 3),
            XppStrokePoint(x: 140, y: 20, width: 3),
            XppStrokePoint(x: 140, y: 60, width: 3),
            XppStrokePoint(x: 20, y: 60, width: 3),
            XppStrokePoint(x: 20, y: 20, width: 3),
          ],
        )..isShape = true,
        XppStrokeHighlight(
            color: Colors.yellow,
            points: [
              XppStrokePoint(x: 80, y: 70, width: 5),
              XppStrokePoint(x: 140, y: 100, width: 5),
              XppStrokePoint(x: 80, y: 130, width: 5),
              XppStrokePoint(x: 20, y: 100, width: 5),
              XppStrokePoint(x: 80, y: 70, width: 5),
            ],
          )
          ..isShape = true
          ..smooth = true,
        XppText(
          text: 'OSI àèìòù\nTesto nitido',
          fontFamily: 'Inter',
          offset: const Offset(20, 135),
          size: 14,
          color: Colors.blue,
        ),
      ]);
      await tester.runAsync(() async {
        await (FontLoader(
          'Inter',
        )..addFont(rootBundle.load('fonts/Inter/Inter-Variable.ttf'))).load();
        final pdf = await buildNotesPdf(
          file,
          loadBackground: (_, _, _) async => null,
        );
        expect(latin1.decode(pdf), isNot(contains('/Subtype /Image')));
        await File('docs/validation/pdf-vector-shapes.pdf').writeAsBytes(pdf);
        await File('docs/validation/pdf-vector-shapes-reference.png')
            .writeAsBytes(await rasterizeExportPage(page, maxScale: 4));
        page.layers!.first.content = [
          XppImage(
            data: await solidPng(Colors.green),
            topLeft: const Offset(0, 0),
            bottomRight: const Offset(160, 180),
          ),
        ];
        final imagePdf = await buildNotesPdf(
          file,
          loadBackground: (_, _, _) async => null,
        );
        final encoded = latin1.decode(imagePdf);
        expect(encoded, contains('/Width 8'));
        expect(encoded, contains('/Height 8'));
      });
    },
  );

  testWidgets(
    'Android document URI can be saved again and reopened from the library',
    (tester) async {
      const channel = MethodChannel('online.xournal.mobile/documents');
      final documents = <String, Uint8List>{};
      const uri = 'content://documents/notes.xopp';
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        final args = Map<String, dynamic>.from(call.arguments as Map);
        switch (call.method) {
          case 'write':
            documents[args['uri'] as String] = args['bytes'] as Uint8List;
            return null;
          case 'read':
            return documents[args['uri']];
          case 'exists':
            return documents.containsKey(args['uri']);
        }
        throw PlatformException(code: 'unsupported');
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      BuildContext? context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final file = XppFile.empty(title: 'Appunti')..sourcePath = uri;
      file.pages!.first.layers!.first.content!.add(
        line(const Offset(10, 10), const Offset(50, 10)),
      );
      final ctrl = CanvasController(autosaveEnabled: false)
        ..file = file
        ..hasUnsavedChanges = true;
      expect(await tester.runAsync(() => ctrl.saveFile(context!)), isTrue);
      expect(file.sourcePath, uri);
      expect(ctrl.hasUnsavedChanges, isFalse);
      expect(await FilePickerCross.exists(uri), isTrue);
      expect(
        await FilePickerCross.exists('content://documents/missing'),
        isFalse,
      );
      final raw = await FilePickerCross.fromInternalPath(path: uri);
      expect(raw.path, uri);
      final parsed = await tester.runAsync(
        () => XppFile.fromFilePickerCross(raw, null, unavailable),
      );
      expect(parsed!.pages!.first.layers!.first.content, hasLength(1));
      expect(calls, containsAllInOrder(['write', 'exists', 'exists', 'read']));
      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
    },
  );

  testWidgets('Android document write failure preserves unsaved changes', (
    tester,
  ) async {
    const channel = MethodChannel('online.xournal.mobile/documents');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'document_access',
        message: 'Permission denied',
      ),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    BuildContext? context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final file = XppFile.empty()..sourcePath = 'content://documents/readonly';
    final ctrl = CanvasController(autosaveEnabled: false)
      ..file = file
      ..hasUnsavedChanges = true;
    expect(await tester.runAsync(() => ctrl.saveFile(context!)), isFalse);
    expect(ctrl.hasUnsavedChanges, isTrue);
    expect(ctrl.savingFile, isFalse);
    expect(file.sourcePath, 'content://documents/readonly');
    await tester.pumpWidget(const SizedBox());
    ctrl.dispose();
  });

  test(
    'PDF raster keeps paper, all layers, text, formulas, image and erased ink',
    () async {
      final ink = line(const Offset(10, 20), const Offset(90, 20));
      final erased = ink
          .eraseWhere(coordinates: const Offset(50, 20), radius: 6)
          .newContent
          .single;
      final page = XppPage(
        pageSize: XppPageSize(width: 100, height: 120),
        background: XppBackgroundSolidPlain(color: Colors.white),
        layers: [
          XppLayer(
            content: [
              erased,
              XppText(
                text: 'ABC',
                offset: const Offset(10, 35),
                size: 12,
                color: Colors.black,
              ),
              XppTexImage(
                text: 'x^2',
                topLeft: const Offset(10, 60),
                color: Colors.black,
              ),
              XppImage(
                data: await solidPng(const Color(0xFFFF0000)),
                topLeft: const Offset(70, 60),
                bottomRight: const Offset(90, 80),
              ),
            ],
          ),
          XppLayer(
            content: [
              line(
                const Offset(10, 100),
                const Offset(90, 100),
                color: const Color(0xFF0000FF),
              ),
            ],
          ),
        ],
      );
      final png = await rasterizeExportPage(page);
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      try {
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        List<int> pixel(int x, int y) => pixels.sublist(
          (y * 2 * image.width + x * 2) * 4,
          (y * 2 * image.width + x * 2) * 4 + 4,
        );
        bool inkIn(Rect rect) {
          for (var y = rect.top.toInt(); y < rect.bottom; y++) {
            for (var x = rect.left.toInt(); x < rect.right; x++) {
              final p = pixel(x, y);
              if (p[0] < 100 && p[1] < 100 && p[2] < 100) return true;
            }
          }
          return false;
        }

        expect(pixel(30, 20).take(3), everyElement(0));
        expect(pixel(50, 20), [255, 255, 255, 255]);
        expect(pixel(80, 70), [255, 0, 0, 255]);
        expect(pixel(30, 100), [0, 0, 255, 255]);
        expect(inkIn(const Rect.fromLTRB(10, 35, 60, 55)), isTrue);
        expect(inkIn(const Rect.fromLTRB(10, 60, 60, 85)), isTrue);
      } finally {
        image.dispose();
        codec.dispose();
      }
    },
  );

  test(
    'PDF loads every uncached background and preserves page dimensions',
    () async {
      final background = await solidPng(Colors.green);
      final file = XppFile(
        title: 'PDF notes',
        pages: [
          for (var i = 0; i < 3; i++)
            XppPage(
              pageSize: XppPageSize(width: 100 + i * 10, height: 140 + i * 10),
              background: XppBackgroundPdf(
                filename: 'source.pdf',
                page: i,
                onUnavailable: unavailable,
              ),
              layers: [XppLayer.empty()],
            ),
        ],
      );
      final requested = <int>[];
      final ctrl = CanvasController(
        autosaveEnabled: false,
        pdfRasterizer: (index) async {
          requested.add(index);
          return background;
        },
      )..file = file;
      expect(ctrl.pdfBackgrounds.isEmpty, isTrue);
      final bytes = await ctrl.buildPdfBytes();
      expect(requested, [0, 1, 2]);
      final pdf = latin1.decode(bytes);
      expect(pdf.startsWith('%PDF-'), isTrue);
      expect(RegExp(r'/Type\s*/Page\b').allMatches(pdf).length, 3);
      expect(
        RegExp(r'/MediaBox\s*\[0\s+0\s+120\s+160\]').hasMatch(pdf),
        isTrue,
      );
      expect(ctrl.pdfBackgrounds.isEmpty, isTrue);
      ctrl.dispose();
    },
  );

  test('PDF fails instead of silently dropping a missing background', () async {
    final file = XppFile.empty();
    file.pages!.first.background = XppBackgroundPdf(
      filename: 'missing.pdf',
      onUnavailable: unavailable,
    );
    await expectLater(
      buildNotesPdf(file, loadBackground: (_, _, _) async => null),
      throwsStateError,
    );
  });

  testWidgets(
    'save as XOPP round trips portable notes and updates destination only on success',
    (tester) async {
      BuildContext? context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final file = XppFile.empty(title: 'Note:/lezione')
        ..sourcePath = 'original.xopp';
      final png = await tester.runAsync(() => solidPng(Colors.red));
      file.pdfAttachments['source.pdf'] = Uint8List.fromList([1, 2, 3]);
      file.pages!.first.background = XppBackgroundPdf(
        filename: 'source.pdf',
        page: 2,
        onUnavailable: unavailable,
      );
      file.pages!.first.layers!.first.content!.addAll([
        line(const Offset(10, 10), const Offset(50, 10)),
        XppText(
          text: 'Appunti',
          offset: const Offset(10, 20),
          size: 12,
          color: Colors.black,
        ),
        XppImage(
          data: png!,
          topLeft: const Offset(10, 40),
          bottomRight: const Offset(30, 60),
        ),
        XppTexImage(
          text: 'x^2',
          topLeft: const Offset(40, 40),
          color: Colors.black,
        ),
      ]);
      FilePickerCross? captured;
      String? destination;
      final ctrl =
          CanvasController(
              autosaveEnabled: false,
              documentExporter: (data) async {
                captured = data;
                return destination;
              },
            )
            ..file = file
            ..hasUnsavedChanges = true;
      final cancelled = await tester.runAsync(
        () => ctrl.exportToXopp(context!),
      );
      expect(cancelled, isFalse);
      expect(file.sourcePath, 'original.xopp');
      expect(ctrl.hasUnsavedChanges, isTrue);
      expect(ctrl.savingFile, isFalse);
      expect(captured!.fileName, 'Note__lezione.xopp');
      destination = 'content://notes/saved.xopp';
      final saved = await tester.runAsync(() => ctrl.exportToXopp(context!));
      expect(saved, isTrue);
      expect(
        file.sourcePath,
        'original.xopp',
      ); // Export is not a verified reopenable origin.
      expect(ctrl.hasUnsavedChanges, isFalse);
      final parsed = await tester.runAsync(
        () => XppFile.fromFilePickerCross(captured!, null, unavailable),
      );
      expect(parsed!.pages!.first.layers!.first.content, hasLength(4));
      expect(parsed.pdfAttachments['source.pdf'], [1, 2, 3]);
      expect((parsed.pages!.first.background as XppBackgroundPdf).page, 2);
      expect(
        (parsed.pages!.first.layers!.first.content![1] as XppText).text,
        'Appunti',
      );
      expect(
        (parsed.pages!.first.layers!.first.content![2] as XppImage).data,
        png,
      );
      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
    },
  );

  testWidgets(
    'PDF cancellation and failure retain editable source and dirty state',
    (tester) async {
      BuildContext? context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      FilePickerCross? captured;
      final file = XppFile.empty(title: 'Appunti')
        ..sourcePath = 'original.xopp';
      final ctrl =
          CanvasController(
              autosaveEnabled: false,
              documentExporter: (data) async {
                captured = data;
                return null;
              },
            )
            ..file = file
            ..hasUnsavedChanges = true;
      await tester.runAsync(() => ctrl.exportToPdf(context!));
      expect(captured!.fileName, 'Appunti.pdf');
      expect(file.sourcePath, 'original.xopp');
      expect(ctrl.hasUnsavedChanges, isTrue);
      expect(ctrl.savingFile, isFalse);
      expect(find.text('PDF esportato'), findsNothing);
      file.pages!.clear();
      await tester.runAsync(() => ctrl.exportToPdf(context!));
      await tester.pump();
      expect(ctrl.hasUnsavedChanges, isTrue);
      expect(ctrl.savingFile, isFalse);
      expect(find.textContaining('Errore esportazione PDF:'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
    },
  );
}
