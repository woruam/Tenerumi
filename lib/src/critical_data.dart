import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'document_limits.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'compat/critical_backend_stub.dart'
    if (dart.library.io) 'compat/critical_backend_io.dart'
    if (dart.library.js_interop) 'compat/critical_backend_web.dart'
    as backend;

/// A single commit contains library, tags, workspace and recovery pointers.
/// Preferences are only a migration input; immutable generations are retained.
abstract final class CriticalData {
  @visibleForTesting
  static bool inMemoryForTests = false;
  static final _memoryStates = <String, Map<String, dynamic>>{};
  static final _memoryBlobs = <String, Map<String, Uint8List>>{};
  static final _memoryRecoveries = <String, List<Map<String, dynamic>>>{};
  static Future<String> _namespace() async =>
      (await getApplicationDocumentsDirectory()).path;
  static Future<Map<String, dynamic>> _readState() async => inMemoryForTests
      ? Map<String, dynamic>.from(
          jsonDecode(jsonEncode(_memoryStates[await _namespace()] ?? {}))
              as Map,
        )
      : _readBackend();
  static Future<Map<String, dynamic>> _readBackend() async {
    final state = await backend.readState();
    for (final warning in backend.warnings) {
      if (!warnings.contains(warning)) warnings.add(warning);
    }
    backend.warnings.clear();
    return state;
  }

