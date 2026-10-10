/// Limits at the host boundary also apply to JavaScript and SDK providers.
void validatePluginValue(Object? value, {int maxBytes = 12 * 1024 * 1024}) {
  PluginValueBudget(maxBytes).add(value);
}

/// Incremental aggregate accounting, also counting repeated/shared values.
class PluginValueBudget {
  final int maxBytes;
  int nodes = 0, size = 0;
  PluginValueBudget(this.maxBytes);
  void add(Object? value, {int depth = 0}) => walk(value, depth);
  void walk(Object? item, int depth) {
    if (depth > 64 || ++nodes > 100000) {
      throw StateError('Dati plugin troppo complessi');
    }
    if (item is String) {
      // Count UTF-8 without allocating an encoded copy of untrusted strings.
      for (var i = 0; i < item.length; i++) {
        final c = item.codeUnitAt(i);
        if (c <= 0x7f) {
          size++;
        } else if (c <= 0x7ff) {
          size += 2;
        } else if (c >= 0xd800 &&
            c <= 0xdbff &&
            i + 1 < item.length &&
            item.codeUnitAt(i + 1) >= 0xdc00 &&
            item.codeUnitAt(i + 1) <= 0xdfff) {
          size += 4;
          i++;
        } else {
          size += 3;
        }
        if (size > maxBytes) throw StateError('Dati plugin troppo grandi');
      }
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
}

String pluginText(Object? value) {
  if (value != null && value is! String) {
    throw StateError('text deve essere una stringa');
  }
  final text = value as String? ?? '';
  if (text.length > 65536) throw StateError('Testo: massimo 65536 caratteri');
  return text;
}
