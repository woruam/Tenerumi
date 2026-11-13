import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'XppFile.dart';
import 'critical_data.dart';
import 'recovery_journal.dart';
import 'compat/file_picker_cross.dart';
import 'compat/internal_storage_generic.dart'
    if (dart.library.io) 'compat/internal_storage_io.dart'
    as storage;

class AutosaveStore {
  static const indexKey = 'osipp.autosave.v1';
  static Future<void>? _queue;
  static Timer? _gcTimer;

  @visibleForTesting
  static void resetTestQueue() {
    _queue = null;
    _gcTimer?.cancel();
    _gcTimer = null;
  }

  static void _scheduleGc() {
    _gcTimer?.cancel();
    _gcTimer = Timer(const Duration(seconds: 5), () {
      unawaited(CriticalData.collectGarbage());
    });
  }

  static Future<T> _serial<T>(Future<T> Function() fn) {
    final result = (_queue ?? Future.value()).then((_) => fn());
    final completed = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _queue = completed;
    unawaited(
      completed.then((_) {
        if (identical(_queue, completed)) _queue = null;
      }),
    );
    return result;
  }

  static bool _valid(Map<String, dynamic> e) =>
      e['id'] is String &&
      e['title'] is String &&
      e['path'] is String &&
      e['time'] is int &&
      (e['source'] == null || e['source'] is String) &&
      (e['key'] == null || e['key'] is String) &&
      (e['generation'] == null || e['generation'] is int) &&
      (e['hash'] == null ||
          e['hash'] is String &&
              RegExp(r'^[a-f0-9]{64}$').hasMatch(e['hash'] as String)) &&
      (e['baseHash'] == null || e['baseHash'] is String) &&
      (e['localId'] == null || e['localId'] is String) &&
      (e['modifiedAt'] == null || e['modifiedAt'] is String);
  static Future<List<Map<String, dynamic>>> list() async {
    final records = await CriticalData.records(indexKey, _valid);
    final dismissed = await CriticalData.stringList('dismissedRecoveries');
    for (final entry in await CriticalData.stagedRecoveries()) {
      if (_valid(entry) &&
          !dismissed.contains(entry['token']) &&
          !records.any((e) => e['token'] == entry['token']))
        records.add(entry);
    }
    records.removeWhere((e) => dismissed.contains(e['token']));
    for (final e in records) {
      e['localId'] ??=
          'legacy-${sha256.convert(utf8.encode((e['source'] ?? e['path']) as String))}';
      e['key'] ??= XppFile.recoveryKeyFor(
        e['source'] as String?,
        e['localId'] as String,
      );
    }
    records.sort(
      (a, b) => ((b['generation'] as int?) ?? b['time'] as int).compareTo(
        (a['generation'] as int?) ?? a['time'] as int,
      ),
    );
    // Return the newest generation of each local origin; history stays durable.
    final seen = <String>{};
    return records.where((e) => seen.add(e['key'] as String)).toList();
  }

  static Future<void> save(XppFile file, Uint8List bytes) => _serial(
    () => CriticalData.blobTransaction(() async {
      final blob = await CriticalData.putBlob(bytes);
      await _commit(file, blob, 'xopp');
      _scheduleGc();
    }),
  );
  static Future<void> saveIncremental(XppFile file) => _serial(
    () => CriticalData.blobTransaction(() async {
      final blob = await RecoveryJournal.write(file);
      await _commit(file, blob, 'journal');
      _scheduleGc();
    }),
  );
  static Future<void> _commit(XppFile file, String blob, String format) async {
    final previous = await list();
    final generation =
        previous.fold<int>(
          0,
          (g, e) => ((e['generation'] as int?) ?? e['time'] as int) > g
              ? ((e['generation'] as int?) ?? e['time'] as int)
              : g,
        ) +
        1;
    final entry = <String, dynamic>{
      'id': file.documentId,
      'key': file.recoveryKey,
      'localId': file.localId,
      'title': file.title ?? 'Documento',
      'source': file.sourcePath,
      'path': 'blob:$blob',
      'hash': blob,
      'baseHash': file.originHash,
      'token':
          '${file.recoveryKey}-$blob-${DateTime.now().microsecondsSinceEpoch}',
      'time': DateTime.now().millisecondsSinceEpoch,
      'generation': generation,
      'format': format,
      if (file.modifiedAt != null)
        'modifiedAt': file.modifiedAt!.toUtc().toIso8601String(),
      if (file.previewImage != null)
        'preview': base64Encode(file.previewImage!),
    };
    // Sidecar survives process death between the blob and the metadata commit.
    await CriticalData.stageRecovery(entry);
    final entries = List<Map<String, dynamic>>.of(previous);
    entries.removeWhere((e) => e['key'] == file.recoveryKey);
    entries.add(entry);
    await CriticalData.write(indexKey, entries);
  }

