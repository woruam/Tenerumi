import 'dart:convert';
import 'dart:typed_data';

import 'plugin_manifest.dart';
import '../src/bounded_archive.dart';

/// Package layout: manifest.json, main.js and additional relative JS modules.
/// Read in memory; no archive paths are ever extracted onto the filesystem.
NotePlugin decodePluginPackage(Uint8List bytes) {
  if (bytes.length > 2 * 1024 * 1024) {
    throw const FormatException('Pacchetto troppo grande');
  }
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
    return NotePlugin.parse(utf8.decode(bytes));
  }
  final decoded = decodeBoundedZip(
    bytes,
    maxInput: 2 * 1024 * 1024,
    maxOutput: 2 * 1024 * 1024,
    maxEntries: 65,
    entryLimit: (name) {
      if (name != 'manifest.json' &&
          !RegExp(r'^[a-zA-Z0-9_-]+(/[a-zA-Z0-9_-]+)*\.js$').hasMatch(name)) {
        throw const FormatException('Percorso non valido nel pacchetto');
      }
      return 2 * 1024 * 1024;
    },
  );
  final files = decoded.map(
    (name, content) => MapEntry(name, utf8.decode(content)),
  );
  final source = files.remove('manifest.json');
  if (source == null) throw const FormatException('manifest.json mancante');
  final manifest = jsonDecode(source) as Map<String, dynamic>;
  if (manifest['modules'] != null) {
    throw const FormatException(
      'I moduli del pacchetto devono essere file .js',
    );
  }
  manifest['runtime'] = 'javascript';
  manifest['modules'] = files;
  return NotePlugin.parse(jsonEncode(manifest));
}
