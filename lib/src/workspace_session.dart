import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'XppFile.dart';
import 'autosave_store.dart';
import 'critical_data.dart';
import 'compat/file_picker_cross.dart';

class RestoredWorkspace {
  final List<XppFile> files;
  final List<Map<String, dynamic>> tabs;
  final Map<String, dynamic> state;
  RestoredWorkspace(this.files, this.tabs, this.state);
}

class WorkspaceSession {
  static const key = 'osipp.workspace.v1';
  static Future<void> save(Map<String, dynamic>? state) =>
      CriticalData.write(key, state ?? <String, dynamic>{});
  static Future<RestoredWorkspace?> restore() async {
    Object? value = await CriticalData.read(key);
    if (value == null) {
      final raw = (await SharedPreferences.getInstance()).get(key);
      if (raw == null) return null;
      try {
        if (raw is! String)
          throw const FormatException('Sessione non testuale');
        if (raw.length > 4 * 1024 * 1024)
          throw const FormatException('Sessione troppo grande');
        value = jsonDecode(raw);
      } catch (_) {
        await CriticalData.quarantine(
          key,
          raw is String ? raw : jsonEncode(raw),
        );
        return null;
      }
    }
    if (value is! Map || value['tabs'] is! List) {
      if (value is Map && value.isEmpty) return null;
      await CriticalData.quarantine(key, jsonEncode(value));
      return null;
    }
    final state = Map<String, dynamic>.from(value);
    final entries = await AutosaveStore.list();
    final files = <XppFile>[], tabs = <Map<String, dynamic>>[];
    final originalIndices = <int>[];
    final savedTabs = (state['tabs'] as List).take(100).toList();
    for (var i = 0; i < savedTabs.length; i++) {
      try {
        final tab = Map<String, dynamic>.from(savedTabs[i] as Map);
        if (tab['path'] != null && tab['path'] is! String ||
            tab['title'] != null && tab['title'] is! String ||
            tab['tag'] != null && tab['tag'] is! String)
          throw const FormatException('Scheda invalida');
        if (tab['page'] != null && tab['page'] is! int ||
            tab['localId'] != null && tab['localId'] is! String ||
            tab['key'] != null && tab['key'] is! String)
          throw const FormatException('Stato scheda invalido');
        XppFile? original, recovered;
        String? originalHash;
        final path = tab['path'] as String?;
        final localId =
            tab['localId'] as String? ??
            'legacy-${sha256.convert(utf8.encode(path ?? 'unsaved'))}';
        final recoveryKey =
            tab['key'] ??
            (path == null ? null : XppFile.recoveryKeyFor(path, localId));
        final recovery = entries
            .where((e) => e['key'] == recoveryKey)
            .firstOrNull;
        if (path != null && tab['recoveryOnly'] != true) {
          try {
            final picked = await FilePickerCross.fromInternalPath(path: path);
            originalHash = sha256.convert(picked.toUint8List()).toString();
            original = await XppFile.fromFilePickerCross(
              picked,
              null,
              (_) async => throw StateError('Sfondo mancante'),
            );
            if (tab['localId'] is String) original.localId = localId;
          } catch (_) {}
        }
        if (recovery != null &&
            (original == null || originalHash != recovery['hash'])) {
          try {
            recovered = await AutosaveStore.restore(recovery);
          } catch (_) {}
        }
        // An ID imported in XML is never sufficient to select a checkpoint.
        // If the original changed, both versions survive and recovery is protected.
        final safeRecovery =
            recovered != null &&
            original != null &&
            recovery?['baseHash'] == originalHash;
        XppFile? file = safeRecovery ? recovered : original ?? recovered;
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
        if (file == null && tab['blank'] == true)
          file = XppFile.empty(
            title: tab['title'] as String?,
            tag: tab['tag'] as String?,
          );
        if (file == null) continue;
        if (tab['title'] is String) file.title = tab['title'] as String;
        if (tab['tag'] is String) file.tag = tab['tag'] as String;
        files.add(file);
        tabs.add(tab);
        originalIndices.add(i);
        if (original != null && recovered != null && !safeRecovery) {
          recovered.title = '${recovered.title} (recupero da verificare)';
          files.add(recovered);
          tabs.add({...tab, 'recoveryOnly': true});
          originalIndices.add(-1);
        }
      } catch (_) {
        await CriticalData.quarantine(key, jsonEncode(savedTabs[i]));
      }
    }
    if (files.isEmpty) return null;
    final primary = originalIndices.indexOf(
      state['primary'] is int ? state['primary'] as int : 0,
    );
    final secondary = originalIndices.indexOf(
      state['secondary'] is int ? state['secondary'] as int : -2,
    );
    state['primary'] = primary < 0 ? 0 : primary;
    state['secondary'] = secondary < 0 ? null : secondary;
    if (state['divider'] is! num || !(state['divider'] as num).isFinite)
      state['divider'] = 0.5;
    if (state['split'] is! bool) state['split'] = false;
    return RestoredWorkspace(files, tabs, state);
  }
}