  static Future<Uint8List> readBytes(Map<String, dynamic> entry) async {
    final path = entry['path'] as String;
    if (entry['format'] == 'journal')
      return (await RecoveryJournal.read(entry['hash'] as String))
          .serializeSnapshotAsync();
    if (path.startsWith('blob:'))
      return CriticalData.getBlob(path.substring(5));
    // Legacy generations remain readable until explicitly reconciled.
    return kIsWeb
        ? base64Decode((await SharedPreferences.getInstance()).getString(path)!)
        : storage.readFile(path);
  }

  static Future<Uint8List?> checkpointBytes(String key, DateTime? modifiedAt) =>
      _serial(() async {
        final entry = (await list())
            .where(
              (e) =>
                  e['key'] == key &&
                  e['modifiedAt'] == modifiedAt?.toUtc().toIso8601String(),
            )
            .firstOrNull;
        if (entry == null) return null;
        try {
          return await readBytes(entry);
        } catch (_) {
          return null;
        }
      });

  static Future<String?> checkpointBlobPath(String key, DateTime? modifiedAt) =>
      _serial(() async {
        final entry = (await list())
            .where(
              (e) =>
                  e['key'] == key &&
                  e['modifiedAt'] == modifiedAt?.toUtc().toIso8601String(),
            )
            .firstOrNull;
        if (entry == null) return null;
        final hash = entry['hash'] as String?;
        if (hash == null) return null;
        return CriticalData.blobFilePath(hash);
      });
  static Future<XppFile> restore(Map<String, dynamic> entry) async {
    try {
      return await _restore(entry);
    } catch (error) {
      final dismissed = await CriticalData.stringList('dismissedRecoveries');
      final older =
          (await CriticalData.stagedRecoveries())
              .where(
                (e) =>
                    e['key'] == entry['key'] &&
                    !dismissed.contains(e['token']) &&
                    e['token'] != entry['token'] &&
                    ((e['generation'] as int?) ?? 0) <
                        ((entry['generation'] as int?) ?? 0),
              )
              .toList()
            ..sort(
              (a, b) => ((b['generation'] as int?) ?? 0).compareTo(
                (a['generation'] as int?) ?? 0,
              ),
            );
      for (final previous in older) {
        try {
          final file = await _restore(previous);
          file.importWarnings.add(
            'Generazione più recente danneggiata: aperto il recupero precedente',
          );
          return file;
        } catch (_) {}
      }
      rethrow;
    }
  }

  static Future<XppFile> _restore(Map<String, dynamic> entry) async {
    final file = entry['format'] == 'journal'
        ? await RecoveryJournal.read(entry['hash'] as String)
        : await XppFile.fromFilePickerCross(
            FilePickerCross(
              await readBytes(entry),
              path: '${entry['title']}.xopp',
            ),
            null,
            (_) async => throw StateError('Sfondo mancante'),
          );
    file.title = entry['title'] as String;
    file.sourcePath = entry['source'] as String?;
    if (entry['localId'] is String) file.localId = entry['localId'] as String;
    file.originHash = entry['baseHash'] as String?;
    file.recovered = true;
    file.importWarnings.add(
      'Recupero locale: verificare il contenuto e salvare una copia',
    );
    return file;
  }

  static Future<void> remove(String key) => _serial(() async {
    final entries = await list();
    final staged = await CriticalData.stagedRecoveries();
    final removed = [...entries, ...staged]
        .where((e) => e['key'] == key)
        .map((e) => e['token'])
        .whereType<String>()
        .toSet();
    entries.removeWhere((e) => e['key'] == key);
    await CriticalData.transaction((state) async {
      state[indexKey] = entries;
      state['dismissedRecoveries'] = {
        ...?(state['dismissedRecoveries'] as List?),
        ...removed,
      }.toList();
    });
    // Never delete payloads in the commit path. Prior generations remain intact.
  });
}
