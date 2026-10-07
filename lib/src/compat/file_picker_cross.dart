import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';

import 'internal_storage_generic.dart'
    if (dart.library.io) 'internal_storage_io.dart'
    as storage;

/// Compatibility layer replacing the discontinued `file_picker_cross`
/// package. It keeps the same API surface used throughout the app, but is
/// implemented on top of the maintained `file_picker` package plus
/// `path_provider` for internal app storage.
enum FileTypeCross { any, image, custom }

class FilePickerCross {
  static const _documents = MethodChannel('online.xournal.mobile/documents');
  final Uint8List _bytes;
  final String? path;

  FilePickerCross(
    Uint8List bytes, {
    FileTypeCross type = FileTypeCross.any,
    String? fileExtension,
    this.path,
  }) : _bytes = bytes;

  String? get fileName {
    final sourcePath = path;
    if (sourcePath == null) return null;
    final normalized = sourcePath.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  Uint8List toUint8List() => _bytes;

  /// Opens a file picker and reads the selected file into memory.
  static Future<FilePickerCross> importFromStorage({
    FileTypeCross type = FileTypeCross.any,
    String? fileExtension,
  }) async {
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
    final file = await FilePicker.pickFile(
      type: fileType,
      allowedExtensions: extensions,
    );
    if (file == null) {
      throw 'No file selected.';
    }
    final selectedPath = file.path;
    // v13 reads local paths, Android content URIs and browser blobs through
    // PlatformFile, without requiring a filesystem path or eager withData.
    final data = await file.readAsBytes();
    return FilePickerCross(
      data,
      type: type,
      fileExtension: fileExtension,
      path:
          selectedPath ??
          (file.uri.scheme == 'content' ? file.uri.toString() : file.name),
    );
  }

  /// Reads a file previously stored via [saveToPath]. Bare file names are
  /// resolved inside the app's documents directory, full paths are read
  /// directly from disk.
  static Future<FilePickerCross> fromInternalPath({
    required String path,
  }) async {
    if (path.startsWith('content://')) {
      final data = await _documents.invokeMethod<Uint8List>('read', {
        'uri': path,
      });
      if (data == null) throw StateError('Documento non disponibile');
      return FilePickerCross(data, path: path);
    }
    final resolved = await storage.resolve(path);
    final data = await storage.readFile(resolved);
    return FilePickerCross(data, path: resolved);
  }

  /// Persists the file. Bare names go to the app's documents directory.
  Future<String> saveToPath({required String path}) async {
    if (path.startsWith('content://')) {
      await _documents.invokeMethod<void>('write', {
        'uri': path,
        'bytes': _bytes,
      });
      return path;
    }
    final resolved = await storage.resolve(path);
    await storage.writeFile(resolved, _bytes);
    return resolved;
  }

  static Future<bool> exists(String path) async {
    if (path.startsWith('content://')) {
      return await _documents.invokeMethod<bool>('exists', {'uri': path}) ??
          false;
    }
    return storage.exists(await storage.resolve(path));
  }

  static Future<DateTime?> lastModified(String path) async {
    if (path.startsWith('content://')) {
      final millis = await _documents.invokeMethod<int>('lastModified', {
        'uri': path,
      });
      return millis == null || millis <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }
    return storage.lastModified(await storage.resolve(path));
  }

  /// Shows a "save as" dialog (or triggers a download on the web).
  Future<String?> exportToStorage({String? fileName}) async {
    String name = fileName ?? this.fileName ?? 'export';
    name = name.replaceAll('\\', '/');
    name = name.substring(name.lastIndexOf('/') + 1);
    // v13 writes the bytes itself and returns a URI, including content URIs.
    // Do not pass these to filesystem APIs or write the selected file twice.
    final savedUri = await FilePicker.saveFile(
      fileName: name,
      bytes: _bytes,
      mimeType: name.toLowerCase().endsWith('.pdf')
          ? 'application/pdf'
          : name.toLowerCase().endsWith('.json')
          ? 'application/json'
          : 'application/octet-stream',
    );
    if (savedUri == null) return kIsWeb ? name : null;
    if (savedUri.scheme == 'content') {
      await _documents.invokeMethod<bool>('retain', {
        'uri': savedUri.toString(),
      });
    }
    return savedUri.scheme == 'file'
        ? savedUri.toFilePath()
        : savedUri.toString();
  }

  static Future<void> delete({required String path}) async {
    if (path.startsWith('content://')) {
      await _documents.invokeMethod<void>('delete', {'uri': path});
      return;
    }
    await storage.deleteFile(await storage.resolve(path));
  }
}
