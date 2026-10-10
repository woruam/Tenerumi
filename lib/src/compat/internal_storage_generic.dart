import 'dart:typed_data';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../critical_data.dart';

import 'package:crypto/crypto.dart';

/// Web fallback: there is no local file system. Opened files live in memory
/// only; restored backup notes persist in transactional IndexedDB blobs. Exports
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
      (key != null && await CriticalData.read(key) is String) ||
      (key != null && (await SharedPreferences.getInstance()).containsKey(key));
}

Future<DateTime?> lastModified(String path) async => null;
Future<String> hashFile(
  String path, {
  int maxBytes = 128 * 1024 * 1024,
}) async => sha256.convert(await readFile(path, maxBytes: maxBytes)).toString();

Future<Uint8List> readFile(
  String path, {
  int maxBytes = 128 * 1024 * 1024,
}) async {
  final key = _restoredKey(path);
  if (key != null) {
    final blob = await CriticalData.read(key);
    if (blob is String) {
      final bytes = await CriticalData.getBlob(blob);
      if (bytes.length > maxBytes)
        throw const FormatException('File troppo grande');
      return bytes;
    }
    final stored = (await SharedPreferences.getInstance()).getString(key);
    if (stored != null) {
      if (stored.length > ((maxBytes + 2) ~/ 3) * 4) {
        throw const FormatException('File troppo grande');
      }
      final bytes = base64Decode(stored);
      if (bytes.length > maxBytes) {
        throw const FormatException('File troppo grande');
      }
      return bytes;
    }
  }
  if (_sessionFiles.containsKey(path)) {
    final bytes = _sessionFiles[path]!;
    if (bytes.length > maxBytes) {
      throw const FormatException('File troppo grande');
    }
    return bytes;
  }
  throw UnsupportedError('Local files are not available on this platform.');
}

Future<void> writeFile(String path, Uint8List bytes) async {
  final key = _restoredKey(path);
  if (key != null) {
    await CriticalData.blobTransaction(() async {
      final blob = await CriticalData.putBlob(bytes);
      await CriticalData.write(key, blob);
    });
  } else {
    _sessionFiles[path] = bytes;
  }
}

Future<void> writeFileIfMissing(String path, Uint8List bytes) async {}

Future<void> deleteFile(String path) async {
  final key = _restoredKey(path);
  if (key != null) await CriticalData.write(key, null);
  if (key != null &&
      !await (await SharedPreferences.getInstance()).remove(key)) {
    throw StateError('Impossibile eliminare l’appunto ripristinato.');
  }
  _sessionFiles.remove(path);
}
