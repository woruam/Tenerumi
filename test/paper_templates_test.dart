import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/document_export.dart';
import 'package:xournalpp/src/paper_template.dart';
import 'package:xournalpp/widgets/add_page_button.dart';
import 'package:xournalpp/widgets/infinite_canvas.dart';

Future<FilePickerCross> unavailable(String? _) async =>
    throw StateError('Missing');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Smith labels are on their normalized resistance/reactance curves', () {
    final labels = smithChartLabels();
    expect(
      labels.map((label) => label.text),
      containsAll([
        '0',
        '0.2',
        '0.5',
        '1',
        '2',
        '5',
        '∞',
        '+j0.2',
        '−j0.2',
        '+j5',
        '−j5',
      ]),
    );
    for (final label in labels) {
      final point = label.normalizedPoint;
      if (label.reactance) {
        expect(point.distance, closeTo(1, 1e-12));
        expect(
          (point - Offset(1, -1 / label.value)).distance,
          closeTo(1 / label.value.abs(), 1e-12),
        );
        expect(point.dy.sign, -label.value.sign);
      } else if (label.value.isFinite) {
        final center = Offset(label.value / (1 + label.value), 0);
        expect(
          (point - center).distance,
          closeTo(1 / (1 + label.value), 1e-12),
        );
      }
    }
    expect(smithChartNormalizationLegend, contains('Z/Z0'));
  });

  testWidgets('squared paper has consistent 10mm finite and infinite cells', (
    tester,
  ) async {
    expect(graphPaperSpacing, closeTo(72 * 10 / 25.4, 1e-10));
    final file = XppFile.empty(
      pageSize: XppPageSize(width: 100, height: 100),
      template: (size) => XppBackgroundSolidGraph(size: size),
    );
    final ctrl = CanvasController(autosaveEnabled: false)..init(file);
    final transform = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 100,
          height: 100,
          child: InfiniteCanvas(canvas: ctrl, transform: transform),
        ),
      ),
    );
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<CustomPainter>()
        .first;
    await tester.runAsync(() async {
      Future<int> redAt(bool infinite, int x, int y) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        if (infinite) {
          painter.paint(canvas, const Size(100, 100));
        } else {
          paintPaperBackground(
            canvas,
            const Size(100, 100),
            file.pages!.single.background,
          );
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 100);
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          return pixels[(y * 100 + x) * 4];
        } finally {
          image.dispose();
          picture.dispose();
        }
      }

      for (final infinite in [false, true]) {
        // A line lies at 28.35pt; the midpoint of the cell is clean paper.
        expect(await redAt(infinite, 28, 14), lessThan(255));
        expect(await redAt(infinite, 14, 14), 255);
        expect(await redAt(infinite, 56, 14), lessThan(255));
      }
    });
    await tester.pumpWidget(const SizedBox());
    ctrl.dispose();
    transform.dispose();
  });

  testWidgets('render labeled Smith chart on portrait square and dark paper', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final font = FontLoader('Open Sans')
        ..addFont(rootBundle.load('fonts/Open Sans/OpenSans-Regular.ttf'));
      await font.load();
      final output = Directory('build/visual-validation')
        ..createSync(recursive: true);
      for (final (name, size, color) in [
        ('smith-a4', XppPageSize.a4, Colors.white),
        ('smith-square', XppPageSize(width: 200, height: 200), Colors.white),
        ('smith-dark', XppPageSize.a4, const Color(0xff0a0a0a)),
      ]) {
        final file = XppFile.empty(
          pageSize: size,
          template: (size) => XppBackgroundSmith(size: size, color: color),
        );
        final png = await rasterizeExportPage(file.pages!.single, maxScale: 2);
        await File('${output.path}/$name.png').writeAsBytes(png);
        expect(png.length, greaterThan(1000));
      }
    });
  });

  test(
    'custom page does not change creation paper, including after round trip',
    () async {
      final file = XppFile.empty(
        template: (size) => XppBackgroundSolidGraph(size: size),
      );
      final ctrl = CanvasController()..init(file);
      addTearDown(ctrl.dispose);
      ctrl.insertPage(
        after: true,
        paper: const PaperSettings(
          template: PaperTemplate.smith,
          width: 419.53,
          height: 595.28,
        ),
      );
      ctrl.addPage();
      expect(file.pages![1].background, isA<XppBackgroundSmith>());
      expect(file.pages![1].pageSize!.width, 419.53);
      expect(file.pages![2].background, isA<XppBackgroundSolidGraph>());
      expect(file.pages![2].pageSize!.width, 595.28);
      final restored = await XppFile.fromFilePickerCross(
        FilePickerCross(await file.toUint8ListAsync()),
        null,
        unavailable,
      );
      expect(restored.importWarnings, isEmpty);
      expect(restored.pages![1].background, isA<XppBackgroundSmith>());
      expect(restored.defaultPaper.template, PaperTemplate.graph);
      expect(
        restored.snapshot().defaultPaper.toMap(),
        file.defaultPaper.toMap(),
      );
      final reopened = CanvasController()..init(restored);
      addTearDown(reopened.dispose);
      reopened.goToPage(1);
      reopened.addPage();
      expect(restored.pages![2].background, isA<XppBackgroundSolidGraph>());
      expect(restored.pages![2].pageSize!.width, 595.28);
    },
  );

  test('legacy notes derive default from first page; PDF defaults to white', () async {
    final xml =
        '''<xournal><page width="400" height="600"><background type="solid" style="graph" color="white"/><layer/></page><page width="200" height="300"><background type="solid" style="lined" color="white"/><layer/></page></xournal>''';
    final file = await XppFile.fromFilePickerCross(
      FilePickerCross(
        Uint8List.fromList(GZipEncoder().encodeBytes(utf8.encode(xml))),
      ),
      null,
      unavailable,
    );
    final ctrl = CanvasController()..init(file);
    addTearDown(ctrl.dispose);
    ctrl.goToPage(1);
    ctrl.addPage();
    expect(file.pages!.last.background, isA<XppBackgroundSolidGraph>());
    expect(file.pages!.last.pageSize!.width, 400);
    final pdf = XppFile(
      pages: [
        XppPage.empty(
          pageSize: XppPageSize.a4,
          template: XppBackgroundPdf(
            onUnavailable: unavailable,
            filename: 'pdf',
            page: 0,
          ),
        ),
      ],
    );
    expect(pdf.defaultPaper.template, PaperTemplate.plain);
    expect(pdf.defaultPaper.color, Colors.white);
  });

  testWidgets(
    'long press chooses paper and size; next short press restores original',
    (tester) async {
      final ctrl = CanvasController(autosaveEnabled: false)
        ..init(
          XppFile.empty(
            template: (size) => XppBackgroundSolidLined(size: size),
          ),
        );
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AddPageButton(controller: ctrl)),
        ),
      );
      await tester.longPress(find.byType(IconButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carta di Smith'));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A5').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aggiungi'));
      await tester.pumpAndSettle();
      expect(ctrl.file!.pages!.last.background, isA<XppBackgroundSmith>());
      expect(ctrl.file!.pages!.last.pageSize!.width, 419.53);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(ctrl.file!.pages!.last.background, isA<XppBackgroundSolidLined>());
      expect(ctrl.file!.pages!.last.pageSize!.width, 595.28);
    },
  );

  testWidgets('Smith chart is painted in thumbnails and embedded in PDF', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final file = XppFile.empty(
        pageSize: XppPageSize(width: 200, height: 300),
        template: (size) => XppBackgroundSmith(size: size),
      );
      final png = await rasterizeExportPage(file.pages!.single, maxScale: 1);
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      try {
        expect(image.width, 200);
        expect(image.height, 300);
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        expect(
          [for (var i = 0; i < pixels.length; i += 4) pixels[i]]
              .any((r) => r < 240),
          true,
        );
      } finally {
        image.dispose();
        codec.dispose();
      }
      final bytes = await buildNotesPdf(
        file,
        loadBackground: (_, _, _) async => null,
      );
      expect(RegExp(r'/Subtype\s*/Image').hasMatch(latin1.decode(bytes)), true);
    });
  });

  testWidgets('infinite Smith chart renders once at its world position', (
    tester,
  ) async {
    final file = XppFile.empty(
      pageSize: XppPageSize(width: 200, height: 300),
      template: (size) => XppBackgroundSmith(size: size),
    )..pages!.first.infinite = true;
    final ctrl = CanvasController(autosaveEnabled: false)..init(file);
    final transform = TransformationController();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 200,
                height: 300,
                child: InfiniteCanvas(canvas: ctrl, transform: transform),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    Future<bool> hasChartPixels() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        return [for (var i = 0; i < pixels.length; i += 4) pixels[i]]
            .any((red) => red < 240);
      } finally {
        image.dispose();
      }
    }

    expect(await tester.runAsync(hasChartPixels), true);
    transform.value = Matrix4.identity()..translate(-600.0, -600.0);
    await tester.pump();
    expect(await tester.runAsync(hasChartPixels), false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    ctrl.dispose();
    transform.dispose();
  });
}
