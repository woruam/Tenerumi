import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/src/stylus_shortcut.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/selection_clipboard.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/stylus_menu_settings.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';
import 'package:xournalpp/widgets/infinite_canvas.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/controllers/workspace_controller.dart';
import 'package:xournalpp/widgets/unified_toolbar.dart';

Future<void> mount(
  WidgetTester tester, {
  Duration delay = const Duration(milliseconds: 500),
  ValueChanged<StylusShortcut>? onSelect,
  ValueChanged<XppContent?>? onInk,
  SelectionClipboard? clipboard,
  List<XppContent> Function(Offset)? onPaste,
  double scale = 1,
  Object? identity,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                height: 300,
                child: PointerListener(
                  selectionIdentity: identity,
                  color: Colors.black,
                  strokeWidth: 2.5,
                  stylusMenuHoldDelay: delay,
                  stylusShortcuts: StylusShortcut.defaults,
                  toolData: const {
                    PointerDeviceKind.stylus: EditingTool.STYLUS,
                  },
                  onStylusShortcut: onSelect,
                  onNewContent: onInk,
                  clipboard: clipboard,
                  onPasteContent: onPaste,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

Future<TestGesture> open(
  WidgetTester tester, {
  Offset point = const Offset(150, 150),
}) async {
  final pen = await tester.createGesture(
    kind: PointerDeviceKind.stylus,
    pointer: 71,
  );
  await pen.down(point);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  expect(find.byKey(const ValueKey('stylus-radial-menu')), findsOneWidget);
  return pen;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'document settings expose the menu timing and shortcut settings',
    (tester) async {
      final theme = ThemeController();
      final workspace = WorkspaceController(autosaveEnabled: false);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeController>.value(value: theme),
            ChangeNotifierProvider<WorkspaceController>.value(value: workspace),
          ],
          child: const MaterialApp(home: Scaffold(appBar: UnifiedToolbar())),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('document-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Menù circolare della penna'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('stylus-menu-hold-delay')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('edit-radial-slot-4')), findsOneWidget);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
      theme.dispose();
    },
  );

  testWidgets(
    'empty clipboard item never selects an action when released over it',
    (tester) async {
      final selected = <StylusShortcut>[];
      await mount(tester, onSelect: selected.add);
      final pen = await open(tester);
      await pen.moveTo(
        tester.getCenter(find.byKey(const ValueKey('selection-paste'))),
      );
      await pen.up();
      await tester.pump();
      expect(selected, isEmpty);
      expect(find.byKey(const ValueKey('stylus-radial-menu')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final infinite in [false, true]) {
    testWidgets(
      'the held menu freezes stylus pan in canvas infinite=$infinite',
      (tester) async {
        final transform = TransformationController();
        final canvas = CanvasController(autosaveEnabled: false)
          ..init(XppFile.empty());
        canvas.file!.pages!.first.infinite = infinite;
        canvas.setTool(EditingTool.MOVE);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: infinite
                  ? InfiniteCanvas(canvas: canvas, transform: transform)
                  : ZoomableWidget(
                      controller: transform,
                      sceneSize: const Size(800, 3000),
                      stylusPanEnabled: true,
                      child: PointerListener(
                        stylusShortcuts: StylusShortcut.defaults,
                        stylusMenuHoldDelay: const Duration(milliseconds: 1100),
                        toolData: canvas.toolData,
                        onStylusShortcut: canvas.applyStylusShortcut,
                        child: const SizedBox(width: 800, height: 3000),
                      ),
                    ),
            ),
          ),
        );
        final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
        await pen.down(const Offset(400, 300));
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('stylus-radial-menu')),
          findsOneWidget,
        );
        final before = transform.value.clone();
        await pen.moveTo(
          tester.getCenter(find.byKey(const ValueKey('radial-slot-2'))),
        );
        await tester.pump();
        expect(transform.value, before);
        await pen.up();
        await tester.pump();
        expect(find.byKey(const ValueKey('stylus-radial-menu')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        canvas.dispose();
        transform.dispose();
      },
    );
  }

  testWidgets(
    'opening delay is respected and stationary release closes without changing tools',
    (tester) async {
      StylusShortcut? selected;
      final ink = <XppContent?>[];
      await mount(tester, onSelect: (s) => selected = s, onInk: ink.add);
      final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await pen.down(const Offset(150, 150));
      await tester.pump(const Duration(milliseconds: 499));
      expect(find.byKey(const ValueKey('stylus-radial-menu')), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.byKey(const ValueKey('stylus-radial-menu')), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('stylus-radial-menu')),
          matching: find.byType(Material),
        ),
        findsNWidgets(6),
      );
      await pen.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('stylus-radial-menu')), findsNothing);
      expect(selected, isNull);
      expect(ink, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final scale in [.4, 1.0, 3.0]) {
    testWidgets(
      'one held pen previews each item and chooses only on release at zoom $scale',
      (tester) async {
        final selected = <StylusShortcut>[];
        final ink = <XppContent?>[];
        await mount(
          tester,
          scale: scale,
          onSelect: selected.add,
          onInk: ink.add,
        );
        final pen = await open(tester, point: const Offset(90, 90));
        final target = find.byKey(const ValueKey('radial-slot-2'));
        final size = tester.getSize(target);
        expect(size, const Size(56, 56));
        await pen.moveTo(tester.getCenter(target));
        await tester.pump();
        expect(selected, isEmpty);
        final active = tester.widget<Material>(target);
        expect(
          active.color,
          Theme.of(tester.element(target)).colorScheme.primary,
        );
        final last = find.byKey(const ValueKey('radial-slot-3'));
        await pen.moveTo(tester.getCenter(last));
        await tester.pump();
        expect(selected, isEmpty);
        await pen.up();
        await tester.pump();
        expect(selected.single.tool, EditingTool.ERASER);
        expect(ink, isEmpty);
        expect(find.byKey(const ValueKey('stylus-radial-menu')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'returning to the center or leaving the buttons cancels selection',
    (tester) async {
      final selected = <StylusShortcut>[];
      await mount(tester, onSelect: selected.add);
      for (final release in [const Offset(150, 150), const Offset(700, 500)]) {
        final pen = await open(tester);
        await pen.moveTo(
          tester.getCenter(find.byKey(const ValueKey('radial-slot-1'))),
        );
        await tester.pump();
        await pen.moveTo(release);
        await pen.up();
        await tester.pump();
        expect(selected, isEmpty);
        expect(find.byKey(const ValueKey('stylus-radial-menu')), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cancel and app suspension close the menu without committing a tool or ink',
    (tester) async {
      final selected = <StylusShortcut>[];
      final ink = <XppContent?>[];
      await mount(tester, onSelect: selected.add, onInk: ink.add);
      final pen = await open(tester);
      await pen.moveTo(
        tester.getCenter(find.byKey(const ValueKey('radial-slot-2'))),
      );
      await pen.cancel();
      await tester.pump();
      expect(find.byKey(const ValueKey('stylus-radial-menu')), findsNothing);
      final held = await open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byKey(const ValueKey('stylus-radial-menu')), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await held.up();
      expect(selected, isEmpty);
      expect(ink, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('writing before the threshold never opens the menu', (
    tester,
  ) async {
    final ink = <XppContent?>[];
    await mount(tester, onInk: ink.add);
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(const Offset(120, 120));
    await pen.moveTo(const Offset(180, 180));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('stylus-radial-menu')), findsNothing);
    await pen.up();
    expect(ink, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('paste uses the held point and runs only once at release', (
    tester,
  ) async {
    final clipboard = SelectionClipboard();
    final stroke = XppStroke.byTool(
      tool: XppStrokeTool.PEN,
      color: Colors.black,
      points: [
        XppStrokePoint(x: 10, y: 10, width: 2),
        XppStrokePoint(x: 20, y: 20, width: 2),
      ],
    );
    clipboard.copy([stroke]);
    final positions = <Offset>[];
    await mount(
      tester,
      clipboard: clipboard,
      onPaste: (point) {
        positions.add(point);
        return [stroke];
      },
    );
    final pen = await open(tester);
    await pen.moveTo(
      tester.getCenter(find.byKey(const ValueKey('selection-paste'))),
    );
    await tester.pump();
    expect(positions, isEmpty);
    await pen.up();
    await tester.pump();
    expect(positions, [const Offset(150, 150)]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('other pointers cannot choose or dismiss the held pen menu', (
    tester,
  ) async {
    final selected = <StylusShortcut>[];
    await mount(tester, onSelect: selected.add);
    final pen = await open(tester);
    final point = tester.getCenter(find.byKey(const ValueKey('radial-slot-2')));
    final palm = await tester.startGesture(point, pointer: 81);
    await palm.moveBy(const Offset(4, 4));
    await palm.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('stylus-radial-menu')), findsOneWidget);
    expect(selected, isEmpty);
    await pen.moveTo(point);
    await pen.up();
    await tester.pump();
    expect(selected.single.tool, EditingTool.HIGHLIGHT);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('replacing the page or removing the widget leaves no overlay', (
    tester,
  ) async {
    final first = Object();
    await mount(tester, identity: first);
    final pen = await open(tester);
    await mount(tester, identity: Object());
    await tester.pump();
    expect(find.byKey(const ValueKey('stylus-radial-menu')), findsNothing);
    await pen.up();
    final next = await open(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await next.cancel();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings save delay and presets globally and cancel discards edits',
    (tester) async {
      final theme = ThemeController();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: theme,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showStylusMenuSettings(context, theme),
                  child: const Text('Settings'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('stylus-menu-hold-delay'));
      tester.widget<Slider>(slider).onChanged!(700);
      await tester.pump();
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();
      expect(theme.stylusMenuHoldDelayMs, 700);
      final restored = ThemeController();
      await restored.load();
      expect(restored.stylusMenuHoldDelayMs, 700);
      expect(restored.stylusShortcuts.length, 5);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      tester.widget<Slider>(slider).onChanged!(1500);
      await tester.pump();
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(theme.stylusMenuHoldDelayMs, 700);
      await tester.pumpWidget(const SizedBox());
      theme.dispose();
      restored.dispose();
    },
  );

  testWidgets('small and split view edges keep all circles on screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(350, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    final pen = await open(tester, point: const Offset(10, 10));
    for (var i = 0; i < 6; i++) {
      final key = i == 0 ? 'selection-paste' : 'radial-slot-$i';
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(350));
      expect(rect.bottom, lessThanOrEqualTo(500));
    }
    await pen.up();
    await tester.pumpWidget(const SizedBox());
  });
}
