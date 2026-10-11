import 'dart:typed_data';

import '../responsive_hash.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';

import 'backup_staging_stub.dart'
    if (dart.library.io) 'backup_staging_io.dart'
    as staging;

import 'internal_storage_generic.dart'
    if (dart.library.io) 'internal_storage_io.dart'
    as storage;

/// Compatibility layer replacing the discontinued `file_picker_cross`
/// package. It keeps the same API surface used throughout the app, but is
/// implemented on top of the maintained `file_picker` package plus
/// `path_provider` for internal app storage.
enum FileTypeCross { any, image, custom }

class FilePickerCross {
  static Future<String?> importBackupToStaging() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (file == null) return null;
    return staging.writeStream(file.readAsByteStream(), 513 * 1024 * 1024);
  }

  static Future<void> discardStagedBackup(String path) =>
      staging.disposeStaging(
        path.substring(
          0,
          path.lastIndexOf('/') > path.lastIndexOf('\\')
              ? path.lastIndexOf('/')
              : path.lastIndexOf('\\'),
        ),
      );
  static Future<String?> exportStagedFile(String source, String name) async {
    // The picker requires bytes. The complete private archive exists before it
    // touches the selected destination; failures retain that staging candidate.
    final uri = await FilePicker.saveFile(
      fileName: name,
      bytes: Uint8List(0),
      mimeType: name.endsWith('.pdf') ? 'application/pdf' : 'application/zip',
    );
    if (uri == null) return null;
    if (uri.scheme == 'content') {
      await _documents.invokeMethod<void>('writeFromFile', {
        'uri': uri.toString(),
        'source': source,
      });
      return uri.toString();
    }
    if (uri.scheme != 'file')
      throw StateError('Destinazione di esportazione non supportata');
    await staging.copyToPath(source, uri.toFilePath());
    return uri.toFilePath();
  }

  static Future<String> resolvePath(String path) => storage.resolve(path);
  static const _documents = MethodChannel('online.xournal.mobile/documents');
  final Uint8List _bytes;
  final String? path;
  bool reopenableGrant = true;
  String get contentHash => sha256.convert(_bytes).toString();
  Future<String> contentHashAsync() => responsiveHash(_bytes);
  Future<bool> verifyAt(String path, {String? expectedHash}) async {
    try {
      return await hashAt(path, maxBytes: _bytes.length + 1) ==
          (expectedHash ?? await contentHashAsync());
    } catch (_) {
      return false;
    }
  }

  static Future<String?> hashAt(
    String path, {
    int maxBytes = 128 * 1024 * 1024,
  }) async {
    if (path.startsWith('content://'))
      return _documents.invokeMethod<String>('hash', {
        'uri': path,
        'maxBytes': maxBytes,
      });
    return storage.hashFile(await storage.resolve(path), maxBytes: maxBytes);
  }

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
    int maxBytes = 128 * 1024 * 1024,
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
      // Android filters by MIME type, which has no standard entry for XOPP.
      // A mixed XOPP/PDF filter otherwise silently becomes PDF-only. Let the
      // document parser validate selected bytes, keeping PDF-only pickers exact.
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          extensions.any((extension) => extension.toLowerCase() == 'xopp')) {
        fileType = FileType.any;
        extensions = null;
      }
    }
    final file = await FilePicker.pickFile(
      type: fileType,
      allowedExtensions: extensions,
    );
    if (file == null) {
      throw 'No file selected.';
    }
    final selectedPath =
        file.path ??
        (file.uri.scheme == 'content' ? file.uri.toString() : null);
    // v13 reads local paths, Android content URIs and browser blobs through
    // PlatformFile, without requiring a filesystem path or eager withData.
    final reportedLength = file.lengthSync();
    if (reportedLength != null && reportedLength > maxBytes) {
      throw const FormatException('File troppo grande');
    }
    if (selectedPath?.startsWith('content://') == true) {
      // Use our bounded native reader for the explicitly selected SAF URI.
      return fromInternalPath(path: selectedPath!, maxBytes: maxBytes);
    }
    final data = await readLimitedBytes(file.readAsByteStream(), maxBytes);
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
    int maxBytes = 128 * 1024 * 1024,
  }) async {
    if (path.startsWith('content://')) {
      final data = await _documents.invokeMethod<Uint8List>('read', {
        'uri': path,
        'maxBytes': maxBytes,
      });
      if (data == null) throw StateError('Documento non disponibile');
      if (data.length > maxBytes) {
        throw const FormatException('File troppo grande');
      }
      return FilePickerCross(data, path: path);
    }
    final resolved = await storage.resolve(path);
    final data = await storage.readFile(resolved, maxBytes: maxBytes);
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
      reopenableGrant =
          await _documents.invokeMethod<bool>('retain', {
            'uri': savedUri.toString(),
          }) ??
          false;
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

Future<Uint8List> readLimitedBytes(
  Stream<List<int>> stream,
  int maxBytes,
) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (bytes.length + chunk.length > maxBytes) {
      throw const FormatException('File troppo grande');
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}
