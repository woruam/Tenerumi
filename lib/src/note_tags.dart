import 'package:shared_preferences/shared_preferences.dart';

import 'globals.dart';
import 'recent_documents.dart';

/// Small, local tag catalog. Existing library tags are included on migration.
abstract final class NoteTags {
  static const defaults = ['Appunti', 'Scuola', 'Lavoro'];
  static String normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final tags = <String>[];
    for (final value in [
      ...defaults,
      ...?prefs.getStringList(PreferencesKeys.kNoteTags),
      ...(await RecentDocuments.list())
          .map((entry) => entry['tag'])
          .whereType<String>(),
    ]) {
      final tag = normalize(value);
      if (tag.isNotEmpty &&
          tag.toLowerCase() != 'tutti' &&
          !tags.any(
            (existing) => existing.toLowerCase() == tag.toLowerCase(),
          )) {
        tags.add(tag);
      }
    }
    return tags;
  }

  static Future<String> create(String value) async {
    final tag = normalize(value);
    if (tag.isEmpty || tag.length > 40 || tag.toLowerCase() == 'tutti') {
      throw const FormatException(
        'Inserisci un nome da 1 a 40 caratteri diverso da “Tutti”.',
      );
    }
    final tags = await load();
    final existing = tags
        .where((item) => item.toLowerCase() == tag.toLowerCase())
        .firstOrNull;
    if (existing != null) return existing;
    tags.add(tag);
    if (!await (await SharedPreferences.getInstance()).setStringList(
      PreferencesKeys.kNoteTags,
      tags.where((item) => !defaults.contains(item)).toList(),
    )) {
      throw StateError('Impossibile salvare il tag');
    }
    return tag;
  }
}
