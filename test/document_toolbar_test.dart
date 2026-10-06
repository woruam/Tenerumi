import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/controllers/workspace_controller.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/WorkspacePage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/widgets/unified_toolbar.dart';

class _SaveSpy extends CanvasController {
  int calls = 0;

  @override
  Future<bool> saveFile(BuildContext context) async {
    calls++;
    return false;
  }
}

class _ToolbarWorkspace extends WorkspaceController {
  final primary = _SaveSpy()..init(XppFile.empty());
  final secondary = _SaveSpy()..init(XppFile.empty());

  @override
  CanvasController get active =>
      activePanel == WorkspacePanel.primary ? primary : secondary;

  @override
  void dispose() {
    primary.dispose();
    secondary.dispose();
    super.dispose();
  }
}

Future<void> _menu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('document-settings')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('settings stay visible on phone; save follows focused panel',
      (tester) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ws = _ToolbarWorkspace();
    final theme = ThemeController();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<WorkspaceController>.value(value: ws),
      ],
      child: MaterialApp(
          home: Scaffold(appBar: UnifiedToolbar(onOpenFile: () {}))),
    ));
    await tester.pumpAndSettle();
    await _menu(tester);
    expect(find.text('Salva'), findsOneWidget);
    expect(find.text('Apri file'), findsOneWidget);
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(ws.primary.calls, 1);
    expect(ws.secondary.calls, 0);
    ws.focus(WorkspacePanel.secondary);
    await tester.pump();
    await _menu(tester);
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(ws.primary.calls, 1);
    expect(ws.secondary.calls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    ws.dispose();
    theme.dispose();
  });

  testWidgets('save is disabled while document is being saved', (tester) async {
    final ws = _ToolbarWorkspace();
    ws.primary.savingFile = true;
    final theme = ThemeController();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<WorkspaceController>.value(value: ws),
      ],
      child: const MaterialApp(home: Scaffold(appBar: UnifiedToolbar())),
    ));
    // An active progress indicator does not settle.
    await tester.tap(find.byKey(const ValueKey('document-settings')));
    await tester.pump(const Duration(milliseconds: 300));
    final save = tester.widget<PopupMenuItem<String>>(find.ancestor(
        of: find.text('Salva'), matching: find.byType(PopupMenuItem<String>)));
    expect(save.enabled, isFalse);
    await tester.tap(find.text('Salva'));
    await tester.pump();
    expect(ws.primary.calls, 0);
    await tester.pumpWidget(const SizedBox());
    ws.dispose();
    theme.dispose();
  });

  for (final result in ['success', 'cancel', 'error']) {
    testWidgets('open file $result preserves existing tabs and split state',
        (tester) async {
      final theme = ThemeController();
      final initial = XppFile.empty()..title = 'Original';
      final imported = XppFile.empty()..title = 'Imported';
      await tester.pumpWidget(ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: WorkspacePage(
            initialFile: initial,
            documentOpener: () async {
              if (result == 'error') throw const FormatException('Bad file');
              return result == 'cancel' ? null : imported;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final ws =
          tester.element(find.byType(CanvasPage)).read<WorkspaceController>();
      ws.toggleSplit();
      final secondary = ws.documents[ws.secondaryIndex!];
      ws.focus(WorkspacePanel.secondary);
      ws.controllerFor(initial).hasUnsavedChanges = true;
      await tester.pumpAndSettle();
      await _menu(tester);
      await tester.tap(find.text('Apri file'));
      await tester.pumpAndSettle();
      expect(ws.documents, containsAll([initial, secondary]));
      expect(ws.splitEnabled, isTrue);
      expect(ws.documents[ws.secondaryIndex!], same(secondary));
      expect(ws.controllerFor(initial).hasUnsavedChanges, isTrue);
      if (result == 'success') {
        expect(ws.documents.length, 3);
        expect(ws.activeFile, same(imported));
        expect(ws.activePanel, WorkspacePanel.primary);
      } else {
        expect(ws.documents.length, 2);
        expect(ws.activeFile, same(secondary));
        expect(find.byType(SnackBar),
            result == 'error' ? findsOneWidget : findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      theme.dispose();
    });
  }

  testWidgets('open file cannot launch a second picker while waiting',
      (tester) async {
    final theme = ThemeController();
    final pending = Completer<XppFile?>();
    int calls = 0;
    await tester.pumpWidget(ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(home: WorkspacePage(documentOpener: () {
        calls++;
        return pending.future;
      })),
    ));
    await tester.pumpAndSettle();
    await _menu(tester);
    await tester.tap(find.text('Apri file'));
    await tester.pumpAndSettle();
    await _menu(tester);
    final open = tester.widget<PopupMenuItem<String>>(find.ancestor(
        of: find.text('Apri file'),
        matching: find.byType(PopupMenuItem<String>)));
    expect(open.enabled, isFalse);
    await tester.tap(find.text('Apri file'));
    await tester.pump();
    expect(calls, 1);
    pending.complete(null);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    theme.dispose();
  });
}
