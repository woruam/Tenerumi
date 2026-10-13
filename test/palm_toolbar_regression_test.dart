import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';
import 'package:xournalpp/widgets/infinite_canvas.dart';
import 'package:xournalpp/widgets/canvas_toolbar.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final infinite in [false, true]) {
    for (final kind in [
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
    ]) {
      testWidgets(
        'pen proximity cancels pinch and fresh pinch recovers $infinite $kind',
        (tester) async {
          final transform = TransformationController();
          final canvas = CanvasController(autosaveEnabled: false)
            ..file = XppFile.empty();
          canvas.toolData[PointerDeviceKind.stylus] = EditingTool.STYLUS;
          canvas.toolData[PointerDeviceKind.touch] = EditingTool.MOVE;
          canvas.file!.pages!.first.infinite = infinite;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: infinite
                    ? InfiniteCanvas(canvas: canvas, transform: transform)
                    : ZoomableWidget(
                        controller: transform,
                        sceneSize: const Size(800, 2000),
                        child: const SizedBox(width: 800, height: 2000),
                      ),
              ),
            ),
          );
          final first = await tester.startGesture(
            const Offset(180, 200),
            pointer: 1,
          );
          final second = await tester.startGesture(
            const Offset(330, 200),
            pointer: 2,
          );
          await first.moveTo(const Offset(130, 200));
          await second.moveTo(const Offset(390, 200));
          await tester.pump();
          expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
          final before = transform.value.clone();
          final pen = await tester.createGesture(kind: kind, pointer: 7);
          await pen.addPointer(location: const Offset(250, 200));
          await pen.moveTo(const Offset(251, 200));
          await tester.pump();
          await first.moveBy(const Offset(-70, 0));
          await second.moveBy(const Offset(70, 0));
          await tester.pump();
          expect(transform.value.storage, orderedEquals(before.storage));
          await first.up();
          await second.up();
          // New fingers must also be ignored while the pen is nearby.
          final palm1 = await tester.startGesture(
            const Offset(180, 200),
            pointer: 3,
          );
          final palm2 = await tester.startGesture(
            const Offset(330, 200),
            pointer: 4,
          );
          await palm1.moveBy(const Offset(-60, 0));
          await palm2.moveBy(const Offset(60, 0));
          await tester.pump();
          expect(transform.value.storage, orderedEquals(before.storage));
          await palm1.up();
          await palm2.up();
          if (kind == PointerDeviceKind.stylus) {
            // Stylus hover remains nearby even without another hover event.
            await tester.pump(const Duration(seconds: 1));
            final touch = await tester.startGesture(
              const Offset(220, 220),
              pointer: 8,
            );
            await touch.moveBy(const Offset(0, -100));
            await tester.pump();
            expect(transform.value.storage, orderedEquals(before.storage));
            await touch.up();
          }
          await pen.removePointer();
          await tester.pump(const Duration(milliseconds: 350));
          final fresh1 = await tester.startGesture(
            const Offset(180, 200),
            pointer: 5,
          );
          final fresh2 = await tester.startGesture(
            const Offset(330, 200),
            pointer: 6,
          );
          await fresh1.moveBy(const Offset(-65, 0));
          await fresh2.moveBy(const Offset(65, 0));
          await tester.pump();
          expect(
            transform.value.getMaxScaleOnAxis(),
            greaterThan(before.getMaxScaleOnAxis()),
          );
          await fresh1.up();
          await fresh2.up();
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox());
          transform.dispose();
          canvas.dispose();
        },
      );
    }
  }
  for (final ink in [Colors.black, Colors.purple]) {
    testWidgets('selected tool is independent of ink $ink', (tester) async {
      final canvas = CanvasController(autosaveEnabled: false)
        ..file = XppFile.empty();
      canvas.toolData[PointerDeviceKind.stylus] = EditingTool.STYLUS;
      canvas.toolData[PointerDeviceKind.touch] = EditingTool.MOVE;
      final theme = ThemeController();
      canvas.penColor = ink;
      final penKey = GlobalKey();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CanvasController>.value(value: canvas),
            ChangeNotifierProvider<ThemeController>.value(value: theme),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: CanvasToolbar(
                penKey: penKey,
                highlighterKey: GlobalKey(),
                shapeKey: GlobalKey(),
                eraserKey: GlobalKey(),
                onPenTap: () {},
                onHighlighterTap: () {},
                onShapeTap: () {},
                onEraserTap: () {},
                onImportPdf: () {},
                onToolSelect: (tool) {
                  canvas.toolData[PointerDeviceKind.stylus] = tool;
                  canvas.notifyListeners();
                },
                onPomodoroTap: () {},
              ),
            ),
          ),
        ),
      );
      bool selected(String tooltip) => tester
          .widgetList<Semantics>(
            find.ancestor(
              of: find.byTooltip(tooltip),
              matching: find.byType(Semantics),
            ),
          )
          .any((semantics) => semantics.properties.selected == true);
      expect(selected('Penna'), isTrue);
      expect(find.byIcon(Icons.check), findsNothing);
      final button = tester.widget<IconButton>(find.byKey(penKey));
      expect(
        button.style!.foregroundColor!.resolve({}),
        Theme.of(tester.element(find.byKey(penKey))).colorScheme.onSurface,
      );
      expect(button.style!.side!.resolve({})!.width, 2);
      await tester.tap(find.byTooltip('Lazo'));
      await tester.pump();
      expect(selected('Penna'), isFalse);
      expect(selected('Lazo'), isTrue);
      await tester.tap(find.byTooltip('Mano (Modalità Sicura)'));
      await tester.pump();
      expect(selected('Lazo'), isFalse);
      expect(selected('Mano (Modalità Sicura)'), isTrue);
      await tester.pumpWidget(const SizedBox());
      canvas.dispose();
      theme.dispose();
    });
  }
}
