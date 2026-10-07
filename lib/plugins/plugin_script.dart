import 'plugin_script_stub.dart'
    if (dart.library.io) 'plugin_script_native.dart'
    as platform;
import 'plugin_manifest.dart';
import 'plugin_runtime.dart';

typedef PluginScriptRunner = Future<void> Function(
  NotePlugin plugin,
  String handler,
  PluginApi api,
  Map<String, dynamic> context,
  Future<void> cancelled,
);

Future<void> runPluginScript(
  NotePlugin plugin,
  String handler,
  PluginApi api,
  Map<String, dynamic> context,
  Future<void> cancelled,
) => platform.runPluginScript(plugin, handler, api, context, cancelled);
