import 'dart:async';
import 'dart:math' as math;

import 'plugin_manifest.dart';
import 'plugin_limits.dart';

typedef PluginAction = FutureOr<Object?> Function(Map<String, dynamic> args);

class PluginCapability {
  final Set<String> permissions;
  final PluginAction run;
  const PluginCapability(this.permissions, this.run);
}

/// Public extension point: register new host actions without changing the DSL.
class PluginApi {
  final void Function()? beforeInvoke;
  final void Function()? afterInvoke;
  final void Function()? onFailure;
  PluginApi({this.beforeInvoke, this.afterInvoke, this.onFailure});
  final Map<String, PluginCapability> _actions = {};
  List<String> get actions => List.unmodifiable(_actions.keys);
  Future<Object?> invoke(
    NotePlugin plugin,
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      beforeInvoke?.call();
      validatePluginValue(args);
      final action = _actions[name];
      if (action == null) throw StateError('Azione sconosciuta: $name');
      if (!plugin.permissions.containsAll(action.permissions)) {
        throw StateError('Permessi mancanti per $name');
      }
      final result = await action.run(args);
      afterInvoke?.call();
      validatePluginValue(result, maxBytes: 24 * 1024 * 1024);
      return result;
    } catch (_) {
      onFailure?.call();
      rethrow;
    }
  }

  void register(String name, Set<String> permissions, PluginAction handler) {
    if (_actions.containsKey(name)) {
      throw StateError('Azione già registrata: $name');
    }
    _actions[name] = PluginCapability(Set.unmodifiable(permissions), handler);
  }

  void validate(NotePlugin plugin) {
    void walk(List steps) {
      for (final step in steps.cast<Map<String, dynamic>>()) {
        if (step['action'] case final String name) {
          final action = _actions[name];
          if (action == null) {
            throw FormatException('Azione sconosciuta: $name');
          }
          if (!plugin.permissions.containsAll(action.permissions)) {
            throw FormatException(
              'Permessi mancanti per $name: ${action.permissions.join(', ')}',
            );
          }
        }
        for (final key in ['then', 'else', 'steps']) {
          if (step[key] is List) walk(step[key] as List);
        }
      }
    }

    for (final command in plugin.commands) {
      if (!plugin.isJavaScript) walk(command['steps'] as List);
    }
  }
}

class PluginRuntime {
  final NotePlugin plugin;
  final PluginApi api;
  final Map<String, dynamic> variables;
  int _steps = 0;
  int _expressions = 0;
  final Stopwatch _clock = Stopwatch()..start();
  final bool Function()? cancelled;
  PluginRuntime(
    this.plugin,
    this.api,
    Map<String, dynamic> context, {
    this.cancelled,
  }) : variables = Map.of(context) {
    validatePluginValue(variables, maxBytes: 24 * 1024 * 1024);
  }

  Object? _checked(Object? value) {
    validatePluginValue(value, maxBytes: 24 * 1024 * 1024);
    return value;
  }

  void _set(String name, Object? value) {
    validatePluginValue({
      ...variables,
      name: value,
    }, maxBytes: 24 * 1024 * 1024);
    variables[name] = value;
  }

  String _text(Object? value) {
    if (value is Map || value is List) {
      throw StateError(
        'Liste e oggetti non possono essere convertiti in testo',
      );
    }
    if (value is String && value.length > 65536) {
      throw StateError('Testo troppo lungo');
    }
    _checked(value);
    final text = value == null ? '' : value.toString();
    if (text.length > 65536) throw StateError('Testo troppo lungo');
    return text;
  }

  String _interpolate(String value) {
    if (value.length > 65536) throw StateError('Testo troppo lungo');
    final pieces = <String>[];
    var at = 0, length = 0;
    void add(String part) {
      length += part.length;
      if (length > 65536) throw StateError('Testo troppo lungo');
      pieces.add(part);
    }

    for (final match in RegExp(r'\$\{([a-zA-Z0-9_.]+)\}').allMatches(value)) {
      _budget();
      add(value.substring(at, match.start));
      add(_text(_lookup(match[1]!)));
      at = match.end;
    }
    add(value.substring(at));
    return pieces.join();
  }

