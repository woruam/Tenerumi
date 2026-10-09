import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/widgets/pdf_zoom_detail.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppBackground.dart';

class _Controller extends CanvasController {
  final documents = <_Document>[];
  Completer<bool>? pendingRender;
  bool failDispose = false;
  _Controller() : super(autosaveEnabled: false);
  @override
  Future<pdfx.PdfDocument> openPdfDetail(int index) async {
    final doc = _Document(this);
    documents.add(doc);
    return doc;
  }

  @override
  int pdfSourcePage(int index) => 3;
}

class _Document extends pdfx.PdfDocument {
  final _Controller owner;
  final textures = <_Texture>[];
  int opened = 0, closed = 0, releases = 0;
  _Document(this.owner) : super(sourceName: 'test', id: 'test', pagesCount: 3);
  @override
  Future<pdfx.PdfPage> getPage(
    int number, {
    bool autoCloseAndroid = false,
  }) async {
    expectSync(number, 3);
    expectSync(opened, closed);
    opened++;
    return _Page(this);
  }

  @override
  Future<void> close() async {
    expectSync(opened, closed);
    releases++;
    isClosed = true;
  }
}

class _Page extends pdfx.PdfPage {
  _Page(_Document doc)
    : super(
        document: doc,
        id: 'page',
        pageNumber: 3,
        width: 595,
        height: 842,
        autoCloseAndroid: false,
      );
  @override
  Future<void> close() async {
    (document as _Document).closed++;
    isClosed = true;
  }

  @override
  Future<pdfx.PdfPageTexture> createTexture() async {
    final doc = document as _Document;
    final texture = _Texture(doc, doc.textures.length + 1);
    doc.textures.add(texture);
    return texture;
  }

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
  }) => throw StateError('Detail must never allocate a full-page raster');
}

class _Texture extends pdfx.PdfPageTexture {
  final _Document document;
  int releases = 0, updates = 0;
  double? fullPageWidth;
  @override
  int? textureWidth;
  @override
  int? textureHeight;
  _Texture(this.document, int id)
    : super(id: id, pageId: 'page', pageNumber: 3);
  @override
  bool get hasUpdatedTexture => updates > 0;
  @override
  Future<void> dispose() async {
    releases++;
    if (document.owner.failDispose) throw StateError('Native surface gone');
  }

  @override
  Future<bool> updateRect({
    required String documentId,
    int destinationX = 0,
    int destinationY = 0,
    int? width,
    int? height,
    int sourceX = 0,
    int sourceY = 0,
    int? textureWidth,
    int? textureHeight,
    double? fullWidth,
    double? fullHeight,
    String? backgroundColor,
    bool allowAntiAliasing = true,
  }) async {
    expectSync(document.opened, document.closed);
    updates++;
    this.textureWidth = textureWidth;
    this.textureHeight = textureHeight;
    fullPageWidth = fullWidth;
    expectSync(width! * height!, lessThanOrEqualTo(2000000));
    expectSync(width, lessThanOrEqualTo(2048));
    expectSync(height, lessThanOrEqualTo(2048));
    return document.owner.pendingRender?.future ?? true;
  }
}

Widget _viewer(_Controller controller, TransformationController transform) {
  final viewport = GlobalKey();
  return MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        key: viewport,
        width: 300,
        height: 400,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: 595,
            maxHeight: 842,
            child: ValueListenableBuilder<Matrix4>(
              valueListenable: transform,
              builder: (_, matrix, child) => Transform(
                alignment: Alignment.topLeft,
                transform: matrix,
                child: child,
              ),
              child: SizedBox(
                width: 595,
                height: 842,
                child: PdfZoomDetail(
                  controller: controller,
                  pageIndex: 0,
                  transform: transform,
                  viewportKey: viewport,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('visible crops stay bounded even at extreme zoom and pixel density', () {
    for (final zoom in [1.0, 2.0, 10.0, 100.0]) {
      final plan = PdfDetailPlan.create(
        const Size(595, 842),
        Rect.fromLTWH(10, 20, 300 / zoom, 400 / zoom),
        zoom * 4,
      )!;
      expect(plan.width * plan.height, lessThanOrEqualTo(2000000));
      expect(plan.width, lessThanOrEqualTo(2048));
      expect(plan.height, lessThanOrEqualTo(2048));
      expect(plan.region.contains(const Offset(10, 20)), isTrue);
    }
    expect(
      PdfDetailPlan.create(
        const Size(595, 842),
        const Rect.fromLTWH(600, 0, 50, 50),
        10,
      ),
      isNull,
    );
  });

  test('detail identity changes when a source page is remapped', () {
    final controller = CanvasController(autosaveEnabled: false)
      ..file = XppFile.empty();
    final background = XppBackgroundPdf(
      filename: 'one.pdf',
      page: 0,
      onUnavailable: (_) async => throw StateError('Unused'),
    );
    controller.file!.pages!.first.background = background;
    final initial = controller.pdfDetailIdentity(0);
    controller.file!.pages!.first.background = XppBackgroundPdf(
      filename: 'one.pdf',
      page: 2,
      onUnavailable: background.onUnavailable,
    );
    expect(controller.pdfDetailIdentity(0), isNot(initial));
    expect(controller.pdfSourcePage(0), 3);
    final remapped = controller.pdfDetailIdentity(0);
    controller.file!.pages!.first.background = XppBackgroundPdf(
      filename: 'two.pdf',
      page: 2,
      onUnavailable: background.onUnavailable,
    );
    expect(controller.pdfDetailIdentity(0), isNot(remapped));
    controller.dispose();
  });

  testWidgets(
    'zoom is debounced; detail uses a crop and releases on background',
    (tester) async {
      final ctrl = _Controller(), transform = TransformationController();
      await tester.pumpWidget(_viewer(ctrl, transform));
      for (var i = 2; i <= 10; i++) {
        transform.value = Matrix4.diagonal3Values(
          i.toDouble(),
          i.toDouble(),
          1,
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(ctrl.documents, isEmpty);
      await tester.pump(const Duration(milliseconds: 181));
      await tester.pump();
      final doc = ctrl.documents.single,
          texture = ctrl.documents.single.textures.single;
      expect(texture.fullPageWidth, greaterThan(5000));
      expect(texture.textureWidth, lessThan(1100));
      expect(find.byType(Texture), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(texture.releases, 1);
      expect(doc.releases, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 181));
      await tester.pump();
      expect(ctrl.documents, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(ctrl.documents.last.releases, 1);
      ctrl.dispose();
      transform.dispose();
    },
  );

  testWidgets(
    'closing during render disposes stale texture and closes document even on release failure',
    (tester) async {
      final ctrl = _Controller()
        ..pendingRender = Completer<bool>()
        ..failDispose = true;
      final transform = TransformationController();
      await tester.pumpWidget(_viewer(ctrl, transform));
      await tester.pump(const Duration(milliseconds: 181));
      await tester.pump();
      await tester.pump();
      final doc = ctrl.documents.single;
      expect(doc.textures.single.updates, 1);
      await tester.pumpWidget(const SizedBox());
      ctrl.pendingRender!.complete(true);
      await tester.pump();
      expect(doc.textures.single.releases, 1);
      expect(doc.releases, 1);
      expect(tester.takeException(), isNull);
      ctrl.dispose();
      transform.dispose();
    },
  );
}
