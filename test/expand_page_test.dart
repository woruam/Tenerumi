import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/widgets/expand_page_dialog.dart';
import 'package:xournalpp/widgets/in_app_browser_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('expandPage increases width to the right and height at the bottom', () {
    final ctrl = CanvasController(autosaveEnabled: false)..init(XppFile.empty());
    addTearDown(ctrl.dispose);

    final initialPage = ctrl.file!.pages!.first;
    final initialWidth = initialPage.pageSize!.width;
    final initialHeight = initialPage.pageSize!.height;

    // Espansione sia a destra che in basso
    ctrl.expandPage(0, deltaWidth: 300, deltaHeight: 300);

    expect(initialPage.pageSize!.width, closeTo(initialWidth + 300, 0.001));
    expect(initialPage.pageSize!.height, closeTo(initialHeight + 300, 0.001));
    expect(initialPage.background?.size?.width, closeTo(initialWidth + 300, 0.001));
    expect(initialPage.background?.size?.height, closeTo(initialHeight + 300, 0.001));
    expect(ctrl.hasUnsavedChanges, isTrue);

    // Undo ripristina le dimensioni originali
    ctrl.undo();
    expect(initialPage.pageSize!.width, closeTo(initialWidth, 0.001));
    expect(initialPage.pageSize!.height, closeTo(initialHeight, 0.001));

    // Redo ripristina l'espansione
    ctrl.redo();
    expect(initialPage.pageSize!.width, closeTo(initialWidth + 300, 0.001));
    expect(initialPage.pageSize!.height, closeTo(initialHeight + 300, 0.001));
  });

  test('resizePage sets custom width and height with undo/redo support', () {
    final ctrl = CanvasController(autosaveEnabled: false)..init(XppFile.empty());
    addTearDown(ctrl.dispose);

    final initialPage = ctrl.file!.pages!.first;
    final initialWidth = initialPage.pageSize!.width;
    final initialHeight = initialPage.pageSize!.height;

    ctrl.resizePage(0, width: 800, height: 1200);

    expect(initialPage.pageSize!.width, equals(800));
    expect(initialPage.pageSize!.height, equals(1200));

    ctrl.undo();
    expect(initialPage.pageSize!.width, equals(initialWidth));
    expect(initialPage.pageSize!.height, equals(initialHeight));
  });

  testWidgets('showExpandPageDialog renders quick buttons and presets', (tester) async {
    final ctrl = CanvasController(autosaveEnabled: false)..init(XppFile.empty());
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showExpandPageDialog(context, ctrl),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Espandi Pagina'), findsOneWidget);
    expect(find.text('In basso (+300 pt)'), findsOneWidget);
    expect(find.text('A destra (+300 pt)'), findsOneWidget);
    expect(find.text('Entrambi (+300 pt)'), findsOneWidget);
    expect(find.text('Applica Dimensioni'), findsOneWidget);
  });

  testWidgets('showInAppBrowserDialog renders search bar and shortcut chips', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showInAppBrowserDialog(context, 'flutter math'),
              child: const Text('Open Browser Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Browser Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Ricerca Web & Browser'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Wikipedia'), findsOneWidget);
    expect(find.text('WolframAlpha'), findsOneWidget);
    expect(find.text('Naviga / Cerca'), findsOneWidget);
  });
}
