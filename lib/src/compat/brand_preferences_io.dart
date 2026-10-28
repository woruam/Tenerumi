import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<void> migrateBrandPreferences() async {
  if (!Platform.isWindows) return;
  try {
    await copyLegacyBrandPreferences(await getApplicationSupportDirectory());
  } catch (_) {
    // A missing/locked preferences file must not prevent opening the library.
  }
}

/// ProductName controls the Windows preferences folder. Keep the old file and
/// copy it once, before SharedPreferences first opens the new brand's file.
Future<bool> copyLegacyBrandPreferences(Directory current) async {
  if (current.uri.pathSegments.where((s) => s.isNotEmpty).last.toLowerCase() !=
      'tenerumi')
    return false;
  final target = File.fromUri(current.uri.resolve('shared_preferences.json'));
  if (await target.exists()) return false;
  final source = File(
    '${current.parent.path}${Platform.pathSeparator}xournalpp${Platform.pathSeparator}shared_preferences.json',
  );
  if (!await source.exists() || await source.length() > 32 * 1024 * 1024)
    return false;
  final bytes = await source.readAsBytes();
  try {
    if (jsonDecode(utf8.decode(bytes)) is! Map) return false;
  } on FormatException {
    return false;
  }
  await current.create(recursive: true);
  final lock = await File.fromUri(current.uri.resolve('brand-migration.lock'))
      .open(mode: FileMode.append);
  final temporary = File.fromUri(
    current.uri.resolve('shared_preferences.migrating'),
  );
  var wroteTemporary = false;
  try {
    await lock.lock(FileLock.blockingExclusive);
    if (await target.exists()) return false;
    await temporary.writeAsBytes(bytes, flush: true);
    wroteTemporary = true;
    await temporary.rename(target.path);
    return true;
  } finally {
    if (wroteTemporary && await temporary.exists()) await temporary.delete();
    await lock.close();
  }
}
