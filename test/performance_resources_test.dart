import 'dart:async';

import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:pdfx/src/renderer/interfaces/platform.dart';
import 'package:xournalpp/src/XppBackground.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/decoded_image_cache.dart';
import 'package:xournalpp/src/autosave_store.dart';
import 'package:xournalpp/src/workspace_session.dart';
import 'package:xournalpp/src/responsive_hash.dart';
import 'package:xournalpp/src/PdfImage.dart';
import 'package:crypto/crypto.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/document_export.dart';
import 'package:xournalpp/widgets/virtual_page_column.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

import 'canvas_workspace_test.dart' show stroke, DocumentsProvider, unavailable;

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'document_export_test.dart' show solidPng;

class _PdfBackend extends PdfxPlatform {
  final Uint8List png;
  final List<_PdfDocument> documents = [];
  Completer<pdfx.PdfDocument>? pending;
  _PdfBackend(this.png);
  @override
  Future<pdfx.PdfDocument> openData(
    FutureOr<Uint8List> data, {
    String? password,
  }) async {
    final doc = _PdfDocument(png);
    documents.add(doc);
    return pending?.future ?? Future.value(doc);
  }

  @override
  Future<pdfx.PdfDocument> openFile(String path, {String? password}) =>
      openData(png);
  @override
  Future<pdfx.PdfDocument> openAsset(String path, {String? password}) =>
      openData(png);
}

class _PdfDocument extends pdfx.PdfDocument {
  final Uint8List png;
  int pageOpens = 0, pageCloses = 0, documentCloses = 0;
  final renderedAreas = <double>[];
  _PdfDocument(this.png) : super(sourceName: 'test', id: 'test', pagesCount: 3);
  @override
  Future<pdfx.PdfPage> getPage(
    int number, {
    bool autoCloseAndroid = false,
  }) async {
    expect(isClosed, isFalse);
    expect(pageOpens, pageCloses);
    pageOpens++;
    return _PdfPage(this, number, png);
  }

  @override
  Future<void> close() async {
    expect(pageOpens, pageCloses);
    documentCloses++;
    isClosed = true;
  }
}

class _PdfPage extends pdfx.PdfPage {
  final Uint8List png;
  _PdfPage(_PdfDocument doc, int number, this.png)
    : super(
        document: doc,
        id: 'page',
        pageNumber: number,
        width: 595,
        height: 842,
        autoCloseAndroid: false,
      );
  @override
  Future<pdfx.PdfPageImage?> render({
    required double width,
    required double height,
    pdfx.PdfPageImageFormat format = pdfx.PdfPageImageFormat.jpeg,
    String? backgroundColor,
    Rect? cropRect,
    int quality = 100,
    bool forPrint = false,
    bool removeTempFile = true,
  }) async {
    (document as _PdfDocument).renderedAreas.add(width * height);
    return _PdfImage(png, pageNumber);
  }

  @override
  Future<void> close() async {
    (document as _PdfDocument).pageCloses++;
    isClosed = true;
  }

  @override
  Future<pdfx.PdfPageTexture> createTexture() => throw UnimplementedError();
}

class _PdfImage extends pdfx.PdfPageImage {
  _PdfImage(Uint8List data, int number)
    : super(
        id: 'image',
        pageNumber: number,
        width: 8,
        height: 8,
        bytes: data,
        format: pdfx.PdfPageImageFormat.png,
        quality: 100,
      );
}

