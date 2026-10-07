import 'plugin_manifest.dart';
import 'plugin_runtime.dart';

Future<void> runPluginScript(
  NotePlugin plugin,
  String handler,
  PluginApi api,
  Map<String, dynamic> context,
  Future<void> cancelled,
) async {
  throw UnsupportedError(
    'I plugin JavaScript richiedono l’app Android o desktop. I workflow JSON funzionano anche sul Web.',
  );
}
