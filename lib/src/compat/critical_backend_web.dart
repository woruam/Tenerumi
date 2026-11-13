import '../document_limits.dart';
import '../responsive_hash.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

Future<IDBDatabase> _database() async {
  final request = window.indexedDB.open('osipp-critical-v2', 2);
  final done = Completer<IDBDatabase>();
  request.onupgradeneeded = ((Event _) {
    final db = request.result as IDBDatabase;
    if (!db.objectStoreNames.contains('data')) db.createObjectStore('data');
  }).toJS;
  request.onsuccess = ((Event _) {
    final db = request.result as IDBDatabase;
    if (done.isCompleted) {
      db.close();
      return;
    }
    db.onversionchange = ((Event _) => db.close()).toJS;
    done.complete(db);
  }).toJS;
  request.onerror = ((Event _) {
    if (!done.isCompleted) {
      done.completeError(
        StateError(
          'Archivio browser non disponibile: ${request.error?.message}',
        ),
      );
    }
  }).toJS;
  request.onblocked = ((Event _) {
    if (!done.isCompleted) {
      done.completeError(
        StateError(
          'Chiudere le altre schede Tenerumi per aggiornare l’archivio',
        ),
      );
    }
  }).toJS;
  return done.future;
}

Future<JSAny?> _read(String key) async {
  final db = await _database();
  try {
    final request = db
        .transaction('data'.toJS, 'readonly')
        .objectStore('data')
        .get(key.toJS);
    final done = Completer<JSAny?>();
    request.onsuccess = ((Event _) => done.complete(request.result)).toJS;
    request.onerror = ((Event _) => done.completeError(
      StateError('Lettura archivio browser fallita'),
    )).toJS;
    return await done.future;
  } finally {
    db.close();
  }
}

Future<void> _write(String key, JSAny value, {bool state = false}) async {
  final db = await _database();
  try {
    final tx = db.transaction('data'.toJS, 'readwrite');
    final done = Completer<void>();
    tx.oncomplete = ((Event _) => done.complete()).toJS;
    tx.onabort = ((Event _) => done.completeError(
      StateError(
        'Quota o scrittura dell’archivio browser fallita; il recupero precedente è conservato',
      ),
    )).toJS;
    final store = tx.objectStore('data');
    if (state) {
      final old = store.get(key.toJS);
      old.onsuccess = ((Event _) {
        if (old.result != null) store.put(old.result!, 'state-previous'.toJS);
        store.put(value, key.toJS);
      }).toJS;
    } else {
      store.put(value, key.toJS);
    }
    await done.future;
  } finally {
    db.close();
  }
}

Future<Map<String, dynamic>> readState() async {
  final value = await _read('state');
  if (value == null) return {};
  try {
    final text = (value as JSString).toDart;
    if (text.length > 16 * 1024 * 1024)
      throw const FormatException("Metadati troppo grandi");
    validateDocumentJsonText(text);
    return Map<String, dynamic>.from(jsonDecode(text) as Map);
  } catch (_) {
    await quarantine((value as JSString).toDart);
    final previous = await _read('state-previous');
    return previous == null
        ? {}
        : Map<String, dynamic>.from(
            jsonDecode((previous as JSString).toDart) as Map,
          );
  }
}

Future<void> writeState(Map<String, dynamic> state) async {
  final raw = jsonEncode(state);
  if (raw.length > 16 * 1024 * 1024)
    throw StateError('Limite dei metadati raggiunto');
  await _write('state', raw.toJS, state: true);
}

Future<void> quarantine(String raw) =>
    _write('quarantine-${DateTime.now().microsecondsSinceEpoch}', raw.toJS);
Future<String> putBlob(Uint8List bytes) async {
  final key = await responsiveHash(bytes);
  await _write('blob-$key', bytes.toJS);
  return key;
}

Future<Uint8List> getBlob(String key) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key))
    throw const FormatException('Identificatore invalido');
  final raw = await _read('blob-$key');
  if (raw == null) throw StateError('Recupero non disponibile');
  final bytes = (raw as JSUint8Array).toDart;
  if (await responsiveHash(bytes) != key)
    throw const FormatException('Recupero corrotto');
  return bytes;
}

Future<String?> blobFilePath(String key) async => null;

Future<void> stageRecovery(Map<String, dynamic> entry) async {
  // The recovery manifest itself is an immutable journal in the same database.
  final entries = await stagedRecoveries();
  entries.add(entry);
  await _write('recovery-manifests', jsonEncode(entries).toJS);
}

Future<List<Map<String, dynamic>>> stagedRecoveries() async {
  final raw = await _read('recovery-manifests');
  if (raw == null) return [];
  return (jsonDecode((raw as JSString).toDart) as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

final warnings = <String>[];
Future<bool> hasBlob(String hash) async => await _read('blob-$hash') != null;
Future<List<Map<String, dynamic>>> retainedStates() async {
  final states = <Map<String, dynamic>>[];
  for (final key in ['state', 'state-previous']) {
    final raw = await _read(key);
    if (raw != null)
      states.add(
        Map<String, dynamic>.from(jsonDecode((raw as JSString).toDart) as Map),
      );
  }
  return states;
}

Future<void> compact(
  Set<String> live,
  List<Map<String, dynamic>> retained,
) async {
  final db = await _database();
  try {
    final tx = db.transaction('data'.toJS, 'readwrite'),
        done = Completer<void>();
    tx.oncomplete = ((Event _) => done.complete()).toJS;
    tx.onabort = ((Event _) => done.completeError(
      StateError('Pulizia browser interrotta'),
    )).toJS;
    final store = tx.objectStore('data'),
        request = tx.objectStore('data').getAllKeys();
    request.onsuccess = ((Event _) {
      for (final key in (request.result as JSArray<JSAny>).toDart) {
        final name = (key as JSString).toDart;
        if (name.startsWith('blob-') && !live.contains(name.substring(5)))
          store.delete(key);
      }
      store.put(jsonEncode(retained).toJS, 'recovery-manifests'.toJS);
    }).toJS;
    await done.future;
  } finally {
    db.close();
  }
}

Future<void> stageLibrary(Map<String, dynamic> entry) async {
  final rows = await libraryCandidates();
  rows.removeWhere((e) => e['path'] == entry['path']);
  rows.add(entry);
  await _write('library-manifests', jsonEncode(rows).toJS);
}

Future<List<Map<String, dynamic>>> libraryCandidates() async {
  final raw = await _read('library-manifests');
  if (raw == null) return [];
  return (jsonDecode((raw as JSString).toDart) as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

Future<void> forgetLibrary(String path) async {
  final rows = await libraryCandidates();
  rows.removeWhere((e) => e['path'] == path);
  await _write('library-manifests', jsonEncode(rows).toJS);
}
