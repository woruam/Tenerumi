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

Future<void> writeFile(String path, Uint8List bytes) async {
  try {
    // Tenta di salvare il file
    await File(path).writeAsBytes(bytes, flush: true);
    print("✅ File salvato con successo: $path");
  } catch (e) {
    // Se Android blocca il salvataggio, cattura l'errore
    print("❌ ERRORE DI SALVATAGGIO IMPREVISTO: $e");
    
    // Rilanciamo l'errore per farlo sapere all'interfaccia grafica
    throw Exception("Impossibile scrivere il file. Permesso negato o percorso non valido.");
  }
}

Future<void> writeFileIfMissing(String path, Uint8List bytes) async {
  try {
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) {
      await file.writeAsBytes(bytes, flush: true);
    }
  } catch (_) {
    // e.g. content:// URIs on Android: file_picker already wrote the bytes.
  }
}

Future<void> deleteFile(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}