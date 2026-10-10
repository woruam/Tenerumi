import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';
import 'package:xournalpp/plugins/plugin_examples.dart';
import 'package:xournalpp/plugins/plugin_script.dart';
import 'package:xournalpp/plugins/plugin_script_native.dart' as native;
import 'package:xournalpp/plugins/plugin_runtime.dart';
import 'package:xournalpp/plugins/plugin_services.dart';

import 'plugin_system_test.dart' show canvas, content;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'osipp.javascript.enabled': true,
      'osipp.plugins.unsafe': true,
    }),
  );
  test(
    'JavaScript cannot execute despite permissions and bypass flags',
    () async {
      final plugins = PluginController();
      final c = canvas();
      addTearDown(plugins.dispose);
      addTearDown(c.dispose);
      final manifest = jsonDecode(exampleSource(3)) as Map;
      manifest['permissions'] = [
        'document.read',
        'document.write',
        'storage',
        'network',
        'export',
        'ui',
      ];
      manifest['unsafe'] = true;
      manifest['allowJavaScript'] = true;
      manifest['modules'] = {
        'main.js': "export async function insert(){await osipp.call('text.add',{text:'unsafe'});}",
      };
      await plugins.install(jsonEncode(manifest));
      await expectLater(
        plugins.execute('example.latex', 'insert', c),
        throwsUnsupportedError,
      );
      expect(pluginJavaScriptAvailable, false);
      expect(content(c), isEmpty);
      expect(c.undoStack, isEmpty);
      expect(plugins.installed.single.state, isEmpty);
      expect(plugins.running, false);
    },
  );
  test('direct native runner is blocked without initializing FJS', () async {
    final controller = PluginController();
    addTearDown(controller.dispose);
    final p = controller.validateSource(exampleSource(3));
    await expectLater(
      native.runPluginScript(p, 'insert', PluginApi(), {}, Future.value()),
      throwsUnsupportedError,
    );
  });
  test('LaTeX and OCR examples run as safe host workflows', () async {
    final plugins = PluginController();
    final c = canvas();
    addTearDown(plugins.dispose);
    addTearDown(c.dispose);
    for (final id in ['example.latex', 'example.ocr']) {
      final index = pluginExamples.indexWhere((p) => p['id'] == id);
      await plugins.install(workflowExampleSource(index));
    }
    await plugins.execute(
      'example.latex',
      'insert',
      c,
      input: {'formula': r'\frac{a}{b}', 'size': 24},
      host: PluginHost(
        latex: (_) async => {
          'base64': base64Encode(kTransparentImage),
          'width': 40,
          'height': 30,
        },
      ),
    );
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
    expect(content(c), hasLength(2));
    expect((content(c).last as XppText).text, 'corrected');
  });
}
