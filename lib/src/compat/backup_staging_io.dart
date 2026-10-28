import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

import '../bounded_archive.dart';
import '../document_limits.dart';
import 'internal_storage_io.dart' as storage;

const supportsDiskStaging = true;
Future<String> createStaging() async {
  final base = Directory(await storage.resolve('backup-staging'));
  await base.create(recursive: true);
  var used = 0;
  await for (final file in base.list(recursive: true, followLinks: false)) {
    if (file is File) used += await file.length();
  }
  if (used > 1024 * 1024 * 1024)
    throw StateError(
      'Staging dei backup pieno: liberare spazio prima di continuare',
    );
  final root = Directory(
    '${base.path}/${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
  );
  await root.create();
  return root.path;
}

Future<void> checkQuota(String directory, int additional) async {
  final base = Directory(directory).parent;
  var used = 0;
  await for (final entry in base.list(recursive: true, followLinks: false)) {
    if (entry is File) used += await entry.length();
  }
  if (used + additional > 1024 * 1024 * 1024)
    throw StateError('Limite dello staging raggiunto');
}

class StagedZipWriter {
  StagedZipWriter(this.directory) {
    _encoder.create(path, level: ZipFileEncoder.store);
  }
  final String directory;
  final _encoder = ZipFileEncoder();
  int total = 0;
  bool _closed = false;
  String get path => '$directory/backup.zip';
  Future<void> add(String name, Uint8List bytes) async {
    if (total + bytes.length > 512 * 1024 * 1024)
      throw StateError('Backup oltre 512 MiB');
    await checkQuota(directory, bytes.length);
    total += bytes.length;
    _encoder.addArchiveFile(ArchiveFile.noCompress(name, bytes.length, bytes));
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      await _encoder.close();
    }
  }
}

Future<Map<String, dynamic>> inspectArchive(String path) async {
  final root = await createStaging();
  try {
    return await compute(_extract, {'path': path, 'root': root});
  } catch (_) {
    await disposeStaging(root);
    rethrow;
  }
}

Map<String, dynamic> _extract(Map<String, String> args) {
  var occupied = 0;
  for (final f in Directory(
    args['root']!,
  ).parent.listSync(recursive: true, followLinks: false)) {
    if (f is File) occupied += f.lengthSync();
  }
  var extractedBytes = 0;
  final input = InputFileStream(args['path']!);
  final paths = <String, String>{};
  try {
    decodeBoundedZipStream(
      input,
      maxInput: 513 * 1024 * 1024,
      maxOutput: 512 * 1024 * 1024,
      maxEntries: 10001,
      entryLimit: (name) {
        if (name == 'manifest.json') return 8 * 1024 * 1024;
        if (RegExp(r'^notes/[0-9]+\.xopp$').hasMatch(name))
          return DocumentLimits.standard.compressedBytes;
        throw const FormatException('Percorso backup non valido');
      },
      onEntry: (name, bytes) {
        extractedBytes += bytes.length;
        if (occupied + extractedBytes > 1024 * 1024 * 1024)
          throw StateError('Limite dello staging raggiunto');
        final leaf = name == 'manifest.json'
            ? 'manifest.json'
            : '${name.split('/').last}';
        final file = File('${args['root']}/$leaf');
        file.writeAsBytesSync(bytes, flush: true);
        paths[name] = file.path;
      },
    );
    final manifestPath = paths.remove('manifest.json');
    if (manifestPath == null) throw const FormatException('Manifesto mancante');
    return {
      'manifestText': File(manifestPath).readAsStringSync(),
      'paths': paths,
      'root': args['root'],
    };
  } finally {
    input.closeSync();
  }
}

Future<Uint8List> readStaged(String path) =>
    storage.readFile(path, maxBytes: DocumentLimits.standard.compressedBytes);
Future<void> disposeStaging(String root) async {
  final base = Directory(await storage.resolve('backup-staging')).absolute.path;
  final dir = Directory(root).absolute;
  if (!dir.path.startsWith('$base${Platform.pathSeparator}') &&
      !dir.path.startsWith('$base/'))
    throw StateError('Staging estraneo');
  if (await dir.exists()) await dir.delete(recursive: true);
}

Future<void> copyToPath(String source, String destination) async {
  final input = File(source), output = File(destination);
  final temp = File(
    '$destination.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    final sink = temp.openWrite();
    await sink.addStream(input.openRead());
    await sink.flush();
    await sink.close();
    await temp.rename(output.path);
    final expected = await sha256.bind(input.openRead()).single;
    final actual = await sha256.bind(output.openRead()).single;
    if (expected != actual)
      throw StateError('Backup scritto non verificato: staging conservato');
  } catch (_) {
    if (await temp.exists()) await temp.delete();
    rethrow;
  }
}

Future<String> writeStream(Stream<List<int>> stream, int maxBytes) async {
  final root = await createStaging();
  final file = File('$root/import.zip');
  final sink = file.openWrite();
  var count = 0;
  try {
    await for (final chunk in stream) {
      count += chunk.length;
      if (count > maxBytes) throw const FormatException('Backup troppo grande');
      await checkQuota(root, chunk.length);
      sink.add(chunk);
      await sink.flush();
    }
    await sink.flush();
    await sink.close();
    return file.path;
  } catch (_) {
    await sink.close();
    await disposeStaging(root);
    rethrow;
  }
}
