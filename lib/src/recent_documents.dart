import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';

import 'XppFile.dart';
import 'globals.dart';
import 'compat/file_picker_cross.dart';
import 'autosave_store.dart';

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
    final completed = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queue = completed;
    unawaited(
      completed.then((_) {
        if (identical(_queue, completed)) _queue = null;
      }),
    );
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

  /// Commit a restored library in one metadata write after every file exists.
  static Future<void> addRestored(
    List<({XppFile file, bool favorite})> documents,
    List<String> backupTags,
  ) => _serial(() async {
    final entries = await list();
    final prefs = await SharedPreferences.getInstance();
    final previousTags = prefs.getStringList(PreferencesKeys.kNoteTags);
    final tags = [...?previousTags];
    for (final value in backupTags) {
      final tag = value.trim();
      if (tag.isNotEmpty &&
          tag.toLowerCase() != 'tutti' &&
          !tags.any((t) => t.toLowerCase() == tag.toLowerCase())) {
        tags.add(tag);
      }
    }
    for (final document in documents) {
      final file = document.file;
      entries.add({
        'name': file.title,
        'path': file.sourcePath,
        'id': file.documentId,
        'tag': file.tag ?? 'Appunti',
        'favorite': document.favorite,
        'preview': file.previewImage == null
            ? ''
            : base64Encode(file.previewImage!),
        if (file.modifiedAt != null)
          'modifiedAt': file.modifiedAt!.toUtc().toIso8601String(),
      });
    }
    if (!await prefs.setStringList(PreferencesKeys.kNoteTags, tags)) {
      throw StateError('Impossibile ripristinare i tag');
    }
    try {
      await _write(entries);
    } catch (_) {
      if (previousTags == null) {
        await prefs.remove(PreferencesKeys.kNoteTags);
      } else {
        await prefs.setStringList(PreferencesKeys.kNoteTags, previousTags);
      }
      rethrow;
    }
  });

  static Future<void> delete(
    Map<String, dynamic> entry, {
    Future<void> Function(String)? deleteFile,
  }) => _serial(() async {
    final entries = await list();
    final path = entry['path'];
    final id = entry['id'];
    final current = entries
        .where(
          (e) => path is String && path.isNotEmpty
              ? e['path'] == path
              : id is String && id.isNotEmpty
              ? e['id'] == id
              : e['path'] == path && e['name'] == entry['name'],
        )
        .firstOrNull;
    if (current == null) return;
    if (path is String && path.isNotEmpty) {
      if (deleteFile != null)
        await deleteFile(path);
      else
        await FilePickerCross.delete(path: path);
    }
    entries.remove(current);
    await _write(entries);
    final documentId = current['id'];
    if (documentId is String && documentId.isNotEmpty)
      await AutosaveStore.remove(documentId);
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
