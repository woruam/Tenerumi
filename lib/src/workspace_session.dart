import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'XppFile.dart';
import 'autosave_store.dart';
import 'compat/file_picker_cross.dart';

class RestoredWorkspace {
  final List<XppFile> files;
  final List<Map<String, dynamic>> tabs;
  final Map<String, dynamic> state;
  RestoredWorkspace(this.files, this.tabs, this.state);
}

/// Preferences contain tab metadata and bounded empty-page templates, never audio payloads. Notes live
/// in the existing atomic disk checkpoints and their original saved files.
class WorkspaceSession {
  static const key = 'osipp.workspace.v1';
  static Future<void>? _queue;
  static Future<void> save(Map<String, dynamic>? state) {
    final encoded = state == null ? null : jsonEncode(state);
    final result = (_queue ?? Future.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final success = encoded == null
          ? await prefs.remove(key)
          : await prefs.setString(key, encoded);
      if (!success) throw StateError('Impossibile salvare le schede aperte');
    });
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

  static Future<RestoredWorkspace?> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final state = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final entries = await AutosaveStore.list();
      final files = <XppFile>[], tabs = <Map<String, dynamic>>[];
      final originalIndices = <int>[];
      final savedTabs = (state['tabs'] as List).toList();
      for (var i = 0; i < savedTabs.length; i++) {
        final tab = Map<String, dynamic>.from(savedTabs[i] as Map);
        XppFile? file;
        final recovery = entries.where((e) => e['id'] == tab['id']).firstOrNull;
        if (recovery != null) {
          try {
            file = await AutosaveStore.restore(recovery);
          } catch (_) {}
        }
        if (file == null && tab['path'] is String) {
          try {
            file = await XppFile.fromFilePickerCross(
              await FilePickerCross.fromInternalPath(
                path: tab['path'] as String,
              ),
              null,
              (_) async => throw StateError('Sfondo mancante'),
            );
            file.sourcePath = tab['path'] as String;
          } catch (_) {}
        }
        if (file == null &&
            tab['template'] is String &&
            (tab['template'] as String).length < 65536) {
          try {
            file = await XppFile.fromFilePickerCross(
              FilePickerCross(
                base64Decode(tab['template'] as String),
                path: 'empty.xopp',
              ),
              null,
              (_) async => throw StateError('Sfondo mancante'),
            );
          } catch (_) {}
        }
        if (file == null && tab['blank'] == true) {
          file = XppFile.empty(
            title: tab['title'] as String?,
            tag: tab['tag'] as String?,
          );
        }
        if (file == null) continue;
        if (tab['title'] is String) file.title = tab['title'] as String;
        if (tab['tag'] is String) file.tag = tab['tag'] as String;
        files.add(file);
        tabs.add(tab);
        originalIndices.add(i);
      }
      if (files.isEmpty) return null;
      final primary = originalIndices.indexOf(state['primary'] as int? ?? 0);
      final secondary = originalIndices.indexOf(
        state['secondary'] as int? ?? -1,
      );
      state['primary'] = primary < 0 ? 0 : primary;
      state['secondary'] = secondary < 0 ? null : secondary;
      return RestoredWorkspace(files, tabs, state);
    } catch (_) {
      return null;
    }
  }
}
