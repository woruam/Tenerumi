import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/decoded_image_cache.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('returning canvas has its decoded PDF on the first frame', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = CanvasController(autosaveEnabled: false)
      ..init(XppFile.empty());
    final bytes = Uint8List.fromList(kTransparentImage);
    controller.pdfBackgrounds[0] = bytes;
    Widget canvas() => MaterialApp(
      home: CanvasPage(
        file: controller.file,
        controller: controller,
        showInternalToolbar: false,
      ),
    );
    await tester.pumpWidget(canvas());
    await tester.runAsync(() async {
      for (
        var attempt = 0;
        attempt < 50 && DecodedImageCache.shared.lookup(bytes) == null;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(DecodedImageCache.shared.lookup(bytes), isNotNull);
    await tester.pumpWidget(const SizedBox());
    expect(DecodedImageCache.shared.lookup(bytes), isNotNull);
    await tester.pumpWidget(canvas());
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    expect(DecodedImageCache.shared.byteCount, 0);
  });

  test(
    'returning to a tab reuses visible PDF rasters; invalidation clears them',
    () async {
      final rendered = <int>[];
      final controller = CanvasController(
        autosaveEnabled: false,
        pdfRasterizer: (page) async {
          rendered.add(page);
          return Uint8List.fromList([page]);
        },
      );
      addTearDown(controller.dispose);
      controller.setVisiblePdfPages({0, 1});
      await Future<void>.delayed(Duration.zero);
      expect(rendered, [0, 1]);
      final first = controller.pdfBackgrounds[0];

      controller.suspendPdfRendering(retainRasterCache: true);
      expect(controller.pdfBackgrounds[0], same(first));
      controller.setVisiblePdfPages({0, 1});
      await Future<void>.delayed(Duration.zero);
      expect(rendered, [0, 1]);

      controller.suspendPdfRendering();
      expect(controller.pdfBackgrounds, isEmpty);
      controller.setVisiblePdfPages({0});
      await Future<void>.delayed(Duration.zero);
      expect(rendered, [0, 1, 0]);
    },
  );

  test('suspended tabs retain at most four visible PDF rasters', () async {
    final controller = CanvasController(
      autosaveEnabled: false,
      pdfRasterizer: (page) async => Uint8List.fromList([page]),
    );
    addTearDown(controller.dispose);
    controller.activePageIndex = 5;
    controller.setVisiblePdfPages({0, 1, 2, 3, 4, 5});
    await Future<void>.delayed(Duration.zero);
    controller.suspendPdfRendering(retainRasterCache: true);
    expect(controller.pdfBackgrounds.length, 4);
    expect(controller.pdfBackgrounds.containsKey(5), isTrue);

    controller.setVisiblePdfPages({4, 5});
    await Future<void>.delayed(Duration.zero);
    controller.suspendPdfRendering(retainRasterCache: true);
    expect(controller.pdfBackgrounds.keys.toSet(), {4, 5});
  });

  test(
    'inactive PDF snapshots share a 32 MiB budget and evict oldest tabs',
    () async {
      final controllers = List.generate(
        3,
        (_) => CanvasController(
          autosaveEnabled: false,
          pdfRasterizer: (_) async => Uint8List(12 * 1024 * 1024),
        ),
      );
      addTearDown(() {
        for (final controller in controllers) {
          controller.dispose();
        }
      });
      for (final controller in controllers) {
        controller.setVisiblePdfPages({0});
        await Future<void>.delayed(Duration.zero);
        controller.suspendPdfRendering(retainRasterCache: true);
      }
      expect(controllers.first.pdfBackgrounds, isEmpty);
      expect(controllers[1].pdfBackgrounds, isNotEmpty);
      expect(controllers[2].pdfBackgrounds, isNotEmpty);
      expect(
        controllers.fold<int>(0, (sum, c) => sum + c.pdfBackgrounds.byteCount),
        lessThanOrEqualTo(32 * 1024 * 1024),
      );
    },
  );
}
