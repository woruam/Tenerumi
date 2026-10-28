import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';

import 'XppFile.dart';
import 'globals.dart';
import 'compat/file_picker_cross.dart';
import 'autosave_store.dart';
import 'critical_data.dart';
import 'note_tags.dart';

bool hasDocumentPreview(Object? value) {
  if (value is! String || value.isEmpty || value.length > 512 * 1024)
    return false;
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
  static bool restoring = false;
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
    final missingIndex =
        await CriticalData.read(PreferencesKeys.kRecentFiles) == null;
    final entries = await CriticalData.records(
      PreferencesKeys.kRecentFiles,
      (e) =>
          e['path'] is String &&
          e['name'] is String &&
          (e['id'] == null || e['id'] is String) &&
          (e['tag'] == null || e['tag'] is String) &&
          (e['favorite'] == null || e['favorite'] is bool) &&
          (e['key'] == null || e['key'] is String) &&
          (e['localId'] == null || e['localId'] is String) &&
          (e['preview'] == null ||
              e['preview'] is String &&
                  (e['preview'] as String).length <= 512 * 1024) &&
          (e['modifiedAt'] == null || e['modifiedAt'] is String),
    );
    if (missingIndex || entries.isEmpty && CriticalData.warnings.isNotEmpty) {
      for (final candidate in await CriticalData.libraryCandidates()) {
        final path = candidate['path'];
        if (path is String &&
            candidate['name'] is String &&
            !entries.any((e) => e['path'] == path)) {
          try {
            if (await FilePickerCross.exists(path)) entries.add(candidate);
          } catch (_) {}
        }
      }
      await CriticalData.write(PreferencesKeys.kRecentFiles, entries);
    }
    final pending = await CriticalData.read('restorePending');
    if (!restoring && pending is List && pending.isNotEmpty) {
      for (final record in pending.whereType<Map>()) {
        final path = record['path'];
        if (path is! String || entries.any((e) => e['path'] == path)) continue;
        try {
          final file = await XppFile.fromFilePickerCross(
            await FilePickerCross.fromInternalPath(path: path),
            null,
            (_) async => throw StateError('Sfondo mancante'),
          );
          entries.add({
            ...Map<String, dynamic>.from(record),
            'id': file.documentId,
          });
        } catch (_) {
          await CriticalData.quarantine('restorePending', jsonEncode(record));
        }
      }
      await CriticalData.transaction((state) async {
        state[PreferencesKeys.kRecentFiles] = entries;
        state['restorePending'] = [];
      });
      CriticalData.warnings.add(
        'Ripristino interrotto: gli appunti completi sono stati recuperati nella libreria.',
      );
    }
    return entries;
  }

  static Future<void> save(XppFile snapshot, String path) => _serial(() async {
    final entries = await list();
    final previous = entries.where((e) => e['path'] == path).firstOrNull;
    entries.removeWhere((e) => e['path'] == path);
    entries.add({
      ...?previous,
      'name': snapshot.title ?? 'Documento',
      'path': path,
      'id': snapshot.documentId,
      'key': XppFile.recoveryKeyFor(path, snapshot.localId),
      'localId': snapshot.localId,
      'favorite': previous?['favorite'] ?? false,
      'tag': snapshot.tag ?? previous?['tag'] ?? 'Appunti',
      'preview': snapshot.previewImage == null
          ? (previous?['preview'] ?? '')
          : base64Encode(snapshot.previewImage!),
      if (snapshot.modifiedAt != null)
        'modifiedAt': snapshot.modifiedAt!.toUtc().toIso8601String(),
    });
    await CriticalData.stageLibrary(entries.last);
    await _write(entries);
  });

  /// Commit a restored library in one metadata write after every file exists.
  static Future<void> addRestored(
    List<({XppFile file, bool favorite})> documents,
    List<String> backupTags,
  ) => _serial(() async {
    final entries = await list();
    final prefs = await SharedPreferences.getInstance();
    final previousTags =
        (await CriticalData.read(PreferencesKeys.kNoteTags) as List?)
            ?.whereType<String>()
            .toList() ??
        prefs.getStringList(PreferencesKeys.kNoteTags);
    final tags = <String>[];
    final seenTags = <String>{};
    for (final value in [
      ...?previousTags,
      ...backupTags,
      ...documents.map((d) => d.file.tag).whereType<String>(),
    ]) {
      final tag = NoteTags.normalize(value);
      if (tag.isNotEmpty &&
          tag.toLowerCase() != 'tutti' &&
          seenTags.add(tag.toLowerCase())) {
        tags.add(tag);
      }
    }
    for (final document in documents) {
      final file = document.file;
      entries.removeWhere((e) => e['path'] == file.sourcePath);
      entries.add({
        'name': file.title ?? 'Documento',
        'path': file.sourcePath,
        'id': file.documentId,
        'key': file.recoveryKey,
        'localId': file.localId,
        'tag': file.tag ?? 'Appunti',
        'favorite': document.favorite,
        'preview': file.previewImage == null
            ? ''
            : base64Encode(file.previewImage!),
        if (file.modifiedAt != null)
          'modifiedAt': file.modifiedAt!.toUtc().toIso8601String(),
      });
      await CriticalData.stageLibrary(entries.last);
    }
    await CriticalData.transaction((state) async {
      state[PreferencesKeys.kNoteTags] = {
        ...?(state[PreferencesKeys.kNoteTags] as List?),
        ...tags,
      }.toList();
      state[PreferencesKeys.kRecentFiles] = entries;
      state['restorePending'] = [];
    });
  });

  static Future<void> delete(
    Map<String, dynamic> entry, {
    Future<void> Function(String)? deleteFile,
  }) => _serial(() async {
    final entries = await list();
    final path = entry['path'];
    final current = entries
        .where(
          (e) => path is String && path.isNotEmpty
              ? e['path'] == path
              : e['key'] != null && e['key'] == entry['key'],
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
    if (path is String) await CriticalData.forgetLibrary(path);
    await _write(entries);
    await AutosaveStore.remove(
      current['key'] as String? ??
          XppFile.recoveryKeyFor(
            path as String?,
            current['localId'] as String? ?? 'legacy',
          ),
    );
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
    await CriticalData.write(PreferencesKeys.kRecentFiles, entries);
  }
}
