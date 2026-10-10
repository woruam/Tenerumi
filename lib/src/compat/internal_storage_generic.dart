import 'dart:typed_data';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Web fallback: there is no local file system. Opened files live in memory
/// only; restored backup notes also persist in browser preferences. Exports
/// still use download (`exportToStorage`).
Future<String> resolve(String path) async => path;

final _sessionFiles = <String, Uint8List>{};
String? _restoredKey(String path) =>
    path.startsWith('backup-') && !path.contains('/') && !path.contains('\\')
    ? 'osipp.web-restored.$path'
    : null;

Future<bool> exists(String path) async {
  final key = _restoredKey(path);
  return _sessionFiles.containsKey(path) ||
      (key != null && (await SharedPreferences.getInstance()).containsKey(key));
}

Future<DateTime?> lastModified(String path) async => null;

Future<Uint8List> readFile(String path) async {
  final key = _restoredKey(path);
  if (key != null) {
    final stored = (await SharedPreferences.getInstance()).getString(key);
    if (stored != null) return base64Decode(stored);
  }
  if (_sessionFiles.containsKey(path)) return _sessionFiles[path]!;
  throw UnsupportedError('Local files are not available on this platform.');
}

Future<void> writeFile(String path, Uint8List bytes) async {
  final key = _restoredKey(path);
  if (key != null &&
      !await (await SharedPreferences.getInstance()).setString(
        key,
        base64Encode(bytes),
      )) {
    throw StateError(
      'Spazio insufficiente per ripristinare l’appunto nel browser.',
    );
  }
  _sessionFiles[path] = bytes;
}

Future<void> writeFileIfMissing(String path, Uint8List bytes) async {}

Future<void> deleteFile(String path) async {
  final key = _restoredKey(path);
  if (key != null &&
      !await (await SharedPreferences.getInstance()).remove(key)) {
    throw StateError('Impossibile eliminare l’appunto ripristinato.');
  }
  _sessionFiles.remove(path);
}
