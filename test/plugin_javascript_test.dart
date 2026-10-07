import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fjs/fjs.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';
import 'package:xournalpp/plugins/plugin_examples.dart';
import 'package:xournalpp/plugins/plugin_services.dart';
import 'package:xournalpp/plugins/plugin_script_native.dart'
    show initializePluginJavaScript;

import 'plugin_system_test.dart' show canvas, content;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library =
      Platform.environment['PLUGIN_FJS_LIBRARY'] ??
      'build/plugin-test-native/fjs.dll';
  final available = File(library).existsSync();
  setUpAll(() async {
    if (available) {
      await initializePluginJavaScript(
        initialize: () => LibFjs.init(
          externalLibrary: ExternalLibrary.open(File(library).absolute.path),
        ),
      );
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  String js(
    String code, {
    List<String> permissions = const ['document.write', 'storage'],
    Map<String, String> extra = const {},
  }) => jsonEncode({
    'apiVersion': 1,
    'id': 'test.javascript',
    'name': 'JS',
    'version': '1',
    'runtime': 'javascript',
    'permissions': permissions,
    'modules': {'main.js': code, ...extra},
    'commands': [
      {'id': 'run', 'label': 'Run', 'handler': 'run'},
    ],
  });
  test(
    'real JavaScript supports imports, loops, async host calls and single undo',
    () async {
      final plugins = PluginController();
      final c = canvas();
      addTearDown(plugins.dispose);
      addTearDown(c.dispose);
      await plugins.install(
        js(
          r'''
import { label } from './helpers.js';
export async function run(context) {
  const words = ['one', 'two', 'three'].map(x => label(x));
  for (let i=0;i<words.length;i++) await osipp.call('text.add', {text: words[i], x:40, y:40+i*20});
  await osipp.call('state.set', {key:'count',value:words.length});
}
''',
          extra: {
            'helpers.js': 'export const label = value => value.toUpperCase();',
          },
        ),
      );
      await plugins.execute('test.javascript', 'run', c);
      expect(content(c).cast<XppText>().map((t) => t.text), [
        'ONE',
        'TWO',
        'THREE',
      ]);
      expect(c.undoStack, hasLength(1));
      c.undo();
      expect(content(c), isEmpty);
      expect(plugins.installed.single.state['count'], 3);
    },
    skip: available ? false : 'Build/fetch the native FJS test library first',
  );
  test(
    'real JS exceptions and missing permissions roll back the whole command',
    () async {
      final plugins = PluginController();
      final c = canvas();
      addTearDown(plugins.dispose);
      addTearDown(c.dispose);
      await plugins.install(
        js(
          "export async function run() {await osipp.call('text.add',{text:'staged'}); await osipp.call('state.set',{key:'x',value:1}); throw new Error('failed');}",
        ),
      );
      await expectLater(
        plugins.execute('test.javascript', 'run', c),
        throwsA(anything),
      );
      expect(content(c), isEmpty);
      expect(plugins.installed.single.state, isEmpty);
      await plugins.install(
        js(
          "export async function run() { await osipp.call('text.add',{text:'forbidden'}); }",
          permissions: [],
        ),
        replace: true,
      );
      await expectLater(
        plugins.execute('test.javascript', 'run', c),
        throwsA(anything),
      );
      expect(content(c), isEmpty);
    },
    skip: available ? false : 'Native FJS test library unavailable',
  );
  test('native interrupt cancels an infinite loop and a following plugin still runs', () async {
    final plugins = PluginController();
    final c = canvas();
    addTearDown(plugins.dispose);
    addTearDown(c.dispose);
    final entered = Completer<void>();
    final custom = PluginController(
      extendApi: (api, s) => api.register('test.entered', {}, (_) {
        entered.complete();
        return null;
      }),
    );
    addTearDown(custom.dispose);
    await custom.install(
      js(
        "export async function run(){ await osipp.call('text.add',{text:'staged'});await osipp.call('test.entered'); while(true){} }",
      ),
    );
    final execution = custom.execute('test.javascript', 'run', c);
    final failed = expectLater(execution, throwsA(anything));
    await entered.future;
    custom.cancel();
    await failed.timeout(const Duration(seconds: 10));
    expect(content(c), isEmpty);
    expect(custom.running, false);
    await plugins.install(
      js(
        "export async function run(){await osipp.call('text.add',{text:'after cancellation'});} ",
      ),
      replace: true,
    );
    await plugins.execute('test.javascript', 'run', c);
    expect(content(c), hasLength(1));
  }, skip: available ? false : 'Native FJS test library unavailable');
  test('shipped LaTeX, Anki and OCR scripts execute through asynchronous providers', () async {
    final plugins = PluginController();
    final c = canvas();
    addTearDown(plugins.dispose);
    addTearDown(c.dispose);
    for (var i = 3; i < pluginExamples.length; i++) {
      await plugins.install(exampleSource(i));
    }
    await plugins.execute(
      'example.latex',
      'insert',
      c,
      host: PluginHost(
        form: (_) async => {'formula': r'\frac{a}{b}', 'size': 24},
        preview: (_) async => true,
        latex: (_) async => {
          'base64': base64Encode(kTransparentImage),
          'width': 40,
          'height': 30,
        },
      ),
    );
    expect(content(c), hasLength(1));
    await plugins.execute(
      'example.anki',
      'add',
      c,
      host: PluginHost(form: (_) async => {'front': 'Q', 'back': 'A'}),
    );
    final anki = await plugins.execute('example.anki', 'export', c);
    expect(anki.files.single.name, 'flashcard.tsv');
    await plugins.execute(
      'example.ocr',
      'recognize',
      c,
      host: PluginHost(
        openFile: (_) async => {'base64': base64Encode(kTransparentImage)},
        ocr: (_) async => {'text': 'recognized', 'blocks': []},
        form: (_) async => {'text': 'corrected'},
      ),
    );
    expect((content(c).last as XppText).text, 'corrected');
  }, skip: available ? false : 'Native FJS test library unavailable');
}
