import 'dart:convert';

import 'package:xournalpp/controllers/canvas_controller.dart';

import 'XppFile.dart';
import 'compat/file_picker_cross.dart';
import 'recent_documents.dart';

typedef LibraryMetadataLoader = Future<Map<String, dynamic>?> Function(
  Map<String, dynamic> entry,
  bool Function() stillVisible,
);

class LibraryMetadata {
  static Future<void>? _queue;
  static final _pending = <String, Future<Map<String, dynamic>?>>{};
  static final _visibleRequests = <String, List<bool Function()>>{};
  // Cache only small metadata, never parsed documents, PDF handles or pages.
  static final _cache = <String, Map<String, dynamic>>{};
  static Future<Map<String, dynamic>?> load(
    Map<String, dynamic> entry,
    bool Function() stillVisible,
  ) {
    final path = entry['path'];
    if (path is! String || path.isEmpty) return Future.value(null);
    final key = '$path|${entry['modifiedAt']}|${entry['preview']?.hashCode}';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future.value(cached);
    }
    if (_pending[key] case final Future<Map<String, dynamic>?> pending) {
      _visibleRequests[key]!.add(stillVisible);
      return pending;
    }
    _visibleRequests[key] = [stillVisible];
    bool needed() => _visibleRequests[key]?.any((request) => request()) == true;
    final result = (_queue ?? Future.value()).then((_) async {
      if (!needed()) return null;
      final metadata = <String, dynamic>{};
      CanvasController? controller;
      try {
        if (entry['modifiedAt'] == null) {
          try {
            final date = await FilePickerCross.lastModified(path);
            if (date != null) metadata['modifiedAt'] = date.toIso8601String();
          } catch (_) {
            /* Providers may expose the document without a date. */
          }
        }
        if (needed() && !hasDocumentPreview(entry['preview'])) {
          final file = await XppFile.fromFilePickerCross(
            await FilePickerCross.fromInternalPath(path: path),
            null,
            (_) async => throw StateError('Sfondo non disponibile'),
          );
          if (!needed()) return null;
          if (file.modifiedAt != null) {
            metadata['modifiedAt'] = file.modifiedAt!.toUtc().toIso8601String();
          }
          controller = CanvasController(autosaveEnabled: false)..file = file;
          try {
            metadata['preview'] = base64Encode(
              await controller.buildPreviewBytes(),
            );
          } catch (_) {
            /* Keep the icon if an external PDF or image is unavailable. */
          }
        }
        if (metadata.isNotEmpty) await RecentDocuments.enrich(entry, metadata);
        return metadata.isEmpty ? null : metadata;
      } catch (_) {
        return metadata.isEmpty ? null : metadata;
      } finally {
        controller?.dispose();
      }
    });
    _pending[key] = result;
    _queue = result.then<void>(
      (metadata) {
        _pending.remove(key);
        _visibleRequests.remove(key);
        if (metadata != null) {
          _cache[key] = metadata;
          while (_cache.length > 32) {
            _cache.remove(_cache.keys.first);
          }
        }
      },
      onError: (Object _, StackTrace _) {
        _pending.remove(key);
        _visibleRequests.remove(key);
      },
    );
    return result;
  }
}