void main() {
  test('Android PDF metadata uses one reply and preserves different page dimensions', () async {
    final previous = PdfxPlatform.instance;
    final backend = _PdfBackend(await solidPng(Colors.white));
    PdfxPlatform.instance = backend;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const metadata = MethodChannel('online.xournal.mobile/pdf-metadata');
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(metadata, (call) async {
          calls++;
          expect(call.method, 'pageSizes');
          expect(call.arguments['documentId'], 'test');
          return [100.0, 200.0, 300.0, 400.0, 500.0, 600.0];
        });
    try {
      final file = await XppFile.importPdf(
        pdf: FilePickerCross(Uint8List.fromList([1])),
      );
      expect(calls, 1);
      expect(file.pages!.map((p) => p.pageSize!.width), [100, 300, 500]);
      expect(file.pages!.map((p) => p.pageSize!.height), [200, 400, 600]);
      expect(file.pages!.map((p) => (p.background as XppBackgroundPdf).page), [
        0,
        1,
        2,
      ]);
      expect(backend.documents.single.pageOpens, 0);
      expect(backend.documents.single.documentCloses, 1);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(metadata, null);
      debugDefaultTargetPlatformOverride = null;
      PdfxPlatform.instance = previous;
    }
  });
  test(
    'Android missing metadata channel falls back and closes all pages',
    () async {
      final previous = PdfxPlatform.instance;
      final backend = _PdfBackend(await solidPng(Colors.white));
      PdfxPlatform.instance = backend;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const metadata = MethodChannel('online.xournal.mobile/pdf-metadata');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(metadata, (_) async {
            throw MissingPluginException();
          });
      try {
        final sizes = await pdfPageSizes(
          FilePickerCross(Uint8List.fromList([1])),
        );
        expect(sizes, hasLength(3));
        expect(backend.documents.single.pageOpens, 3);
        expect(backend.documents.single.pageCloses, 3);
        expect(backend.documents.single.documentCloses, 1);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(metadata, null);
        debugDefaultTargetPlatformOverride = null;
        PdfxPlatform.instance = previous;
      }
    },
  );
  test(
    'invalid or incomplete PDF metadata rejects and closes its source',
    () async {
      final previous = PdfxPlatform.instance;
      final backend = _PdfBackend(await solidPng(Colors.white));
      PdfxPlatform.instance = backend;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const metadata = MethodChannel('online.xournal.mobile/pdf-metadata');
      try {
        for (final values in [
          [100.0, 200.0],
          [double.nan, 200.0, 300.0, 400.0, 500.0, 600.0],
        ]) {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(metadata, (_) async => values);
          await expectLater(
            pdfPageSizes(FilePickerCross(Uint8List.fromList([1]))),
            throwsFormatException,
          );
          expect(backend.documents.last.pageOpens, 0);
          expect(backend.documents.last.documentCloses, 1);
        }
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(metadata, null);
        debugDefaultTargetPlatformOverride = null;
        PdfxPlatform.instance = previous;
      }
    },
  );
  test('parallel PDF requests transfer only one document at a time', () async {
    final previous = PdfxPlatform.instance;
    final backend = _PdfBackend(await solidPng(Colors.white));
    final pending = Completer<pdfx.PdfDocument>();
    backend.pending = pending;
    PdfxPlatform.instance = backend;
    try {
      final first = openPdfData(Uint8List.fromList([1]));
      final second = openPdfData(Uint8List.fromList([2]));
      await Future<void>.delayed(Duration.zero);
      expect(backend.documents, hasLength(1));
      backend.pending = null;
      pending.complete(backend.documents.single);
      final opened = await Future.wait([first, second]);
      expect(backend.documents, hasLength(2));
      expect(identical(opened.first, opened.last), isFalse);
      for (final document in opened) {
        await document.close();
      }
    } finally {
      PdfxPlatform.instance = previous;
    }
  });
  test(
    'streamed save preserves legacy XML, large PDF bytes and metadata',
    () async {
      final bytes = Uint8List.fromList(
        List.generate(2 * 1024 * 1024 + 7, (i) => i % 251),
      );
      final file = XppFile.empty(title: 'Legacy PDF', tag: 'A & B');
      file.pdfAttachments['old & "quoted".pdf'] = bytes;
      file.pages!.first.background = XppBackgroundPdf(
        filename: 'old & "quoted".pdf',
        page: 0,
        onUnavailable: unavailable,
      );
      file.pages!.first.layers!.first.content!.add(stroke());
      final expected = file.toXmlString();
      final encoded = await file.toUint8ListAsync();
      expect(utf8.decode(GZipDecoder().decodeBytes(encoded)), expected);
      final reopened = await XppFile.fromFilePickerCross(
        FilePickerCross(encoded),
        null,
        unavailable,
      );
      expect(reopened.pdfAttachments.values.single, bytes);
      expect(reopened.tag, file.tag);
      expect(reopened.pages!.first.layers!.first.content, hasLength(1));
    },
  );

  test(
    'large attachment hashes yield to the event loop and retain SHA-256',
    () async {
      final bytes = Uint8List(2 * 1024 * 1024 + 7)..[100] = 17;
      var inputHandled = false;
      Timer.run(() => inputHandled = true);
      final hash = await responsiveHash(bytes);
      expect(inputHandled, isTrue);
      expect(hash, sha256.convert(bytes).toString());
    },
  );

  test('PDF imported into a tab keeps its workspace identity and is immediately recoverable', () async {
    final previous = PdfxPlatform.instance;
    final backend = _PdfBackend(await solidPng(Colors.white));
    PdfxPlatform.instance = backend;
    final selected = FilePickerCross(Uint8List.fromList([1, 2, 3]));
    final path = await selected.saveToPath(path: 'import-recovery-test.pdf');
    final tab = XppFile.empty(title: 'PDF');
    final controller = CanvasController(autosaveEnabled: false)..init(tab);
    var renderedAfterCheckpoint = false;
    controller.addListener(() {
      if (!controller.savingFile &&
          controller.file!.pdfAttachments.isNotEmpty) {
        renderedAfterCheckpoint = true;
      }
    });
    try {
      await controller.loadPdfFresh(path, 'Imported PDF');
      expect(identical(controller.file, tab), isTrue);
      expect(tab.pages, hasLength(3));
      expect(renderedAfterCheckpoint, isTrue);
      final entry = (await AutosaveStore.list()).singleWhere(
        (e) => e['key'] == tab.recoveryKey,
      );
      final recovered = await AutosaveStore.restore(entry);
      expect(recovered.pdfAttachments.values.single, [1, 2, 3]);
      expect(recovered.pages, hasLength(3));
      await WorkspaceSession.save({
        'tabs': [
          {'key': tab.recoveryKey, 'localId': tab.localId, 'title': tab.title},
        ],
      });
      final workspace = await WorkspaceSession.restore();
      expect(workspace!.files.single.pdfAttachments.values.single, [1, 2, 3]);
      expect(backend.documents.single.documentCloses, 1);
      expect(backend.documents.single.renderedAreas, isEmpty);
    } finally {
      controller.dispose();
      PdfxPlatform.instance = previous;
    }
  });

  test('PDF size import opens and closes one source for all pages', () async {
    final previous = PdfxPlatform.instance;
    final backend = _PdfBackend(await solidPng(Colors.white));
    PdfxPlatform.instance = backend;
    try {
      final file = await XppFile.importPdf(
        pdf: FilePickerCross(Uint8List.fromList([1])),
      );
      expect(file.pages, hasLength(3));
      expect(backend.documents, hasLength(1));
      expect(backend.documents.single.pageCloses, 3);
      expect(backend.documents.single.documentCloses, 1);
    } finally {
      PdfxPlatform.instance = previous;
    }
  });
  test(
    'visible pages requested during import render after recovery is committed',
    () async {
      final previous = PdfxPlatform.instance;
      final backend = _PdfBackend(await solidPng(Colors.white));
      final pending = Completer<pdfx.PdfDocument>();
      backend.pending = pending;
      PdfxPlatform.instance = backend;
      final tab = XppFile.empty(title: 'Queued viewport');
      var renders = 0;
      late final CanvasController controller;
      controller = CanvasController(
        autosaveEnabled: false,
        pdfRasterizer: (_) async {
          final entries = await AutosaveStore.list();
          expect(entries.any((e) => e['key'] == tab.recoveryKey), isTrue);
          expect(controller.pdfImportPending, isFalse);
          renders++;
          return backend.png;
        },
      )..init(tab);
      try {
        final path = await FilePickerCross(Uint8List.fromList([1, 2, 3]))
            .saveToPath(path: 'queued-import-test.pdf');
        final loading = controller.loadPdfFresh(path, 'Queued viewport');
        while (backend.documents.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        controller.setVisiblePdfPages({0});
        expect(controller.pdfImportPending, isTrue);
        expect(renders, 0);
        backend.pending = null;
        pending.complete(backend.documents.single);
        await loading;
        for (var i = 0; renders == 0 && i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(renders, 1);
      } finally {
        controller.dispose();
        PdfxPlatform.instance = previous;
      }
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    '10000 pages: pixel pans reuse page widgets and coalesce range notifications',
    (tester) async {
      final transform = TransformationController();
      int builds = 0, ranges = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                minHeight: 0,
                maxHeight: double.infinity,
                child: VirtualPageColumn(
                  transform: transform,
                  viewport: const Size(800, 600),
                  width: 750,
                  heights: List.filled(10000, 1000),
                  pageBuilder: (i) {
                    builds++;
                    return Text('Page $i');
                  },
                  onVisiblePages: (_) => ranges++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final initial = builds, initialRanges = ranges;
      final watch = Stopwatch()..start();
      for (var i = 1; i <= 300; i++) {
        transform.value = Matrix4.translationValues(0, -i * .2, 0);
        await tester.pump();
      }
      watch.stop();
      final panBuilds = builds - initial, panRanges = ranges - initialRanges;
      expect(builds, initial);
      expect(ranges, initialRanges);
      transform.value = Matrix4.translationValues(0, -10250, 0);
      await tester.pump();
      await tester.pump();
      expect(find.text('Page 10'), findsOneWidget);
      expect(builds, greaterThan(initial));
      await tester.runAsync(
        () => File('docs/validation/performance-scroll.json').writeAsString(
          jsonEncode({
            'environment':
                'Flutter desktop widget test, not Android frame timing',
            'pages': 10000,
            'panUpdates': 300,
            'initialPageBuilds': initial,
            'additionalPageBuildsDuringPan': panBuilds,
            'additionalRangeNotificationsDuringPan': panRanges,
            'testElapsedMs': watch.elapsedMilliseconds,
          }),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      transform.dispose();
    },
  );
  test(
    'XOPP fast gzip is lossless and benchmarks compression separately from XML',
    () async {
      final file = XppFile.empty(title: 'Stress');
      file.autoGeneratePages = false;
      for (var page = 0; page < 25; page++) {
        if (page > 0) file.pages!.add(XppPage.empty());
        for (var i = 0; i < 100; i++)
          file.pages![page].layers!.first.content!.add(
            stroke(i.toDouble(), i.toDouble()),
          );
      }
      final input = utf8.encode(file.toXmlString());
      final measurements = <String, Object>{
        'environment':
            'desktop JIT, synthetic 25 pages/2500 strokes, compression only',
      };
      Uint8List? fast;
      for (final level in [6, 1]) {
        final times = <int>[];
        Uint8List? bytes;
        GZipEncoder().encodeBytes(input, level: level); // warmup
        for (var attempt = 0; attempt < 5; attempt++) {
          final clock = Stopwatch()..start();
          bytes = GZipEncoder().encodeBytes(input, level: level);
          clock.stop();
          times.add(clock.elapsedMicroseconds);
        }
        times.sort();
        measurements['level$level'] = {
          'medianMicros': times[2],
          'bytes': bytes!.length,
        };
        if (level == 1) fast = bytes;
      }
      expect(GZipDecoder().decodeBytes(fast!), input);
      expect(GZipDecoder().decodeBytes(file.toUint8List()!), input);
      final parsed = await XppFile.fromFilePickerCross(
        FilePickerCross(fast, path: 'stress.xopp'),
        null,
        unavailable,
      );
      expect(parsed.pages, hasLength(25));
      expect(parsed.pages!.last.layers!.first.content, hasLength(100));
      await File('docs/validation/performance-xopp.json')
          .writeAsString(jsonEncode(measurements));
    },
  );
  test('decoded image resources are released with owners and late decode cannot resurrect them', () async {
    final png = await solidPng(Colors.red);
    final cache = DecodedImageCache(
      maxEntries: 1,
      maxBytes: 2048,
      maxDimension: 16,
    );
    final owner = Object();
    cache.retain(owner, [png]);
    cache.lookup(png);
    for (var i = 0; cache.lookup(png) == null && i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final image = cache.lookup(png)!;
    expect(cache.byteCount, greaterThan(0));
    cache.release(owner);
    expect(cache.byteCount, 0);
    expect(cache.entryCount, 0);
    expect(image.debugDisposed, isTrue);
    final other = Object();
    cache.retain(other, [png]);
    cache.lookup(png);
    cache.release(other);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(cache.byteCount, 0);
    expect(cache.entryCount, 0);
    cache.dispose();
  });
  testWidgets(
    'image completion repaints a stationary page and unmount releases its native cache',
    (tester) async {
      final png = (await tester.runAsync(() => solidPng(Colors.red)))!;
      final file = XppFile.empty();
      file.pages!.first.pageSize = XppPageSize(width: 100, height: 100);
      file.pages!.first.layers!.first.content!.add(
        XppImage(
          data: png,
          topLeft: const Offset(10, 10),
          bottomRight: const Offset(80, 80),
        ),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 100,
                height: 100,
                child: XppPageStack(page: file.pages!.first),
              ),
            ),
          ),
        ),
      );
      for (
        var i = 0;
        DecodedImageCache.shared.lookup(png) == null && i < 30;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pump();
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final offset = (50 * image.width + 50) * 4;
          expect(data.getUint8(offset), greaterThan(200));
          expect(data.getUint8(offset + 1), lessThan(80));
        } finally {
          image.dispose();
        }
      });
      await tester.pumpWidget(const SizedBox());
      expect(DecodedImageCache.shared.byteCount, 0);
    },
  );
  testWidgets(
    'manual save reuses current checkpoint and reserializes after edits',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('osi-checkpoint-'),
      ))!;
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = DocumentsProvider(directory.path);
      final ctrl = CanvasController()..init(XppFile.empty(title: 'Reuse'));
      BuildContext? context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );
      try {
        ctrl.addNewContent(0, stroke());
        await tester.runAsync(() => ctrl.flushAutosave());
        final entry = (await tester.runAsync(AutosaveStore.list))!.single;
        final secured = (await tester.runAsync(
          () => AutosaveStore.readBytes(entry),
        ))!;
        expect(await tester.runAsync(() => ctrl.saveFile(context!)), isTrue);
        final saved = (await tester.runAsync(
          () => FilePickerCross.fromInternalPath(path: ctrl.file!.sourcePath!),
        ))!;
        expect(
          saved.toUint8List(),
          secured,
        ); // Byte-for-byte reuse, not a new gzip.
        final savedFile = File(ctrl.file!.sourcePath!);
        final originalTime = DateTime.utc(2000);
        await tester.runAsync(() => savedFile.setLastModified(originalTime));
        expect(await tester.runAsync(() => ctrl.saveFile(context!)), isTrue);
        expect(
          (await tester.runAsync(savedFile.lastModified))!.toUtc(),
          originalTime,
        ); // Unchanged saves verify the bytes without overwriting the file.
        ctrl.addNewContent(0, stroke(100, 100));
        expect(await tester.runAsync(() => ctrl.saveFile(context!)), isTrue);
        final raw = (await tester.runAsync(
          () => FilePickerCross.fromInternalPath(path: ctrl.file!.sourcePath!),
        ))!;
        final parsed = (await tester.runAsync(
          () => XppFile.fromFilePickerCross(raw, null, unavailable),
        ))!;
        expect(parsed.pages!.first.layers!.first.content, hasLength(2));
      } finally {
        await tester.pumpWidget(const SizedBox());
        ctrl.dispose();
        await tester.runAsync(() => ctrl.discardRecovery());
        PathProviderPlatform.instance = previous;
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    },
  );
  test('checkpoint reader rejects mismatched timestamps', () async {
    SharedPreferences.setMockInitialValues({
      AutosaveStore.indexKey: jsonEncode([
        {
          'id': 'note',
          'time': 1,
          'modifiedAt': '2020-01-01T00:00:00.000Z',
          'path': 'never-read.xopp',
        },
      ]),
    });
    expect(
      await AutosaveStore.checkpointBytes('note', DateTime.utc(2021)),
      isNull,
    );
  });
  test('PDF export snapshots are complete and retain page order through background worker', () async {
    final file = XppFile.empty(title: 'Complete');
    file.autoGeneratePages = false;
    file.pages!.first.layers!.first.content!.add(stroke());
    file.pages!.add(
      XppPage.empty()..pageSize = XppPageSize(width: 300, height: 400),
    );
    final bytes = await buildNotesPdf(
      file,
      loadBackground: (_, _) async => null,
    );
    final text = latin1.decode(bytes);
    expect(text, contains('%PDF-'));
    expect(text, contains('/Count 2'));
    expect(file.pages!.last.pageSize!.width, 300);
  });
  test(
    'PDF viewing/export open the source once and close every native resource',
    () async {
      final previous = PdfxPlatform.instance;
      final backend = _PdfBackend(await solidPng(Colors.white));
      PdfxPlatform.instance = backend;
      final file = XppFile.empty()..autoGeneratePages = false;
      file.pdfAttachments['source.pdf'] = Uint8List.fromList([1]);
      file.pages = List.generate(
        3,
        (i) => XppPage.empty()
          ..pageSize = XppPageSize(width: 100, height: 100)
          ..background = XppBackgroundPdf(
            filename: 'source.pdf',
            page: i,
            onUnavailable: unavailable,
          ),
      );
      final ctrl = CanvasController(autosaveEnabled: false)..init(file);
      try {
        ctrl.setVisiblePdfPages({0, 1, 2});
        for (
          var i = 0;
          (backend.documents.isEmpty ||
                  backend.documents.first.pageCloses < 3) &&
              i < 100;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(backend.documents, hasLength(1));
        expect(backend.documents.single.pageCloses, 3);
        for (final area in backend.documents.single.renderedAreas) {
          expect(area, closeTo(4000000 / 3, 1));
        }
        ctrl.suspendPdfRendering();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(backend.documents.single.documentCloses, 1);
        await ctrl.buildPdfBytes();
        expect(backend.documents, hasLength(2));
        expect(backend.documents.last.pageCloses, 3);
        for (final area in backend.documents.last.renderedAreas) {
          expect(area, closeTo(4000000, 1));
        }
        expect(backend.documents.last.documentCloses, 1);
        backend.pending = Completer<pdfx.PdfDocument>();
        ctrl.setVisiblePdfPages({0});
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final opening = backend.documents.last;
        ctrl.suspendPdfRendering();
        backend.pending!.complete(opening);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(opening.pageOpens, 0);
        expect(opening.documentCloses, 1);
      } finally {
        ctrl.dispose();
        PdfxPlatform.instance = previous;
      }
    },
  );
}
