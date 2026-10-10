import 'plugin_manifest.dart';
import 'plugin_runtime.dart';

/// No engine receives plugin source. Manifests and preferences cannot enable it.
Future<void> runPluginScript(
  NotePlugin plugin,
  String handler,
  PluginApi api,
  Map<String, dynamic> context,
  Future<void> cancelled,
) async {
  throw UnsupportedError(
    'JavaScript sospeso per sicurezza. Usa un workflow JSON.',
  );
}
