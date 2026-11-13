import '../document_limits.dart';
import '../responsive_hash.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'internal_storage_io.dart' as storage;

Future<Directory> _root() async {
  final root = Directory(await storage.resolve('state-v2'));
  await root.create(recursive: true);
  return root;
}

String _unique() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
Map _decodeEnvelope(String text) {
  validateDocumentJsonText(text);
  return jsonDecode(text);
}

Future<Map<String, dynamic>> readState() async {
  final root = await _root();
  final files = await root
      .list()
      .where((e) => e is File && e.path.endsWith('.commit'))
      .cast<File>()
      .toList();
  files.sort((a, b) => b.path.compareTo(a.path));
  for (final file in files) {
    try {
      final envelope = _decodeEnvelope(
        utf8.decode(
          await storage.readFile(file.path, maxBytes: 24 * 1024 * 1024),
        ),
      );
      final payload = envelope['payload'] as String;
      if (envelope['schema'] != 2 ||
          sha256.convert(utf8.encode(payload)).toString() != envelope['sha256'])
        throw const FormatException('Commit incompleto');
      validateDocumentJsonText(payload);
      return Map<String, dynamic>.from(jsonDecode(payload) as Map);
    } catch (_) {
      // Keep evidence and fall back to the preceding complete generation.
      await file.rename('${file.path}.quarantine');
      warnings.add(
        'Archivio danneggiato: generazione precedente recuperata, originale conservato.',
      );
    }
  }
  return {};
}

Future<void> writeState(Map<String, dynamic> state) async {
  final root = await _root();
  final payload = jsonEncode(state);
  final encoded = utf8.encode(
    jsonEncode({
      'schema': 2,
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
      'payload': payload,
    }),
  );
  if (encoded.length > 24 * 1024 * 1024)
    throw StateError('Limite dei metadati raggiunto');
  final existing = await root
      .list()
      .where((e) => e is File && e.path.endsWith('.commit'))
      .toList();
  var generation = 0;
  for (final e in existing) {
    final number = int.tryParse(e.uri.pathSegments.last.split('-').first) ?? 0;
    if (number > generation) generation = number;
  }
  final path =
      '${root.path}/${(generation + 1).toString().padLeft(20, '0')}-${Random.secure().nextInt(1 << 32)}.commit';
  await storage.writeFile(path, Uint8List.fromList(encoded));
  // No file referenced by an earlier committed generation is deleted here.
  // Compact metadata only: retain the two prior complete commits as fallback.
  final files = await root
      .list()
      .where((e) => e is File && e.path.endsWith('.commit'))
      .cast<File>()
      .toList();
  files.sort((a, b) => b.path.compareTo(a.path));
  for (final file in files.skip(3)) {
    try {
      await file.delete();
    } catch (_) {}
  }
}

Future<void> quarantine(String raw) async {
  final root = await _root();
  await storage.writeFile(
    '${root.path}/${_unique()}.quarantine',
    Uint8List.fromList(utf8.encode(raw)),
  );
}

final _usage = <String, int>{};
Future<String> putBlob(Uint8List bytes) async {
  final root = await _root();
  final key = await responsiveHash(bytes);
  final file = File('${root.path}/$key.blob');
  if (!await file.exists()) {
    var used = _usage[root.path] ?? 0;
    if (!_usage.containsKey(root.path)) {
      await for (final entry in root.list()) {
        if (entry is File) used += await entry.length();
      }
    }
    if (used + bytes.length > 960 * 1024 * 1024)
      throw StateError(
        'Archivio dei recuperi pieno: esportare un backup prima di liberare spazio',
      );
    await storage.writeFile(file.path, bytes);
    _usage[root.path] = used + bytes.length;
  }
  return key;
}

Future<Uint8List> getBlob(String key) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key))
    throw const FormatException('Identificatore blob invalido');
  final bytes = await storage.readFile('${(await _root()).path}/$key.blob');
  if (await responsiveHash(bytes) != key)
    throw const FormatException('Recupero corrotto');
  return bytes;
}

