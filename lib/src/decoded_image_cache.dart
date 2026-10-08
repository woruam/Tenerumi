import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

class _Entry {
  final WeakReference<Uint8List> source;
  ui.Image? image;
  bool failed = false;
  _Entry(Uint8List bytes) : source = WeakReference(bytes);
  int get bytes => image == null ? 0 : image!.width * image!.height * 4;
}

/// Render resources belong to visible canvases, never to document snapshots.
/// Source bytes are weak keys so the cache cannot keep a closed note alive.
class DecodedImageCache extends ChangeNotifier {
  static final shared = DecodedImageCache();
  final int maxEntries, maxBytes;
  final int? maxDimension;
  DecodedImageCache({
    this.maxEntries = 16,
    this.maxBytes = 32 * 1024 * 1024,
    this.maxDimension,
  });
  final List<_Entry> _entries = [];
  Future<void>? _queue;
  int _epoch = 0;
  final Map<Object, List<WeakReference<Uint8List>>> _owners = {};
  int get byteCount => _entries.fold(0, (sum, e) => sum + e.bytes);
  int get entryCount => _entries.length;
  void retain(Object owner, Iterable<Uint8List> sources) {
    _owners[owner] = sources.map(WeakReference<Uint8List>.new).toList();
    _trim();
  }

  bool _pinned(_Entry entry) => _owners.values.any(
    (sources) =>
        sources.any((ref) => identical(ref.target, entry.source.target)),
  );
  void release(Object owner) {
    _owners.remove(owner);
    if (_owners.isEmpty) {
      clear();
      return;
    }
    for (final entry in List<_Entry>.of(_entries)) {
      if (!_pinned(entry)) {
        _entries.remove(entry);
        entry.image?.dispose();
      }
    }
  }

  ui.Image? lookup(Uint8List data) {
    final old = _entries
        .where((e) => identical(e.source.target, data))
        .firstOrNull;
    if (old != null) {
      _entries.remove(old);
      _entries.add(old);
      return old.image;
    }
    if (data.isEmpty) return null;
    final entry = _Entry(data);
    _entries.add(entry);
    _trim();
    final epoch = _epoch;
    final pending = (_queue ?? Future.value()).then((_) async {
      final source = entry.source.target;
      if (epoch != _epoch || !_entries.contains(entry) || source == null)
        return;
      ui.Codec? codec;
      ui.Image? result;
      try {
        // A descriptor gives dimensions before decode; preserve aspect ratio.
        final buffer = await ui.ImmutableBuffer.fromUint8List(source);
        ui.ImageDescriptor? descriptor;
        try {
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          final largest = descriptor.width > descriptor.height
              ? descriptor.width
              : descriptor.height;
          final bound = maxDimension ?? largest;
          final scale = largest > bound ? bound / largest : 1.0;
          codec = await descriptor.instantiateCodec(
            targetWidth: (descriptor.width * scale).round().clamp(1, bound),
            targetHeight: (descriptor.height * scale).round().clamp(1, bound),
          );
          result = (await codec.getNextFrame()).image;
        } finally {
          descriptor?.dispose();
          buffer.dispose();
        }
        if (epoch != _epoch || !_entries.contains(entry)) {
          result.dispose();
          return;
        }
        entry.image = result;
        _trim();
        notifyListeners();
      } catch (_) {
        result?.dispose();
        entry.failed = true;
      } finally {
        codec?.dispose();
      }
    });
    final completed = pending.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _queue = completed;
    unawaited(
      completed.then((_) {
        if (identical(_queue, completed)) _queue = null;
      }),
    );
    return null;
  }

  void _trim() {
    for (final entry in List<_Entry>.of(_entries)) {
      if (entry.source.target == null) {
        _entries.remove(entry);
        entry.image?.dispose();
      }
    }
    while (_entries.length > maxEntries || byteCount > maxBytes) {
      final entry = _entries.where((e) => !_pinned(e)).firstOrNull;
      if (entry == null)
        break; // Never evict an image being painted by a visible page.
      _entries.remove(entry);
      entry.image?.dispose();
    }
  }

  void clear() {
    _epoch++;
    for (final e in _entries) {
      e.image?.dispose();
    }
    _entries.clear();
  }

  @override
  void dispose() {
    _owners.clear();
    clear();
    super.dispose();
  }
}
