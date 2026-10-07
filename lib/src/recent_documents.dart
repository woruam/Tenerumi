import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';

import 'XppFile.dart';
import 'globals.dart';

bool hasDocumentPreview(Object? value) {
  if (value is! String || value.isEmpty) return false;
  try {
    final bytes = base64Decode(value);
    return bytes.isNotEmpty && !listEquals(bytes, kTransparentImage);
  } catch (_) {
    return false;
  }
}

/// Serialize metadata writes across autosave, manual save and lazy migrations.
/// Preserve user fields and never replace a newer saved entry with old metadata.
class RecentDocuments {
  static Future<void>? _queue;
  static Future<T> _serial<T>(Future<T> Function() operation) {
    final result = (_queue ?? Future.value()).then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final prefs = await SharedPreferences.getInstance();
    return (jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles) ?? '[]')
            as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<void> save(XppFile snapshot, String path) => _serial(() async {
    final entries = await list();
    final previous = entries.where((e) => e['path'] == path).firstOrNull;
    entries.removeWhere((e) => e['path'] == path);
    entries.add({
      ...?previous,
      'name': snapshot.title,
      'path': path,
      'id': snapshot.documentId,
      'favorite': previous?['favorite'] ?? false,
      'tag': snapshot.tag ?? previous?['tag'] ?? 'Appunti',
      'preview': snapshot.previewImage == null
          ? (previous?['preview'] ?? '')
          : base64Encode(snapshot.previewImage!),
      if (snapshot.modifiedAt != null)
        'modifiedAt': snapshot.modifiedAt!.toUtc().toIso8601String(),
    });
    await _write(entries);
  });

  static Future<void> setTag(Map<String, dynamic> entry, String tag) =>
      _serial(() async {
        final entries = await list();
        final current = entries
            .where(
              (e) =>
                  e['path'] == entry['path'] &&
                  ((entry['path'] != null && entry['path'] != '') ||
                      e['name'] == entry['name']),
            )
            .firstOrNull;
        if (current == null) throw StateError('Appunto non disponibile');
        current['tag'] = tag;
        await _write(entries);
      });

  static Future<void> enrich(
    Map<String, dynamic> expected,
    Map<String, dynamic> metadata,
  ) => _serial(() async {
    final entries = await list();
    final current = entries
        .where((e) => e['path'] == expected['path'])
        .firstOrNull;
    if (current == null ||
        current['modifiedAt'] != expected['modifiedAt'] ||
        current['preview'] != expected['preview']) {
      return;
    }
    current.addAll(metadata);
    await _write(entries);
  });
  static Future<void> _write(List<Map<String, dynamic>> entries) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      PreferencesKeys.kRecentFiles,
      jsonEncode(entries),
    )) {
      throw StateError('Impossibile aggiornare i documenti recenti');
    }
  }
}
