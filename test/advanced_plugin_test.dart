import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';
import 'package:xournalpp/plugins/plugin_examples.dart';
import 'package:xournalpp/plugins/plugin_latex.dart';
import 'package:xournalpp/plugins/plugin_manifest.dart';
import 'package:xournalpp/plugins/plugin_package.dart';
import 'package:xournalpp/plugins/plugin_services.dart';
import 'package:xournalpp/plugins/plugin_runtime.dart';

import 'plugin_system_test.dart' show canvas, content, source;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('script modules and handlers validated; traversal rejected', () {
    final js = jsonDecode(exampleSource(3)) as Map;
    expect(NotePlugin.parse(jsonEncode(js)).isJavaScript, true);
    js['modules'] = {'../main.js': 'export function run() {}'};
    expect(() => NotePlugin.parse(jsonEncode(js)), throwsFormatException);
    js['modules'] = {'main.js': ''};
    js['commands'][0]['handler'] = 'run();evil()';
    expect(() => NotePlugin.parse(jsonEncode(js)), throwsFormatException);
  });
  test('zip package loads multiple modules and refuses unexpected files', () {
    final manifest = jsonDecode(exampleSource(3)) as Map<String, dynamic>;
    final modules = manifest.remove('modules') as Map;
    final archive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
      ..addFile(ArchiveFile.string('main.js', modules['main.js'] as String))
      ..addFile(
        ArchiveFile.string('lib/helpers.js', 'export const answer=42;'),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    expect(decodePluginPackage(bytes).modules, hasLength(2));
    archive.addFile(ArchiveFile.string('../escape.js', 'bad'));
    expect(
      () =>
          decodePluginPackage(Uint8List.fromList(ZipEncoder().encode(archive))),
      throwsFormatException,
    );
  });
  test('Anki export escapes newlines, tabs, HTML and header injection', () {
    final tsv = ankiTsv([
      {'front': 'a\tb\nc < d', 'back': 'x & y', 'tags': 'tag\ninjected'},
    ], deck: 'Deck\n#html:false');
    expect(tsv, contains('a&#9;b<br>c &lt; d\tx &amp; y\ttag injected'));
    expect(tsv, contains('#deck:Deck #html:false\n'));
    expect(() => ankiTsv([]), throwsStateError);
    expect(
      () => ankiTsv([
        {'front': '', 'back': 'test'},
      ]),
      throwsStateError,
    );
  });
  test('file exports stay staged and disappear on error', () async {
    final plugins = PluginController();
    final c = canvas();
    addTearDown(plugins.dispose);
    addTearDown(c.dispose);
    await plugins.install(
      source(
        [
          {
            'action': 'anki.export',
            'args': {
              'cards': [
                {'front': 'Q', 'back': 'A'},
              ],
            },
          },
          {
            'action': 'text.add',
            'args': {'text': 'staged'},
          },
          {
            'action': 'content.delete',
            'args': {
              'ids': [999],
            },
          },
        ],
        permissions: ['export', 'document.write'],
      ),
    );
    await expectLater(
      plugins.execute('test.plugin', 'run', c),
      throwsStateError,
    );
    expect(content(c), isEmpty);
    expect(c.undoStack, isEmpty);
    await plugins.install(
      source(
        [
          {
            'action': 'anki.export',
            'args': {
              'cards': [
                {'front': 'Q', 'back': 'A'},
              ],
            },
          },
        ],
        permissions: ['export'],
      ),
      replace: true,
    );
    final result = await plugins.execute('test.plugin', 'run', c);
    expect(result.files.single.name, 'flashcard.tsv');
    expect(utf8.decode(result.files.single.bytes), contains('Q\tA\t'));
  });
  test('new host actions enforce permissions at dynamic invocation', () async {
    final api = PluginApi();
    var called = false;
    api.register('text.add', {'document.write'}, (_) {
      called = true;
      return null;
    });
    final js = jsonDecode(exampleSource(3)) as Map;
    js['permissions'] = [];
    await expectLater(
      api.invoke(NotePlugin.parse(jsonEncode(js)), 'text.add', {
        'text': 'not allowed',
      }),
      throwsStateError,
    );
    expect(called, false);
  });
  test(
    'async OCR and forms compose and late completions cannot edit canvas',
    () async {
      final plugins = PluginController();
      final c = canvas();
      addTearDown(plugins.dispose);
      addTearDown(c.dispose);
      await plugins.install(
        source(
          [
            {
              'action': 'ocr.recognize',
              'args': {'base64': base64Encode(kTransparentImage)},
              'as': 'recognized',
            },
            {
              'action': 'text.add',
              'args': {'text': r'${recognized.text}'},
            },
          ],
          permissions: ['ocr', 'document.write'],
        ),
      );
      final result = await plugins.execute(
        'test.plugin',
        'run',
        c,
        host: PluginHost(
          ocr: (b) async => {'text': 'Recognized text', 'blocks': []},
        ),
      );
      expect(result.content.single.toString(), isNotEmpty);
      expect(result.active, false);
      c.undo();
      expect(content(c), isEmpty);
      final done = Completer<Map<String, dynamic>>();
      final execution = plugins.execute(
        'test.plugin',
        'run',
        c,
        host: PluginHost(ocr: (_) => done.future),
      );
      final assertion = expectLater(execution, throwsStateError);
      plugins.cancel();
      done.complete({'text': 'late'});
      await assertion;
      expect(content(c), isEmpty);
    },
  );
  test(
    'network calls reject undeclared hosts before contacting server',
    () async {
      final plugins = PluginController();
      final c = canvas();
      addTearDown(plugins.dispose);
      addTearDown(c.dispose);
      await plugins.install(
        source(
          [
            {
              'action': 'http.request',
              'args': {'url': 'https://example.com'},
            },
          ],
          permissions: ['network'],
        ),
      );
      await expectLater(
        plugins.execute('test.plugin', 'run', c),
        throwsStateError,
      );
    },
  );
  test('page render includes staged content and produces an image for OCR providers', () async {
    Map<String, dynamic>? rendered;
    final plugins = PluginController(
      extendApi: (api, session) {
        api.register('test.capture', {}, (args) {
          rendered = args;
          return null;
        });
      },
    );
    final c = canvas();
    addTearDown(plugins.dispose);
    addTearDown(c.dispose);
    await plugins.install(
      source(
        [
          {
            'action': 'text.add',
            'args': {'text': 'OCR input'},
          },
          {'action': 'page.render', 'as': 'png'},
          {
            'action': 'test.capture',
            'args': {'var': 'png'},
          },
        ],
        permissions: ['document.read', 'document.write'],
      ),
    );
    await plugins.execute('test.plugin', 'run', c);
    expect(rendered!['width'], 300);
    expect(
      base64Decode(rendered!['base64'] as String).length,
      greaterThan(100),
    );
    expect(content(c), hasLength(1));
    c.undo();
    expect(content(c), isEmpty);
  });
  testWidgets(
    'LaTeX renderer produces actual fraction PNG and rejects invalid syntax',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(() async {
        final rendered = await renderPluginLatex({
          'text': r'\frac{a}{b} + \sqrt{x}',
        });
        expect(base64Decode(rendered['base64'] as String).take(8), [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
        expect(rendered['height'] as double, greaterThan(24));
        await expectLater(
          renderPluginLatex({'text': r'\unknowncommand{'}),
          throwsFormatException,
        );
      });
      expect(tester.takeException(), isNull);
    },
  );
}
