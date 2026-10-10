import 'plugin_manifest.dart';
import 'plugin_runtime.dart';

typedef PluginScriptRunner = Future<void> Function(
  NotePlugin plugin,
  String handler,
  PluginApi api,
  Map<String, dynamic> context,
  Future<void> cancelled,
);

/// FJS 3.2.0 has a filesystem module-loader fallback even with no builtins.
/// Fail closed until a restricted loader and OS-isolated backend are verified.
const pluginJavaScriptAvailable = false;

Future<void> runPluginScript(
  NotePlugin plugin,
  String handler,
  PluginApi api,
  Map<String, dynamic> context,
  Future<void> cancelled,
) async {
  throw UnsupportedError(
    'Esecuzione JavaScript sospesa per sicurezza: il motore attuale può '
    'importare file esterni al plugin. Usa un workflow JSON.',
  );
}
