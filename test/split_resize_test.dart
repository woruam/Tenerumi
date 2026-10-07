import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/controllers/workspace_controller.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/document_scene_geometry.dart';
import 'package:xournalpp/widgets/split_screen_view.dart';
import 'package:xournalpp/widgets/virtual_page_column.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('reflow preserves page fraction and fixed gaps for mixed page sizes',
      () {
    expect(reflowSceneY(24 + 200 + 24 + 50, 100, 200, [.5, 1]),
        24 + 400 + 24 + 100);
    expect(reflowSceneY(24 + 200 + 12, 100, 200, [.5, 1]), 24 + 400 + 12);
    expect(reflowSceneY(0, 100, 200, [.5]), 0);
  });

  for (final size in [const Size(1000, 600), const Size(400, 1000)]) {
    testWidgets('divider drag freezes document gestures and scene at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ws = WorkspaceController(autosaveEnabled: false);
      final secondary = XppFile.empty(title: 'Second');
      ws.addDocument(secondary);
      final first = ws.controllerFor(ws.documents.first);
      for (var i = 0; i < 10; i++) {
        first.addPage();
      }
      final zoom =
          TransformationController(Matrix4.translationValues(0, -900, 0));
      final secondZoom =
          TransformationController(Matrix4.translationValues(0, -80, 0));
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<WorkspaceController>.value(value: ws),
            ChangeNotifierProvider<ThemeController>(
                create: (_) => ThemeController()),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: SplitScreenView(
            primaryWidget: CanvasPage(
                controller: first,
                zoomController: zoom,
                showInternalToolbar: false),
            secondaryWidget: CanvasPage(
                controller: ws.controllerFor(secondary),
                zoomController: secondZoom,
                showInternalToolbar: false),
          )))));
      await tester.pumpAndSettle();
      final widths = tester
          .widgetList<VirtualPageColumn>(find.byType(VirtualPageColumn))
          .map((w) => w.width)
          .toList();
      final startMatrix = zoom.value.clone();
      final secondaryMatrix = secondZoom.value.clone();
      final divider = find.byKey(const ValueKey('split-divider'));
      final gesture = await tester.startGesture(tester.getCenter(divider));
      await tester.pump();
      final delta =
          size.width > size.height ? const Offset(80, 0) : const Offset(0, 80);
      await gesture.moveBy(delta);
      await tester.pump();
      await gesture.moveBy(delta);
      await tester.pump(const Duration(milliseconds: 100));
      expect(ws.dividerRatio, greaterThan(.5));
      expect(zoom.value, startMatrix);
      expect(secondZoom.value, secondaryMatrix);
      expect(
          tester
              .widgetList<VirtualPageColumn>(find.byType(VirtualPageColumn))
              .map((w) => w.width)
              .toList(),
          widths);
      expect(
          tester
              .widgetList<ZoomableWidget>(find.byType(ZoomableWidget))
              .every((w) => !w.interactionsEnabled),
          isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
          tester
              .widgetList<ZoomableWidget>(find.byType(ZoomableWidget))
              .every((w) => w.interactionsEnabled),
          isTrue);
      final newWidth = tester
          .widgetList<VirtualPageColumn>(find.byType(VirtualPageColumn))
          .first
          .width;
      expect(
          zoom.toScene(Offset.zero).dy,
          closeTo(
              reflowSceneY(900, widths.first, newWidth,
                  first.file!.pages!.map((p) => p.pageSize!.ratio)),
              .001));
      await tester.pumpWidget(const SizedBox());
      zoom.dispose();
      secondZoom.dispose();
      ws.dispose();
    });
  }
}
