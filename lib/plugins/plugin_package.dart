import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'plugin_manifest.dart';

/// Package layout: manifest.json, main.js and additional relative JS modules.
/// Read in memory; no archive paths are ever extracted onto the filesystem.
NotePlugin decodePluginPackage(Uint8List bytes) {
  if (bytes.length > 2 * 1024 * 1024) {
    throw const FormatException('Pacchetto troppo grande');
  }
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
    return NotePlugin.parse(utf8.decode(bytes));
  }
  final archive = ZipDecoder().decodeBytes(bytes);
  if (archive.length > 65) {
    throw const FormatException('Troppi file nel pacchetto');
  }
  var size = 0;
  final files = <String, String>{};
  for (final file in archive) {
    if (!file.isFile) continue;
    if (file.name != 'manifest.json' &&
        !RegExp(r'^[a-zA-Z0-9_-]+(/[a-zA-Z0-9_-]+)*\.js$')
            .hasMatch(file.name)) {
      throw const FormatException('Percorso non valido nel pacchetto');
    }
    size += file.size;
    if (size > 2 * 1024 * 1024 || files.containsKey(file.name)) {
      throw const FormatException('Pacchetto troppo grande o file duplicato');
    }
    files[file.name] = utf8.decode(file.content);
  }
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