  void _budget() {
    if (cancelled?.call() == true ||
        ++_expressions > 100000 ||
        _clock.elapsedMilliseconds > 2000) {
      throw StateError('Plugin interrotto: limite di elaborazione superato');
    }
  }

  Object? _lookup(String path) {
    if (path.length > 65536) throw StateError('Percorso troppo lungo');
    Object? result = variables;
    for (final key in path.split('.')) {
      if (result is Map) {
        result = result[key];
      } else if (result is List && int.tryParse(key) != null) {
        final index = int.parse(key);
        result = index >= 0 && index < result.length ? result[index] : null;
      } else {
        return null;
      }
    }
    return result;
  }

  Object? evaluate(Object? value, [int depth = 0]) {
    _budget();
    if (depth > 32) throw StateError('Espressione troppo profonda');
    if (value is String) {
      return _interpolate(value);
    }
    if (value is List) {
      if (value.length > 10000) throw StateError('Lista troppo lunga');
      final result = <Object?>[];
      final budget = PluginValueBudget(24 * 1024 * 1024)..add(null);
      for (final child in value) {
        final evaluated = evaluate(child, depth + 1);
        budget.add(evaluated, depth: 1);
        result.add(evaluated);
      }
      return result;
    }
    if (value is! Map) return _checked(value);
    if (value.containsKey('var')) {
      return _checked(_lookup(value['var'] as String));
    }
    if (!value.containsKey('op')) {
      if (value.length > 10000) throw StateError('Oggetto troppo grande');
      final result = <String, Object?>{};
      final budget = PluginValueBudget(24 * 1024 * 1024)..add(null);
      for (final entry in value.entries) {
        if (entry.key is! String) throw StateError('Chiave JSON non valida');
        budget.add(entry.key, depth: 1);
        final evaluated = evaluate(entry.value, depth + 1);
        budget.add(evaluated, depth: 1);
        result[entry.key as String] = evaluated;
      }
      return result;
    }
    final args = (evaluate(value['args'] ?? [], depth + 1) as List);
    num n(int i) {
      final v = args[i];
      if (v is! num || !v.isFinite) throw StateError('Numero non valido');
      return v;
    }

    String s(int i) => _text(args[i]);
    String join(List values, String separator) {
      if (values.length > 10000) throw StateError('Lista troppo lunga');
      final strings = <String>[];
      var length = math.max(0, values.length - 1) * separator.length;
      for (final value in values) {
        final text = _text(value);
        length += text.length;
        if (length > 65536) throw StateError('Testo troppo lungo');
        strings.add(text);
      }
      return strings.join(separator);
    }

    List<String> split() {
      final original = s(0), separator = s(1);
      final count = separator.isEmpty
          ? original.length
          : separator.allMatches(original).length + 1;
      if (count > 10000) throw StateError('Lista troppo lunga');
      return original.split(separator);
    }

    String replace() {
      final original = s(0), pattern = s(1), replacement = s(2);
      final occurrences = pattern.isEmpty
          ? original.length + 1
          : pattern.allMatches(original).length;
      if (original.length +
              occurrences * math.max(0, replacement.length - pattern.length) >
          65536) {
        throw StateError('Testo troppo lungo');
      }
      return original.replaceAll(pattern, replacement);
    }

    final Object? result = switch (value['op']) {
      'add' => args.fold<num>(0, (sum, v) => sum + (v as num)),
      'sub' => n(0) - n(1),
      'mul' => args.fold<num>(1, (product, v) => product * (v as num)),
      'div' => n(0) / n(1),
      'mod' => n(0) % n(1),
      'min' => math.min(n(0), n(1)),
      'max' => math.max(n(0), n(1)),
      'round' => n(0).round(),
      'floor' => n(0).floor(),
      'ceil' => n(0).ceil(),
      'abs' => n(0).abs(),
      'pow' => math.pow(n(0), n(1)),
      'sqrt' => math.sqrt(n(0)),
      'sin' => math.sin(n(0)),
      'cos' => math.cos(n(0)),
      'tan' => math.tan(n(0)),
      'append' =>
        (args[0] as List).length >= 10000
            ? throw StateError('Lista troppo lunga')
            : [...args[0] as List, args[1]],
      'eq' => args[0] == args[1],
      'ne' => args[0] != args[1],
      'gt' => n(0) > n(1),
      'gte' => n(0) >= n(1),
      'lt' => n(0) < n(1),
      'lte' => n(0) <= n(1),
      'and' => args.every((v) => v == true),
      'or' => args.any((v) => v == true),
      'not' => args[0] != true,
      'concat' => join(args, ''),
      'upper' => s(0).toUpperCase(),
      'lower' => s(0).toLowerCase(),
      'trim' => s(0).trim(),
      'replace' => replace(),
      'split' => split(),
      'join' => join(args[0] as List, s(1)),
      'length' => args[0] is List ? (args[0] as List).length : s(0).length,
      'at' => (args[0] as List)[n(1).toInt()],
      'get' => (args[0] as Map)[s(1)],
      'coalesce' => args.where((v) => v != null).firstOrNull,
      _ => throw StateError('Operatore sconosciuto: ${value['op']}'),
    };
    if (result is num && !result.isFinite) {
      throw StateError('Risultato numerico non valido');
    }
    if (result is String && result.length > 65536) {
      throw StateError('Testo troppo lungo');
    }
    return _checked(result);
  }

