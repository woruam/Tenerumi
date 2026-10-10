import 'dart:io';
import 'dart:convert';

import 'package:fjs/fjs.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = File(
    Platform.environment['PLUGIN_FJS_LIBRARY'] ??
        'build/plugin-test-native/fjs.dll',
  );
  test('audit reproduces the unsafe engine loader using a harmless marker', () async {
    final folder = await Directory.systemTemp.createTemp('osipp-loader-audit-');
    try {
      final fixture = File('${folder.path}/marker.js');
      await fixture.writeAsString('export const marker = "local-file-loaded";');
      await LibFjs.init(
        externalLibrary: ExternalLibrary.open(library.absolute.path),
      );
      final engine = await JsEngine.create(builtins: const JsBuiltinOptions());
      try {
        await engine.init(bridge: (_) => JsResult.ok(JsValue.none()));
        final base = Directory.current.absolute.path.split(Platform.pathSeparator);
        final target = fixture.absolute.path.split(Platform.pathSeparator);
        var common = 0;
        while (common < base.length && common < target.length && base[common] == target[common]) { common++; }
        final relative = [...List.filled(base.length - common, '..'), ...target.skip(common)].join('/');
        var loaded = false;
        for (final path in [
          fixture.path.replaceAll('\\', '/'),
          fixture.uri.toString(),
          './$relative',
        ]) {
          try {
            final value = await engine
                .eval(
                  source: JsCode.code('(async () => { const m = await import(${jsonEncode(path)}); return m.marker; })();'),
                  options: JsEvalOptions.withPromise(),
                )
                .timeout(const Duration(seconds: 5));
            if (value.value == 'local-file-loaded') loaded = true;
          } catch (_) { /* Different spellings can be rejected by the loader. */ }
        }
        expect(loaded, true, reason: 'Review this audit if the pinned engine changes.');
      } finally {
        await engine.close();
      }
    } finally {
      await folder.delete(recursive: true);
    }
  }, skip: library.existsSync() ? false : 'Native FJS library unavailable');
}
