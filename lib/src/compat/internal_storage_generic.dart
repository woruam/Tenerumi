import 'dart:typed_data';

/// Web fallback: there is no local file system. Opened files live in memory
/// only; persisting documents on the web is done via download
/// (`exportToStorage`).
Future<String> resolve(String path) async => path;

Future<Uint8List> readFile(String path) async {
  throw UnsupportedError('Local files are not available on this platform.');
}

Future<void> writeFile(String path, Uint8List bytes) async {
  throw UnsupportedError(
      'Saving local files is not supported on this platform. Use exportToStorage() instead.');
}

Future<void> writeFileIfMissing(String path, Uint8List bytes) async {}

Future<void> deleteFile(String path) async {}
