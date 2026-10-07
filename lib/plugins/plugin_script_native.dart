import 'dart:async';
import 'dart:convert';

import 'package:fjs/fjs.dart';

import 'plugin_manifest.dart';
import 'plugin_runtime.dart';

Future<void>? _initialization;
Future<void> initializePluginJavaScript({
  Future<void> Function()? initialize,
}) => _initialization ??= (initialize ?? LibFjs.init)();

/// A fresh engine per command. No filesystem, network, process or timer builtins.
/// Closing the engine requests QuickJS's native interrupt even in a tight loop.
Future<void> runPluginScript(
  NotePlugin plugin,
  String handler,
  PluginApi api,
  Map<String, dynamic> context,
  Future<void> cancelled,
) async {
  await initializePluginJavaScript();
  final engine = await JsEngine.create(
    builtins: const JsBuiltinOptions(),
    runtimeOptions: JsEngineRuntimeOptions(
      memoryLimit: BigInt.from(64 * 1024 * 1024),
      maxStackSize: BigInt.from(512 * 1024),
    ),
    modules: [
      for (final entry in plugin.modules.entries)
        JsModule.code(module: entry.key, code: entry.value),
    ],
  );
  var active = true;
  var calls = 0;
  var pending = 0;
  Future<void> queue = Future.value();
  try {
    await engine.init(
      bridge: (value) async {
        pending++;
        final previous = queue;
        final done = Completer<void>();
        queue = done.future;
        try {
          await previous;
          if (!active || ++calls > 2000) {
            throw StateError('Comando interrotto o troppe chiamate API');
          }
          final raw = value.value;
          if (raw is! String || raw.length > 12 * 1024 * 1024) {
            throw StateError('Richiesta API non valida');
          }
          final request = jsonDecode(raw) as Map;
          final result = await api.invoke(
            plugin,
            request['action'] as String,
            Map<String, dynamic>.from(request['args'] as Map? ?? {}),
          );
          if (!active) throw StateError('Comando interrotto');
          final encoded = jsonEncode(result);
          if (encoded.length > 12 * 1024 * 1024) {
            throw StateError('Risposta API troppo grande');
          }
          return JsResult.ok(JsValue.string(encoded));
        } catch (error) {
          return JsResult.err(JsError.bridge('$error'));
        } finally {
          pending--;
          done.complete();
        }
      },
    );
    final contextJson = jsonEncode(context);
    final module = jsonEncode(plugin.manifest['entry'] ?? 'main.js');
    final method = jsonEncode(handler);
    final operation = engine.eval(
      source: JsCode.code('''
      globalThis.osipp = Object.freeze({
        call: async (action, args = {}) => JSON.parse(await fjs.bridge_call(JSON.stringify({action, args})))
      });
      const plugin = await import($module);
      await plugin[$method]($contextJson);
      null;
    '''),
      options: JsEvalOptions.withPromise(),
    );
    await Future.any([
      operation,
      cancelled.then<JsValue>((_) => throw StateError('Comando annullato')),
    ]).timeout(const Duration(minutes: 2));
    if (pending != 0) {
      throw StateError('Usare await per ogni chiamata osipp.call');
    }
  } finally {
    active = false;
    await engine.close();
  }
}
