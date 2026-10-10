import 'dart:convert';

/// Limits at the host boundary also apply to JavaScript and SDK providers.
void validatePluginValue(Object? value, {int maxBytes = 12 * 1024 * 1024}) {
  var nodes = 0, size = 0;
  void walk(Object? item, int depth) {
    if (depth > 64 || ++nodes > 100000) {
      throw StateError('Dati plugin troppo complessi');
    }
    if (item is String) {
      size += utf8.encode(item).length;
    } else if (item is Map) {
      for (final entry in item.entries) {
        if (entry.key is! String) throw StateError('Chiave JSON non valida');
        walk(entry.key, depth + 1);
        walk(entry.value, depth + 1);
      }
    } else if (item is List) {
      for (final child in item) {
        walk(child, depth + 1);
      }
    } else if (item == null || item is bool || item is num && item.isFinite) {
      size += 16;
    } else {
      throw StateError('Valore JSON non valido');
    }
    if (size > maxBytes) throw StateError('Dati plugin troppo grandi');
  }

  walk(value, 0);
}

String pluginText(Object? value) {
  if (value != null && value is! String) {
    throw StateError('text deve essere una stringa');
  }
  final text = value as String? ?? '';
  if (text.length > 65536) throw StateError('Testo: massimo 65536 caratteri');
  return text;
}
