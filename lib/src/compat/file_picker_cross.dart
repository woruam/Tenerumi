import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'internal_storage_generic.dart'
    if (dart.library.io) 'internal_storage_io.dart' as storage;

/// Compatibility layer replacing the discontinued `file_picker_cross`
/// package. It keeps the same API surface used throughout the app, but is
/// implemented on top of the maintained `file_picker` package plus
/// `path_provider` for internal app storage.
enum FileTypeCross { any, image, custom }

class FilePickerCross {
  final Uint8List _bytes;
  final String? path;

  FilePickerCross(Uint8List bytes,
      {FileTypeCross type = FileTypeCross.any,
      String? fileExtension,
      this.path})
      : _bytes = bytes;

  String? get fileName {
    if (path == null) return null;
    final normalized = path!.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  Uint8List toUint8List() => _bytes;

  /// Opens a file picker and reads the selected file into memory.
  static Future<FilePickerCross> importFromStorage(
      {FileTypeCross type = FileTypeCross.any, String? fileExtension}) async {
    FileType fileType = FileType.any;
    List<String>? extensions;
    if (type == FileTypeCross.image) {
      fileType = FileType.image;
    } else if (type == FileTypeCross.custom && fileExtension != null) {
      fileType = FileType.custom;
      extensions = fileExtension
          .split(',')
          .map((e) => e.trim().replaceAll('.', ''))
          .toList();
    }
    final result = await FilePicker.pickFiles(
        type: fileType, allowedExtensions: extensions, withData: true);
    if (result == null || result.files.isEmpty) {
      throw 'No file selected.';
    }
    final file = result.files.first;
    Uint8List? data = file.bytes;
    if (data == null && file.path != null) {
      data = await storage.readFile(file.path!);
    }
    if (data == null) throw 'Could not read the selected file.';
    return FilePickerCross(data,
        type: type, fileExtension: fileExtension, path: file.path ?? file.name);
  }

  /// Reads a file previously stored via [saveToPath]. Bare file names are
  /// resolved inside the app's documents directory, full paths are read
  /// directly from disk.
  static Future<FilePickerCross> fromInternalPath(
      {required String path}) async {
    final data = await storage.readFile(await storage.resolve(path));
    return FilePickerCross(data, path: path);
  }

  /// Persists the file. Bare names go to the app's documents directory.
  Future<String> saveToPath({required String path}) async {
    final resolved = await storage.resolve(path);
    await storage.writeFile(resolved, _bytes);
    return path;
  }

  /// Shows a "save as" dialog (or triggers a download on the web).
  Future<String?> exportToStorage({String? fileName}) async {
    String name = fileName ?? this.fileName ?? 'export';
    name = name.replaceAll('\\', '/');
    name = name.substring(name.lastIndexOf('/') + 1);
    final savedPath =
        await FilePicker.saveFile(fileName: name, bytes: _bytes);
    if (savedPath != null) {
      // On desktop platforms `saveFile` only returns the location and the
      // caller is responsible for writing the bytes.
      await storage.writeFileIfMissing(savedPath, _bytes);
    }
    return savedPath ?? name;
  }

  static Future<void> delete({required String path}) async {
    await storage.deleteFile(await storage.resolve(path));
  }
}