  static Future<void> _writeState(Map<String, dynamic> state) async {
    if (inMemoryForTests) {
      _memoryStates[await _namespace()] = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(state)) as Map,
      );
    } else {
      await backend.writeState(state);
    }
  }

  static Future<void>? _queue;
  static Future<void>? _blobsQueue;
  @visibleForTesting
  static void resetTestQueue() {
    _queue = null;
    _blobsQueue = null;
    _lastCollection = null;
  }

  /// Keep a complete graph leased from first fragment through metadata commit.
  static Future<T> blobTransaction<T>(Future<T> Function() fn) {
    final result = (_blobsQueue ?? Future.value()).then((_) => fn());
    final completed = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _blobsQueue = completed;
    unawaited(
      completed.then((_) {
        if (identical(_blobsQueue, completed)) _blobsQueue = null;
      }),
    );
    return result;
  }

  static Future<bool> hasBlob(String hash) async {
    if (inMemoryForTests)
      return _memoryBlobs[await _namespace()]?.containsKey(hash) == true;
    return backend.hasBlob(hash);
  }

  static DateTime? _lastCollection;
  static final _references = <String, List<String>>{};
  static Future<void> collectGarbage({bool force = false}) =>
      blobTransaction(() async {
        final now = DateTime.now();
        if (!force &&
            _lastCollection != null &&
            now.difference(_lastCollection!) < const Duration(seconds: 30))
          return;
        _lastCollection = now;
        await _queue;
        if (inMemoryForTests) return;
        try {
          final roots = await backend.retainedStates();
          final sidecars = await backend.stagedRecoveries();
          final current = await _readState();
          final dismissed = current['dismissedRecoveries'] is List
              ? current['dismissedRecoveries'] as List
              : <Object>[];
          final tokens = <String>{};
          void references(Object? v) {
            if (v is Map) {
              if (v['token'] is String) tokens.add(v['token'] as String);
              for (final value in v.values) {
                references(value);
              }
            }
            if (v is List) {
              for (final value in v) {
                references(value);
              }
            }
          }

          for (final state in roots) {
            references(state);
          }
          sidecars.sort(
            (a, b) => ((b['generation'] as int?) ?? 0).compareTo(
              (a['generation'] as int?) ?? 0,
            ),
          );
          final counts = <String, int>{};
          final retained = <Map<String, dynamic>>[];
          for (final entry in sidecars) {
            final key = entry['key'] as String?;
            final count = counts[key] ?? 0;
            if (tokens.contains(entry['token']) ||
                (!dismissed.contains(entry['token']) && count < 2)) {
              retained.add(entry);
              counts[key ?? 'legacy'] = count + 1;
            }
          }
          final live = <String>{};
          final pending = <String>[];
          final hashPattern = RegExp(r'^[a-f0-9]{64}$');
          void hashes(Object? v) {
            if (v is String) {
              final h = v.startsWith('blob:') ? v.substring(5) : v;
              if (hashPattern.hasMatch(h)) pending.add(h);
            }
            if (v is Map) {
              for (final value in v.values) {
                hashes(value);
              }
            }
            if (v is List) {
              for (final value in v) {
                hashes(value);
              }
            }
          }

          for (final root in [...roots, ...retained]) {
            hashes(root);
          }
          while (pending.isNotEmpty) {
            final hash = pending.removeLast();
            if (live.contains(hash) || !await hasBlob(hash)) continue;
            live.add(hash);
            final cached = _references[hash];
            if (cached != null) {
              pending.addAll(cached);
              continue;
            }

            final bytes = await getBlob(
              hash,
            ); // A corrupt graph aborts collection.
            if (bytes.isEmpty || bytes.length > 32 * 1024 * 1024) continue;
            if (bytes.first == 123) {
              hashes(jsonDecode(utf8.decode(bytes)));
            }
            if (bytes.first == 60) {
              final text = utf8.decode(bytes);
              for (final m in RegExp(
                r'osipp-blob="([a-f0-9]{64})"',
              ).allMatches(text)) {
                pending.add(m[1]!);
              }
            }
          }
          _references.removeWhere((key, _) => !live.contains(key));
          await backend.compact(live, retained);
          final stillPresent = {
            ...tokens,
            ...(await backend.stagedRecoveries()).map((e) => e['token']),
          };
          if (dismissed.any((token) => !stillPresent.contains(token))) {
            await transaction((state) async {
              state['dismissedRecoveries'] =
                  ((state['dismissedRecoveries'] as List?) ?? [])
                      .where(stillPresent.contains)
                      .toList();
            });
          }
        } catch (error) {
          final warning = 'Pulizia recuperi rinviata: $error';
          if (!warnings.contains(warning)) warnings.add(warning);
        }
      });
  static final List<String> warnings = [];
  static Future<T> transaction<T>(Future<T> Function(Map<String, dynamic>) fn) {
    final result = (_queue ?? Future.value()).then((_) async {
      final state = await _readState();
      final answer = await fn(state);
      await _writeState(state);
      return answer;
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

  static Future<Object?> read(String key) async {
    await _queue;
    return (await _readState())[key];
  }

  static Future<void> write(String key, Object? value) =>
      transaction((state) async {
        state[key] = value;
      });

  static Future<List<String>> stringList(String key) async {
    final value = await read(key);
    if (value == null) return [];
    if (value is List && value.every((e) => e is String))
      return value.cast<String>();
    await quarantine(key, jsonEncode(value));
    final valid = value is List
        ? value.whereType<String>().toList()
        : <String>[];
    await write(key, valid);
    return valid;
  }

  static Future<List<Map<String, dynamic>>> records(
    String key,
    bool Function(Map<String, dynamic>) valid,
  ) async {
    var value = await read(key);

    if (value == null) {
      final raw = (await SharedPreferences.getInstance()).get(key);
      if (raw != null) {
        try {
          if (raw is! String)
            throw const FormatException('Indice non testuale');
          if (raw.length > 16 * 1024 * 1024)
            throw const FormatException('Indice troppo grande');
          validateDocumentJsonText(raw);
          value = jsonDecode(raw);
        } catch (_) {
          await quarantine(key, raw is String ? raw : jsonEncode(raw));
          value = <Object>[];
        }
      } else {
        value = <Object>[];
      }
    }
    final result = <Map<String, dynamic>>[];
    var altered = false;
    if (value is List) {
      for (final record in value) {
        try {
          final entry = Map<String, dynamic>.from(record as Map);
          if (!valid(entry)) throw const FormatException('Record invalido');
          result.add(entry);
        } catch (_) {
          altered = true;
          await quarantine(key, jsonEncode(record));
        }
      }
    } else {
      altered = true;
      await quarantine(key, jsonEncode(value));
    }
    // Migration is a durable commit. The legacy original remains untouched.
    if (await read(key) == null || altered) await write(key, result);
    return result;
  }

  static Future<void> quarantine(String key, String raw) async {
    final warning =
        'Metadati danneggiati ($key): originale conservato nel recupero.';
    if (!warnings.contains(warning)) warnings.add(warning);
    if (!inMemoryForTests) await backend.quarantine(raw);
  }

  static Future<String> putBlob(Uint8List bytes) async {
    if (!inMemoryForTests) {
      final key = await backend.putBlob(bytes);
      final refs = <String>[];
      if (bytes.isNotEmpty && bytes.length <= 32 * 1024 * 1024) {
        if (bytes.first == 123) {
          try {
            void scan(Object? v) {
              if (v is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(v))
                refs.add(v);
              if (v is Map) {
                for (final child in v.values) {
                  scan(child);
                }
              }
              if (v is List) {
                for (final child in v) {
                  scan(child);
                }
              }
            }

            scan(jsonDecode(utf8.decode(bytes)));
          } catch (_) {}
        } else if (bytes.first == 60) {
          for (final match in RegExp(
            r'osipp-blob="([a-f0-9]{64})"',
          ).allMatches(utf8.decode(bytes))) {
            refs.add(match[1]!);
          }
        }
      }
      _references[key] = refs;
      return key;
    }
    final key = sha256.convert(bytes).toString();
    (_memoryBlobs[await _namespace()] ??= {})[key] = bytes;
    return key;
  }

  static Future<Uint8List> getBlob(String key) async => inMemoryForTests
      ? _memoryBlobs[await _namespace()]![key]!
      : backend.getBlob(key);
  static final _memoryLibrary = <String, Map<String, Map<String, dynamic>>>{};
  static Future<void> stageLibrary(Map<String, dynamic> entry) async {
    if (inMemoryForTests) {
      (_memoryLibrary[await _namespace()] ??= {})[entry['path'] as String] =
          Map.of(entry);
    } else {
      await backend.stageLibrary(entry);
    }
  }

  static Future<List<Map<String, dynamic>>> libraryCandidates() async =>
      inMemoryForTests
      ? (_memoryLibrary[await _namespace()]?.values.toList() ?? [])
      : backend.libraryCandidates();
  static Future<void> forgetLibrary(String path) async {
    if (inMemoryForTests) {
      _memoryLibrary[await _namespace()]?.remove(path);
    } else {
      await backend.forgetLibrary(path);
    }
  }

  static Future<void> stageRecovery(Map<String, dynamic> entry) async {
    if (inMemoryForTests) {
      (_memoryRecoveries[await _namespace()] ??= []).add(Map.of(entry));
    } else {
      await backend.stageRecovery(entry);
    }
  }

  static Future<List<Map<String, dynamic>>> stagedRecoveries() async =>
      inMemoryForTests
      ? List.of(_memoryRecoveries[await _namespace()] ?? [])
      : backend.stagedRecoveries();
}