Future<String?> blobFilePath(String key) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) return null;
  final file = File('${(await _root()).path}/$key.blob');
  return (await file.exists()) ? file.path : null;
}

Future<void> stageRecovery(Map<String, dynamic> entry) async {
  final root = await _root();
  final payload = jsonEncode(entry);
  await storage.writeFile(
    '${root.path}/${_unique()}.recovery',
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'payload': payload,
          'sha256': sha256.convert(utf8.encode(payload)).toString(),
        }),
      ),
    ),
  );
}

Future<List<Map<String, dynamic>>> stagedRecoveries() async {
  final root = await _root();
  final entries = <Map<String, dynamic>>[];
  await for (final file in root.list()) {
    if (file is! File || !file.path.endsWith('.recovery')) continue;
    try {
      final v = _decodeEnvelope(
        utf8.decode(await storage.readFile(file.path, maxBytes: 1024 * 1024)),
      );
      final raw = v['payload'] as String;
      if (sha256.convert(utf8.encode(raw)).toString() != v['sha256'])
        throw const FormatException('Manifesto corrotto');
      entries.add(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      await file.rename('${file.path}.quarantine');
    }
  }
  return entries;
}

final warnings = <String>[];
Future<bool> hasBlob(String hash) async =>
    File('${(await _root()).path}/$hash.blob').exists();
Future<List<Map<String, dynamic>>> retainedStates() async {
  final states = <Map<String, dynamic>>[];
  await for (final file in (await _root()).list()) {
    if (file is! File || !file.path.endsWith('.commit')) continue;
    final envelope = _decodeEnvelope(await file.readAsString());
    final payload = envelope['payload'] as String;
    if (sha256.convert(utf8.encode(payload)).toString() != envelope['sha256'])
      throw const FormatException('Commit corrotto');
    states.add(Map<String, dynamic>.from(jsonDecode(payload) as Map));
  }
  return states;
}

Future<void> compact(
  Set<String> live,
  List<Map<String, dynamic>> retained,
) async {
  _usage.clear();
  final tokens = retained.map((e) => e['token']).toSet();
  final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
  await for (final file in (await _root()).list()) {
    if (file is! File) continue;
    // A grace interval protects fragments written outside an autosave lease.
    if (!(await file.lastModified()).isBefore(cutoff)) continue;
    final name = file.uri.pathSegments.last;
    if (RegExp(r'^[a-f0-9]{64}\.blob$').hasMatch(name) &&
        !live.contains(name.substring(0, 64))) {
      await file.delete();
    } else if (name.endsWith('.recovery')) {
      final envelope = _decodeEnvelope(await file.readAsString());
      final entry = jsonDecode(envelope['payload'] as String) as Map;
      if (!tokens.contains(entry['token'])) await file.delete();
    }
  }
}

Future<void> stageLibrary(Map<String, dynamic> entry) async {
  final key = sha256.convert(utf8.encode(entry['path'] as String)).toString();
  final payload = jsonEncode(entry);
  await storage.writeFile(
    '${(await _root()).path}/$key.library',
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'payload': payload,
          'sha256': sha256.convert(utf8.encode(payload)).toString(),
        }),
      ),
    ),
  );
}

Future<List<Map<String, dynamic>>> libraryCandidates() async {
  final rows = <Map<String, dynamic>>[];
  await for (final file in (await _root()).list()) {
    if (file is! File || !file.path.endsWith('.library')) continue;
    try {
      final envelope = _decodeEnvelope(
        utf8.decode(await storage.readFile(file.path, maxBytes: 1024 * 1024)),
      );
      final payload = envelope['payload'] as String;
      if (sha256.convert(utf8.encode(payload)).toString() != envelope['sha256'])
        throw const FormatException('Indice appunto corrotto');
      rows.add(Map<String, dynamic>.from(jsonDecode(payload) as Map));
    } catch (_) {
      await file.rename('${file.path}.quarantine');
    }
  }
  return rows;
}

Future<void> forgetLibrary(String path) async {
  final key = sha256.convert(utf8.encode(path)).toString();
  final file = File('${(await _root()).path}/$key.library');
  if (await file.exists()) await file.delete();
}
