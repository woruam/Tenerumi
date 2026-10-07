import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';
import 'package:xournalpp/plugins/plugin_examples.dart';
import 'package:xournalpp/plugins/plugin_manager_page.dart';
import 'package:xournalpp/plugins/plugin_manifest.dart';
import 'package:xournalpp/plugins/plugin_runtime.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppPageSize.dart';

String source(
  List steps, {
  List<String> permissions = const ['document.write'],
  List inputs = const [],
  String id = 'test.plugin',
}) => jsonEncode({
  'apiVersion': 1,
  'id': id,
  'name': 'Test plugin',
  'version': '1.0.0',
  'permissions': permissions,
  'commands': [
    {'id': 'run', 'label': 'Esegui test', 'inputs': inputs, 'steps': steps},
  ],
});
CanvasController canvas() => CanvasController(autosaveEnabled: false)
  ..file = XppFile.empty(
    title: 'Test',
    pageSize: XppPageSize(width: 300, height: 260),
  );
List content(CanvasController c) => c.file!.pages!.first.layers!.first.content!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'valid images commit; malformed images cannot corrupt a document',
    () async {
      final plugins = PluginController();
      final c = canvas();
      addTearDown(plugins.dispose);
      addTearDown(c.dispose);
      await plugins.install(
        source([
          {
            'action': 'image.add',
            'args': {'base64': base64Encode(kTransparentImage)},
          },
        ]),
      );
      await plugins.execute('test.plugin', 'run', c);
      expect(content(c), hasLength(1));
      await plugins.install(
        source([
          {
            'action': 'text.add',
            'args': {'text': 'temporary'},
          },
          {
            'action': 'image.add',
            'args': {
              'base64': base64Encode([1, 2, 3]),
            },
          },
        ]),
        replace: true,
      );
      await expectLater(
        plugins.execute('test.plugin', 'run', c),
        throwsA(anything),
      );
      expect(content(c), hasLength(1));
      expect(c.undoStack, hasLength(1));
    },
  );

  test(
    'invalid manifest, permissions and unknown API do not install',
    () async {
      final plugins = PluginController();
      addTearDown(plugins.dispose);
      await expectLater(
        plugins.install(
          source([
            {'action': 'native.shell'},
          ]),
        ),
        throwsFormatException,
      );
      await expectLater(
        plugins.install(
          source([
            {'action': 'text.add'},
          ], permissions: []),
        ),
        throwsFormatException,
      );
      expect(
        () => NotePlugin.parse(
          source([
            {'action': 'message', 'set': 'x'},
          ]),
        ),
        throwsFormatException,
      );
      expect(
        () => NotePlugin.parse(source([], id: 'Invalid ID')),
        throwsFormatException,
      );
      final future = jsonDecode(source([])) as Map;
      future['apiVersion'] = 2;
      expect(() => NotePlugin.parse(jsonEncode(future)), throwsFormatException);
      expect(plugins.installed, isEmpty);
    },
  );

  test('all bundled examples install and generate undoable notes or persistent tools', () async {
    final plugins = PluginController();
    final c = canvas();
    addTearDown(plugins.dispose);
    addTearDown(c.dispose);
    for (var i = 0; i < pluginExamples.length; i++) {
      await plugins.install(exampleSource(i));
    }
    await plugins.execute(
      'example.date-stamp',
      'stamp',
      c,
      input: {'title': 'Lezione'},
    );
    expect((content(c).single as XppText).text, startsWith('Lezione — '));
    await plugins.execute('example.weekly-planner', 'generate', c);
    expect(content(c), hasLength(15));
    expect(c.undoStack, hasLength(2));
    c.undo();
    expect(content(c), hasLength(1));
    c.redo();
    expect(content(c), hasLength(15));
    await plugins.execute('example.study-tools', 'highlight', c);
    expect(c.highlighterWidth, 18);
    expect(c.undoStack, hasLength(2));
    expect(
      plugins.installed
          .firstWhere((e) => e.plugin.id == 'example.study-tools')
          .state['uses'],
      1,
    );
    final reloaded = PluginController();
    await reloaded.load();
    addTearDown(reloaded.dispose);
    expect(
      reloaded.installed
          .firstWhere((e) => e.plugin.id == 'example.study-tools')
          .state['uses'],
      1,
    );
  });

  test(
    'conditions, foreach, arithmetic, text transforms and storage compose',
    () async {
      final plugins = PluginController();
      final c = canvas();
      addTearDown(plugins.dispose);
      addTearDown(c.dispose);
      await plugins.install(
        source(
          [
            {
              'set': 'words',
              'value': ['one', 'two', 'three'],
            },
            {
              'forEach': {'var': 'words'},
              'as': 'word',
              'steps': [
                {
                  'action': 'text.add',
                  'args': {
                    'text': {
                      'op': 'upper',
                      'args': [
                        {'var': 'word'},
                      ],
                    },
                    'x': 10,
                    'y': 20,
                  },
                },
              ],
            },
            {'action': 'content.list', 'as': 'items'},
            {
              'if': {
                'op': 'eq',
                'args': [
                  {
                    'op': 'length',
                    'args': [
                      {'var': 'items'},
                    ],
                  },
                  3,
                ],
              },
              'then': [
                {
                  'action': 'content.transform',
                  'args': {'ids': 'all', 'dx': 20, 'dy': 10, 'scale': 2},
                },
                {
                  'action': 'state.set',
                  'args': {'key': 'count', 'value': 3},
                },
              ],
              'else': [
                {
                  'action': 'message',
                  'args': {'text': 'Unexpected'},
                },
              ],
            },
            {
              'action': 'text.update',
              'args': {'id': 1, 'text': 'updated'},
            },
          ],
          permissions: ['document.read', 'document.write', 'storage'],
        ),
      );
      await plugins.execute('test.plugin', 'run', c);
      expect((content(c).first as XppText).offset, const Offset(40, 50));
      expect((content(c).first as XppText).text, 'ONE');
      expect((content(c)[1] as XppText).text, 'updated');
      expect(plugins.installed.single.state['count'], 3);
      expect(c.undoStack, hasLength(1));
      c.undo();
      expect(content(c), isEmpty);
      c.redo();
      expect(content(c), hasLength(3));
    },
  );

  test(
    'failed plugin rolls back content, state, tool and undo history',
    () async {
      final plugins = PluginController();
      final c = canvas();
      addTearDown(plugins.dispose);
      addTearDown(c.dispose);
      await plugins.install(
        source(
          [
            {
              'action': 'text.add',
              'args': {'text': 'must not appear'},
            },
            {
              'action': 'state.set',
              'args': {'key': 'count', 'value': 1},
            },
            {
              'action': 'tool.set',
              'args': {'tool': 'pen', 'width': 40},
            },
            {
              'action': 'content.transform',
              'args': {
                'ids': [999],
              },
            },
          ],
          permissions: ['document.write', 'storage', 'tool.write'],
        ),
      );
      await expectLater(
        plugins.execute('test.plugin', 'run', c),
        throwsStateError,
      );
      expect(content(c), isEmpty);
      expect(c.undoStack, isEmpty);
      expect(c.hasUnsavedChanges, isFalse);
      expect(c.penWidth, 2.5);
      expect(plugins.installed.single.state, isEmpty);
      expect(plugins.running, isFalse);
    },
  );

  test('instruction budget interrupts nested loops without committing partial edits', () async {
    final plugins = PluginController();
    final c = canvas();
    addTearDown(plugins.dispose);
    addTearDown(c.dispose);
    await plugins.install(
      source([
        {
          'action': 'text.add',
          'args': {'text': 'temporary'},
        },
        {
          'repeat': 1000,
          'as': 'outer',
          'steps': [
            {
              'repeat': 1000,
              'as': 'inner',
              'steps': [
                {'set': 'n', 'value': 1},
              ],
            },
          ],
        },
      ]),
    );
    await expectLater(
      plugins.execute('test.plugin', 'run', c),
      throwsStateError,
    );
    expect(content(c), isEmpty);
    expect(c.undoStack, isEmpty);
  });

  test('large string expansion is rejected before allocating huge output', () {
    final plugin = NotePlugin.parse(source([]));
    final runtime = PluginRuntime(plugin, PluginApi(), {});
    expect(
      () => runtime.evaluate({
        'op': 'replace',
        'args': ['x' * 65536, 'x', 'a' * 65536],
      }),
      throwsStateError,
    );
    expect(
      () => runtime.evaluate({
        'op': 'concat',
        'args': ['x' * 40000, 'y' * 40000],
      }),
      throwsStateError,
    );
    expect(
      () => runtime.evaluate({
        'op': 'div',
        'args': [1, 0],
      }),
      throwsStateError,
    );
    expect(
      runtime.evaluate({
        'op': 'sin',
        'args': [0],
      }),
      0,
    );
    expect(
      runtime.evaluate({
        'op': 'pow',
        'args': [2, 3],
      }),
      8,
    );
    expect(
      runtime.evaluate({
        'op': 'append',
        'args': [
          [1, 2],
          3,
        ],
      }),
      [1, 2, 3],
    );
  });

  test('disable, update and uninstall persist across restarts', () async {
    final plugins = PluginController();
    final c = canvas();
    addTearDown(plugins.dispose);
    addTearDown(c.dispose);
    await plugins.install(exampleSource(2));
    await plugins.execute('example.study-tools', 'highlight', c);
    await plugins.setEnabled('example.study-tools', false);
    await expectLater(
      plugins.execute('example.study-tools', 'highlight', c),
      throwsStateError,
    );
    await plugins.install(exampleSource(2), replace: true);
    expect(plugins.installed.single.enabled, isFalse);
    expect(plugins.installed.single.state['uses'], 1);
    final loaded = PluginController();
    await loaded.load();
    addTearDown(loaded.dispose);
    expect(loaded.installed.single.enabled, isFalse);
    await loaded.uninstall('example.study-tools');
    final empty = PluginController();
    await empty.load();
    addTearDown(empty.dispose);
    expect(empty.installed, isEmpty);
  });

  test('corrupt installed entries are isolated from healthy plugins', () async {
    SharedPreferences.setMockInitialValues({
      PluginController.storageKey: jsonEncode([
        {
          'manifest': {'broken': true},
        },
        {'manifest': pluginExamples[0], 'enabled': true, 'state': {}},
      ]),
    });
    final plugins = PluginController();
    await plugins.load();
    addTearDown(plugins.dispose);
    expect(plugins.installed, hasLength(1));
    expect(plugins.loadErrors, hasLength(1));
  });

  test('required input and types are validated before editing', () async {
    final plugins = PluginController();
    final c = canvas();
    addTearDown(plugins.dispose);
    addTearDown(c.dispose);
    await plugins.install(
      source(
        [
          {
            'action': 'text.add',
            'args': {
              'text': r'${input.title}',
              'size': {'var': 'input.size'},
            },
          },
        ],
        inputs: [
          {'id': 'title', 'type': 'text', 'label': 'Titolo', 'required': true},
          {
            'id': 'size',
            'type': 'number',
            'label': 'Dimensione',
            'default': 16,
          },
        ],
      ),
    );
    await expectLater(
      plugins.execute(
        'test.plugin',
        'run',
        c,
        input: {'title': 'A', 'size': 'bad'},
      ),
      throwsStateError,
    );
    await expectLater(
      plugins.execute('test.plugin', 'run', c),
      throwsStateError,
    );
    await plugins.execute(
      'test.plugin',
      'run',
      c,
      input: {'title': 'A', 'size': 20},
    );
    expect((content(c).single as XppText).size, 20);
  });

  test(
    'host API extensions preserve transaction and conflict protection',
    () async {
      final gate = Completer<void>();
      final entered = Completer<void>();
      final plugins = PluginController(
        extendApi: (api, session) {
          api.register('custom.wait', {}, (_) async {
            entered.complete();
            await gate.future;
            return null;
          });
        },
      );
      final c = canvas();
      addTearDown(plugins.dispose);
      addTearDown(c.dispose);
      await plugins.install(
        source([
          {'action': 'custom.wait'},
          {
            'action': 'text.add',
            'args': {'text': 'plugin'},
          },
        ]),
      );
      final execution = plugins.execute('test.plugin', 'run', c);
      final rejected = expectLater(execution, throwsStateError);
      await entered.future;
      await expectLater(plugins.install(exampleSource(0)), throwsStateError);
      c.addNewContent(
        0,
        XppText(
          text: 'user',
          offset: const Offset(1, 2),
          size: 12,
          color: Colors.black,
        ),
      );
      gate.complete();
      await rejected;
      expect((content(c).single as XppText).text, 'user');
      expect(c.undoStack, hasLength(1));
    },
  );

  test('execution targets the chosen page and controller only', () async {
    final plugins = PluginController();
    final primary = canvas();
    final secondary = canvas()..addPage();
    addTearDown(plugins.dispose);
    addTearDown(primary.dispose);
    addTearDown(secondary.dispose);
    await plugins.install(exampleSource(0));
    await plugins.execute(
      'example.date-stamp',
      'stamp',
      secondary,
      pageIndex: 1,
      input: {'title': 'Seconda'},
    );
    expect(content(primary), isEmpty);
    expect(content(secondary), isEmpty);
    expect(secondary.file!.pages![1].layers!.first.content, hasLength(1));
  });

  testWidgets('guided creator and command form work on a 380dp phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plugins = PluginController();
    await plugins.load();
    final c = canvas();
    addTearDown(plugins.dispose);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PluginManagerPage(plugins: plugins, canvas: c),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('plugin-create')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Il mio timbro');
    await tester.enterText(find.byType(TextField).last, 'Creato senza codice');
    await tester.tap(find.text('Installa'));
    await tester.pumpAndSettle();
    expect(plugins.installed, hasLength(1));
    await tester.tap(find.text('Il mio timbro').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Il mio timbro'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Il mio timbro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esegui'));
    await tester.pumpAndSettle();
    expect((content(c).single as XppText).text, 'Creato senza codice');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
