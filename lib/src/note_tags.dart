import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'globals.dart';
import 'recent_documents.dart';
import 'critical_data.dart';

/// Small, local tag catalog. Existing library tags are included on migration.
abstract final class NoteTags {
  static const defaults = ['Appunti', 'Scuola', 'Lavoro'];
  static final _whitespace = RegExp(r'\s+');
  static String normalize(String value) =>
      value.trim().replaceAll(_whitespace, ' ');

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    var catalog =
        await CriticalData.read(PreferencesKeys.kNoteTags) ??
        prefs.get(PreferencesKeys.kNoteTags) ??
        <String>[];
    if (catalog is! List || catalog.any((e) => e is! String)) {
      await CriticalData.quarantine(
        PreferencesKeys.kNoteTags,
        jsonEncode(catalog),
      );
      catalog = catalog is List
          ? catalog.whereType<String>().toList()
          : <String>[];
      await CriticalData.write(PreferencesKeys.kNoteTags, catalog);
    }
    final tags = <String>[];
    final seen = <String>{};
    for (final value in [
      ...defaults,
      ...catalog.whereType<String>(),
      ...(await RecentDocuments.list())
          .map((entry) => entry['tag'])
          .whereType<String>(),
    ]) {
      final tag = normalize(value);
      if (tag.isNotEmpty &&
          tag.toLowerCase() != 'tutti' &&
          seen.add(tag.toLowerCase())) {
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
    await CriticalData.transaction((state) async {
      final current =
          (state[PreferencesKeys.kNoteTags] as List?)
              ?.whereType<String>()
              .toList() ??
          [];
      for (final value in tags.where((item) => !defaults.contains(item))) {
        if (!current.any((e) => e.toLowerCase() == value.toLowerCase()))
          current.add(value);
      }
      state[PreferencesKeys.kNoteTags] = current;
    });
    return tag;
  }
}
