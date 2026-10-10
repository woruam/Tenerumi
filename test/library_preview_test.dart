import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:xournalpp/widgets/bounded_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/canvas_geometry_cache.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/src/library_metadata.dart';
import 'package:xournalpp/src/recent_documents.dart';
import 'package:xournalpp/widgets/document_library_card.dart';
import 'package:xournalpp/widgets/infinite_canvas.dart';

import 'document_storage_test.dart' show TestDocumentsProvider;

XppStroke line([double x = 20, double y = 40]) => XppStrokePen(
  color: Colors.black,
  points: [
    XppStrokePoint(x: x, y: y, width: 8),
    XppStrokePoint(x: x + 70, y: y, width: 8),
  ],
);
Future<FilePickerCross> unavailable(String? path) async =>
    throw StateError('Missing $path');

class CountingStroke extends XppStrokePen {
  int boundsCalls = 0;
  CountingStroke()
    : super(
        color: Colors.black,
        points: [
          XppStrokePoint(x: 20, y: 30, width: 4),
          XppStrokePoint(x: 90, y: 30, width: 4),
        ],
      );
  @override
  Rect? bounds() {
    boundsCalls++;
    return super.bounds();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a new blank note already has a UTC modification date', () {
    final before = DateTime.now().toUtc();
    final file = XppFile.empty();
    expect(file.modifiedAt, isNotNull);
    expect(file.modifiedAt!.isUtc, isTrue);
    expect(file.modifiedAt!.isBefore(before), isFalse);
    expect(file.modifiedAt!.isAfter(DateTime.now().toUtc()), isFalse);
  });

  test('modification date survives XOPP and the frozen snapshot', () async {
    final file = XppFile.empty()
      ..modifiedAt = DateTime.utc(2026, 10, 7, 13, 25);
    final snapshot = file.snapshot();
    file.modifiedAt = DateTime.utc(2026, 10, 8);
    final parsed = await XppFile.fromFilePickerCross(
      FilePickerCross(await snapshot.serializeSnapshotAsync()),
      null,
      unavailable,
    );
    expect(parsed.modifiedAt, DateTime.utc(2026, 10, 7, 13, 25));
    expect(snapshot.modifiedAt, parsed.modifiedAt);
  });

  test(
    'recent metadata preserves tags and favorites and refuses stale enrichment',
    () async {
      final file = XppFile.empty(title: 'Appunti')
        ..modifiedAt = DateTime.utc(2026, 10, 7);
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode([
          {
            'path': '/notes.xopp',
            'name': 'Vecchio',
            'tag': 'Scuola',
            'favorite': true,
            'preview': '',
          },
        ]),
      });
      final old = (await RecentDocuments.list()).single;
      await RecentDocuments.save(file, '/notes.xopp');
      await RecentDocuments.enrich(old, {
        'preview': 'obsolete',
        'modifiedAt': '2000-01-01',
      });
      final current = (await RecentDocuments.list()).single;
      expect(current['tag'], 'Scuola');
      expect(current['favorite'], true);
      expect(current['name'], 'Appunti');
      expect(current['modifiedAt'], file.modifiedAt!.toIso8601String());
      expect(current['preview'], isNot('obsolete'));
    },
  );

  test(
    'thumbnail is bounded, includes negative ink and ignores hidden layers',
    () async {
      final file = XppFile.empty();
      file.pages!.first.infinite = true;
      file.pages!.first.layers = [
        XppLayer(content: [line(-100, -80)]),
        XppLayer(visible: false, content: [line(100000, 100000)]),
      ];
      final ctrl = CanvasController(autosaveEnabled: false)..file = file;
      addTearDown(ctrl.dispose);
      final png = await ctrl.buildPreviewBytes();
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      try {
        expect(image.width, lessThanOrEqualTo(320));
        expect(image.height, lessThanOrEqualTo(320));
        final data = (await image.toByteData())!.buffer.asUint8List();
        expect(data.where((v) => v == 0).length, greaterThan(0));
        expect(image.width, greaterThan(100));
        expect(
          (file.pages!.first.layers!.first.content!.first as XppStroke)
              .points!
              .first
              .x,
          -100,
        );
      } finally {
        image.dispose();
        codec.dispose();
      }
    },
  );

  test('thumbnail loads the PDF background of an unmounted page', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 10, 10),
      Paint()..color = Colors.green,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(10, 10);
    final background = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
    var calls = 0;
    final file = XppFile.empty();
    file.pages!.first.background = XppBackgroundPdf(
      filename: 'source.pdf',
      onUnavailable: unavailable,
    );
    final ctrl = CanvasController(
      autosaveEnabled: false,
      pdfRasterizer: (index) async {
        calls++;
        expect(index, 0);
        return background;
      },
    )..file = file;
    addTearDown(ctrl.dispose);
    final png = await ctrl.buildPreviewBytes();
    expect(calls, 1);
    expect(png.length, greaterThan(100));
    expect(ctrl.pageStackKeys, isEmpty);
  });

  test('named autosave updates the home thumbnail, date and existing user metadata', () async {
    final directory = await Directory.systemTemp.createTemp('osipp-home-auto-');
    final path = '${directory.path}/notes.xopp';
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = TestDocumentsProvider(directory.path);
    final file = XppFile.empty(title: 'Lezione')..sourcePath = path;
    final ctrl = CanvasController()..file = file;
    try {
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode([
          {
            'name': 'Lezione',
            'path': path,
            'tag': 'Lavoro',
            'favorite': true,
            'preview': '',
          },
        ]),
      });
      ctrl.addNewContent(0, line());
      await ctrl.flushAutosave();
      final current = (await RecentDocuments.list()).single;
      expect(hasDocumentPreview(current['preview']), isTrue);
      expect(DateTime.parse(current['modifiedAt'] as String), file.modifiedAt);
      expect(current['tag'], 'Lavoro');
      expect(current['favorite'], isTrue);
      final parsed = await XppFile.fromFilePickerCross(
        FilePickerCross(await File(path).readAsBytes()),
        null,
        unavailable,
      );
      expect(hasDocumentPreview(base64Encode(parsed.previewImage!)), isTrue);
      expect(parsed.modifiedAt, file.modifiedAt);
      await ctrl.discardRecovery();
    } finally {
      ctrl.dispose();
      PathProviderPlatform.instance = previous;
      await directory.delete(recursive: true);
    }
  });

  test('legacy metadata is generated lazily once and persisted without opening an editor', () async {
    final directory = await Directory.systemTemp.createTemp(
      'osipp-home-legacy-',
    );
    final path = '${directory.path}/notes.xopp';
    final file = XppFile.empty()..modifiedAt = DateTime.utc(2026, 9, 10);
    file.pages!.first.layers!.first.content!.add(line());
    await File(path).writeAsBytes(await file.toUint8ListAsync());
    final entry = <String, dynamic>{
      'name': 'Vecchia nota',
      'path': path,
      'preview': base64Encode(kTransparentImage),
    };
    SharedPreferences.setMockInitialValues({
      PreferencesKeys.kRecentFiles: jsonEncode([entry]),
    });
    try {
      final result = await LibraryMetadata.load(entry, () => true);
      expect(result!['modifiedAt'], file.modifiedAt!.toIso8601String());
      expect(hasDocumentPreview(result['preview']), isTrue);
      final current = (await RecentDocuments.list()).single;
      expect(current['preview'], result['preview']);
      expect(current['name'], 'Vecchia nota');
      expect(await LibraryMetadata.load(entry, () => true), same(result));
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('hidden queued cards do not read their document', () async {
    final result = await LibraryMetadata.load({
      'path': '/should-not-open.xopp',
    }, () => false);
    expect(result, isNull);
  });

  test(
    'Android modification dates are queried without reading the document',
    () async {
      const channel = MethodChannel('online.xournal.mobile/documents');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return DateTime.utc(2026, 10, 7).millisecondsSinceEpoch;
          });
      try {
        expect(
          await FilePickerCross.lastModified('content://documents/1'),
          DateTime.utc(2026, 10, 7),
        );
        expect(calls, ['lastModified']);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
  );

  test(
    'geometry cache computes bounds once per revision and reflects moved ink',
    () {
      final stroke = CountingStroke();
      final cache = CanvasGeometryCache();
      cache.updateRevision(1);
      final initial = cache.bounds(stroke)!;
      for (var i = 0; i < 100; i++) {
        expect(cache.bounds(stroke), initial);
      }
      expect(stroke.boundsCalls, 1);
      stroke.translate(const Offset(300, 200));
      cache.updateRevision(2);
      expect(cache.bounds(stroke), initial.shift(const Offset(300, 200)));
      expect(stroke.boundsCalls, 2);
    },
  );

  testWidgets(
    'home cards show an image and readable last-modified date on a phone',
    (tester) async {
      final modified = DateTime.utc(2026, 10, 7, 12, 30).toIso8601String();
      final ctrl = CanvasController(autosaveEnabled: false)
        ..file = XppFile.empty();
      ctrl.file!.pages!.first.layers!.first.content!.add(line());
      final png = (await tester.runAsync(ctrl.buildPreviewBytes))!;
      var opened = 0;
      var loaded = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 172,
                height: 190,
                child: DocumentLibraryCard(
                  entry: {
                    'name': 'Appunti',
                    'path': '/notes.xopp',
                    'tag': 'Scuola',
                    'preview': base64Encode(png),
                    'modifiedAt': modified,
                  },
                  fallbackIcon: Icons.description,
                  onTap: () => opened++,
                  metadataLoader: (_, _) async {
                    loaded++;
                    return null;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Appunti'), findsOneWidget);
      expect(find.text(documentModifiedLabel(modified)), findsOneWidget);
      expect(find.byType(BoundedImage), findsOneWidget);
      expect(loaded, 0);
      expect(
        tester.widget<BoundedImage>(find.byType(BoundedImage)).bytes,
        isNotEmpty,
      );
      await tester.tap(find.byType(DocumentLibraryCard));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
    },
  );

  testWidgets(
    'missing and transparent previews fall back and use a lazy loader',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 200,
              child: DocumentLibraryCard(
                entry: {
                  'name': 'Vecchia nota',
                  'path': '/legacy.xopp',
                  'preview': base64Encode(kTransparentImage),
                },
                fallbackIcon: Icons.description,
                onTap: () {},
                metadataLoader: (_, visible) async {
                  expect(visible(), isTrue);
                  calls++;
                  return {
                    'modifiedAt': DateTime.utc(2026, 10, 7).toIso8601String(),
                  };
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(Icon), findsOneWidget);
      expect(find.textContaining('Modificato il'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('invalid preview and missing date do not break home cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 200,
            child: DocumentLibraryCard(
              entry: {'name': 'Nota', 'preview': 'not base64!'},
              fallbackIcon: Icons.description,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Data non disponibile'), findsOneWidget);
    expect(find.byType(Icon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'panning reuses geometry; an edited stroke invalidates the cache',
    (tester) async {
      final stroke = CountingStroke();
      final ctrl = CanvasController(autosaveEnabled: false)
        ..file = XppFile.empty();
      ctrl.file!.pages!.first.layers!.first.content!.add(stroke);
      final transform = TransformationController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InfiniteCanvas(canvas: ctrl, transform: transform),
          ),
        ),
      );
      final initial = stroke.boundsCalls;
      for (var i = 0; i < 20; i++) {
        transform.value = Matrix4.identity()..translate(i.toDouble(), 0.0);
        await tester.pump();
      }
      expect(stroke.boundsCalls, initial);
      stroke.translate(const Offset(200, 100));
      ctrl.markContentChanged(0);
      await tester.pump();
      expect(stroke.boundsCalls, initial + 1);
      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
      transform.dispose();
    },
  );
}