  Future<void> run(List steps) async {
    for (final raw in steps) {
      _budget();
      if (++_steps > 2000) {
        throw StateError('Plugin interrotto: massimo 2000 passi');
      }
      if (_steps % 100 == 0) await Future<void>.delayed(Duration.zero);
      final step = raw as Map<String, dynamic>;
      if (step['action'] case final String name) {
        final action = api._actions[name];
        if (action == null ||
            !plugin.permissions.containsAll(action.permissions)) {
          throw StateError('Azione non autorizzata: $name');
        }
        final args = Map<String, dynamic>.from(
          evaluate(step['args'] ?? {}) as Map,
        );
        _clock.stop();
        final Object? result;
        try {
          result = await api
              .invoke(plugin, name, args)
              .timeout(const Duration(minutes: 2));
        } finally {
          _clock.start();
        }
        if (step['as'] case final String variable) {
          if (['input', 'page', 'document', 'today'].contains(variable)) {
            throw StateError('Variabile riservata: $variable');
          }
          _set(variable, result);
        }
      } else if (step['set'] case final String name) {
        if (['input', 'page', 'document', 'today'].contains(name)) {
          throw StateError('Variabile di contesto riservata: $name');
        }
        _set(name, evaluate(step['value']));
      } else if (step.containsKey('if')) {
        await run(
          (evaluate(step['if']) == true ? step['then'] : step['else'] ?? [])
              as List,
        );
      } else {
        final repeat = step.containsKey('repeat');
        final value = evaluate(step[repeat ? 'repeat' : 'forEach']);
        if (repeat &&
            (value is! num ||
                !value.isFinite ||
                value != value.toInt() ||
                value < 0 ||
                value > 1000)) {
          throw StateError('repeat richiede un intero da 0 a 1000');
        }
        if (!repeat && (value is! List || value.length > 1000)) {
          throw StateError(
            'forEach richiede una lista di massimo 1000 elementi',
          );
        }
        final items = repeat
            ? List.generate((value as num).toInt(), (i) => i)
            : value as List;
        final name = step['as'] as String;
        if (['input', 'page', 'document', 'today'].contains(name)) {
          throw StateError('Variabile riservata: $name');
        }
        final hadValue = variables.containsKey(name);
        final previous = variables[name];
        for (final item in items) {
          _set(name, item);
          await run(step['steps'] as List);
        }
        if (hadValue) {
          variables[name] = previous;
        } else {
          variables.remove(name);
        }
      }
    }
  }
}
