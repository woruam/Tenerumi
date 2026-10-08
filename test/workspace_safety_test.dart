import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/WorkspacePage.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/controllers/workspace_controller.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/widgets/unsaved_document_dialog.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/src/globals.dart';

class _SaveController extends CanvasController {
  _SaveController() : super(autosaveEnabled: false);
  bool succeeds = false;
  int attempts = 0;
  @override
  Future<bool> saveFile(BuildContext context) async {
    attempts++;
    if (succeeds) hasUnsavedChanges = false;
    return succeeds;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('system back protects an inactive unmounted dirty tab',
      (tester) async {
    final theme = ThemeController();
    await tester.pumpWidget(ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => WorkspacePage())),
                        child: const Text('Open workspace')),
                  ))),
    ));
    await tester.tap(find.text('Open workspace'));
    await tester.pumpAndSettle();
    final ws =
        tester.element(find.byType(CanvasPage)).read<WorkspaceController>();
    final hidden = XppFile.empty()..title = 'Hidden dirty tab';
    ws.addDocument(hidden);
    ws.controllerFor(hidden).hasUnsavedChanges = true;
    await tester.pump();
    expect(find.byType(CanvasPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Modifiche non salvate'), findsOneWidget);
    expect(find.text('Salvare "Hidden dirty tab" prima di chiudere?'),
        findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkspacePage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chiudi senza salvare'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkspacePage), findsNothing);
    theme.dispose();
  });

  test(
      'saved touch preference follows selected tool and preserves inverted eraser',
      () async {
    SharedPreferences.setMockInitialValues(
        {PreferencesKeys.kTouchDrawing: true});
    final controller = CanvasController(autosaveEnabled: false)..init(XppFile.empty());
    await Future<void>.delayed(Duration.zero);
    expect(controller.touchDrawingEnabled, isTrue);
    controller.setTool(EditingTool.HIGHLIGHT);
    expect(controller.toolData[PointerDeviceKind.touch], EditingTool.HIGHLIGHT);
    controller.setTool(EditingTool.MOVE);
    expect(controller.toolData[PointerDeviceKind.touch], EditingTool.MOVE);
    expect(controller.toolData[PointerDeviceKind.invertedStylus],
        EditingTool.ERASER);
    controller.dispose();
  });

  test('exit checks inactive and secondary documents in order', () async {
    final ws = WorkspaceController(autosaveEnabled: false);
    ws.addDocument(XppFile.empty()..title = 'inactive');
    ws.addDocument(XppFile.empty()..title = 'secondary');
    final visited = <CanvasController>[];
    expect(
        await ws.confirmCloseAll((controller) async {
          visited.add(controller);
          return visited.length < 3;
        }),
        isFalse);
    expect(visited, ws.documents.map(ws.controllerFor).toList());
    await Future<void>.delayed(Duration.zero);
    ws.dispose();
  });

  test('cancel stops remaining close checks', () async {
    final ws = WorkspaceController(autosaveEnabled: false);
    ws.addDocument(XppFile.empty());
    var calls = 0;
    expect(
        await ws.confirmCloseAll((_) async {
          calls++;
          return false;
        }),
        isFalse);
    expect(calls, 1);
    await Future<void>.delayed(Duration.zero);
    ws.dispose();
  });

  test('closing preceding tab preserves selected document', () async {
    final ws = WorkspaceController(autosaveEnabled: false);
    final selected = XppFile.empty();
    ws.addDocument(selected);
    ws.setPrimary(1);
    await Future<void>.delayed(Duration.zero);
    ws.removeDocument(ws.documents.first);
    expect(ws.activeFile, same(selected));
    ws.dispose();
  });

  for (final succeeds in [false, true]) {
    testWidgets(
        'save ${succeeds ? 'success allows' : 'failure prevents'} close',
        (tester) async {
      final controller = _SaveController()
        ..file = (XppFile.empty()..title = 'Regression')
        ..hasUnsavedChanges = true
        ..succeeds = succeeds;
      bool? allowed;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
        builder: (context) => TextButton(
            onPressed: () async {
              allowed = await confirmDocumentClose(context, controller);
            },
            child: const Text('Exit')),
      ))));
      await tester.tap(find.text('Exit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();
      expect(allowed, succeeds);
      expect(controller.attempts, 1);
      expect(controller.hasUnsavedChanges, !succeeds);
      controller.dispose();
    });
  }
}
