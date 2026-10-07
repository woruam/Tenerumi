import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';

import 'compat/internal_storage_generic.dart'
    if (dart.library.io) 'compat/internal_storage_io.dart'
    as storage;

/// Each checkpoint gets a new filename. The index changes only after a complete
/// write, so an interrupted save cannot replace the last usable checkpoint.
class AutosaveStore {
  static const indexKey = 'osipp.autosave.v1';
  static Future<void> _queue = Future.value();
  static Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final prefs = await SharedPreferences.getInstance();
    return (jsonDecode(prefs.getString(indexKey) ?? '[]') as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList()
      ..sort((a, b) => (b['time'] as int).compareTo(a['time'] as int));
  }

  static Future<void> save(XppFile file, Uint8List bytes) => _serial(() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await list();
    final previous = entries
        .where((e) => e['id'] == file.documentId)
        .firstOrNull;
    final key =
        'recovery-${file.documentId}-${DateTime.now().microsecondsSinceEpoch}.xopp';
    final path = kIsWeb ? key : await storage.resolve(key);
    if (kIsWeb) {
      if (!await prefs.setString(key, base64Encode(bytes))) {
        throw StateError('Spazio per il recupero esaurito');
      }
    } else {
      await storage.writeFile(path, bytes);
    }
    entries.removeWhere((e) => e['id'] == file.documentId);
    entries.add({
      'id': file.documentId,
      'title': file.title ?? 'Documento',
      'source': file.sourcePath,
      'path': path,
      'time': DateTime.now().millisecondsSinceEpoch,
      if (file.modifiedAt != null)
        'modifiedAt': file.modifiedAt!.toUtc().toIso8601String(),
      if (file.previewImage != null)
        'preview': base64Encode(file.previewImage!),
    });
    if (!await prefs.setString(indexKey, jsonEncode(entries))) {
      throw StateError('Impossibile aggiornare il recupero');
    }
    if (previous != null) {
      try {
        await _delete(previous['path'] as String);
      } catch (_) {
        /* Keep the new checkpoint. */
      }
    }
  });

  static Future<XppFile> restore(Map<String, dynamic> entry) async {
    final path = entry['path'] as String;
    final bytes = kIsWeb
        ? base64Decode((await SharedPreferences.getInstance()).getString(path)!)
        : await storage.readFile(path);
    final file = await XppFile.fromFilePickerCross(
      FilePickerCross(bytes, path: '${entry['title']}.xopp'),
      null,
      (_) async => throw StateError('Sfondo mancante'),
    );
    file.title = entry['title'] as String;
    file.sourcePath = entry['source'] as String?;
    file.recovered = true;
    return file;
  }

  static Future<void> _delete(String path) async {
    if (kIsWeb) {
      await (await SharedPreferences.getInstance()).remove(path);
    } else {
      await storage.deleteFile(path);
    }
  }

  static Future<void> remove(String id) => _serial(() async {
    final entries = await list();
    final removed = entries.where((e) => e['id'] == id).toList();
    entries.removeWhere((e) => e['id'] == id);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(indexKey, jsonEncode(entries))) {
      throw StateError('Impossibile eliminare il recupero');
    }
    for (final entry in removed) {
      await _delete(entry['path'] as String);
    }
  });
}
