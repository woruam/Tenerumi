import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/src/pdf_raster_cache.dart';
import 'package:xournalpp/widgets/virtual_page_column.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';

void main() {
  test(
      'PDF rendering is demand driven, serialized, and ignores disposed results',
      () async {
    final first = Completer<Uint8List?>();
    final calls = <int>[];
    final controller = CanvasController(pdfRasterizer: (page) {
      calls.add(page);
      return first.future;
    });
    controller.setVisiblePdfPages({0, 1});
    await Future<void>.delayed(Duration.zero);
    expect(calls, [0]);
    controller.setVisiblePdfPages({2});
    controller.dispose();
    first.complete(Uint8List(4));
    await Future<void>.delayed(Duration.zero);
    expect(calls, [0]);
    expect(controller.pdfBackgrounds, isEmpty);
  });

  test('suspended PDF request cannot publish stale page bytes', () async {
    final pending = Completer<Uint8List?>();
    final controller = CanvasController(pdfRasterizer: (_) => pending.future);
    controller.setVisiblePdfPages({0});
    await Future<void>.delayed(Duration.zero);
    controller.suspendPdfRendering();
    pending.complete(Uint8List(4));
    await Future<void>.delayed(Duration.zero);
    expect(controller.pdfBackgrounds, isEmpty);
    controller.dispose();
  });

  test('PDF cache evicts LRU and accounts for replacement and byte budget', () {
    final cache = PdfRasterCache(maxPages: 2, maxBytes: 10);
    cache[0] = Uint8List(4);
    cache[1] = Uint8List(4);
    expect(cache[0], isNotNull);
    cache[2] = Uint8List(4);
    expect(cache.containsKey(1), isFalse);
    expect(cache.byteCount, 8);
    cache[0] = Uint8List(8);
    expect(cache.keys, [0]);
    cache[3] = Uint8List(11);
    expect(cache.containsKey(3), isFalse);
    cache.clear();
    expect(cache.byteCount, 0);
  });

  testWidgets('100 pages mount only visible canvases; pan changes page set',
      (tester) async {
    final transform = TransformationController();
    Set<int> visible = {};
    await tester.pumpWidget(MaterialApp(
        home: Align(
            alignment: Alignment.topLeft,
            child: VirtualPageColumn(
                transform: transform,
                viewport: const Size(400, 600),
                width: 368,
                heights: List.filled(100, 520),
                onVisiblePages: (v) => visible = v,
                pageBuilder: (i) => Text('page $i')))));
    expect(find.byType(Text), findsNWidgets(2));
    expect(visible, {0, 1});
    transform.value = Matrix4.translationValues(0, -5440, 0);
    await tester.pump();
    expect(find.text('page 0'), findsNothing);
    expect(visible.contains(10), isTrue);
    expect(visible.length, lessThan(5));
    await tester.pumpWidget(const SizedBox());
    transform.dispose();
  });
}
