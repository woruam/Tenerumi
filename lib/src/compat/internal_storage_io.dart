import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> _baseDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}${Platform.pathSeparator}xournalpp');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir.path;
}

/// Bare file names are resolved inside the app's private documents
/// directory; everything containing a separator is treated as a full path.
Future<String> resolve(String path) async {
  if (path.contains('/') || path.contains('\\')) return path;
  return '${await _baseDir()}${Platform.pathSeparator}$path';
}

Future<Uint8List> readFile(String path) => File(path).readAsBytes();

Future<bool> exists(String path) => File(path).exists();

Future<void> writeFile(String path, Uint8List bytes) async {
  final temporary = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    // Tenta di salvare il file
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(path);
    print("✅ File salvato con successo: $path");
  } catch (e) {
    if (await temporary.exists()) await temporary.delete();
    // Se Android blocca il salvataggio, cattura l'errore
    print("❌ ERRORE DI SALVATAGGIO IMPREVISTO: $e");

    // Rilanciamo l'errore per farlo sapere all'interfaccia grafica
    throw Exception(
        "Impossibile scrivere il file. Permesso negato o percorso non valido.");
  }
}

Future<void> writeFileIfMissing(String path, Uint8List bytes) async {
  // Android document providers have already written the bytes through the picker.
  if (path.startsWith('content://')) return;
  // Desktop pickers return a path, including an existing file confirmed by the user.
  await writeFile(path, bytes);
}

Future<void> deleteFile(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
