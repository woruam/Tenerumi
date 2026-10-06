import 'dart:typed_data';

/// Web fallback: there is no local file system. Opened files live in memory
/// only; persisting documents on the web is done via download
/// (`exportToStorage`).
Future<String> resolve(String path) async => path;

final _sessionFiles = <String, Uint8List>{};

Future<bool> exists(String path) async => _sessionFiles.containsKey(path);

Future<Uint8List> readFile(String path) async {
  if (_sessionFiles.containsKey(path)) return _sessionFiles[path]!;
  throw UnsupportedError('Local files are not available on this platform.');
}

Future<void> writeFile(String path, Uint8List bytes) async {
  _sessionFiles[path] = bytes;
}

Future<void> writeFileIfMissing(String path, Uint8List bytes) async {}

Future<void> deleteFile(String path) async {
  _sessionFiles.remove(path);
}
