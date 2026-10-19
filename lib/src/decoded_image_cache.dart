import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

import 'package:flutter/foundation.dart';

class _Entry {
  final WeakReference<Uint8List> source;
  ui.Image? image;
  bool failed = false;
  bool pending = true;
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
    this.maxEntries = 64,
    this.maxBytes = 32 * 1024 * 1024,
    this.maxDimension = 2048,
  });
  final List<_Entry> _entries = [];
  Future<void>? _queue;
  int _epoch = 0;
  final Map<Object, List<WeakReference<Uint8List>>> _owners = {};
  bool _needsRetainMaintenance = false;
  int get byteCount => _entries.fold(0, (sum, e) => sum + e.bytes);
  int get entryCount => _entries.length;
  void retain(Object owner, Iterable<Uint8List> sources) {
    final next = sources is List<Uint8List>
        ? sources
        : sources.toList(growable: false);
    final previous = _owners[owner];
    var unchanged = previous != null && previous.length == next.length;
    if (unchanged) {
      for (var i = 0; i < next.length; i++) {
        if (!identical(previous[i].target, next[i])) {
          unchanged = false;
          break;
        }
      }
    }
    if (unchanged && !_needsRetainMaintenance) return;
    if (!unchanged) {
      _owners[owner] = next.map(WeakReference<Uint8List>.new).toList();
    }
    _needsRetainMaintenance = false;
    _trim();
    final fairShare = maxBytes ~/ math.max(1, _activeSourceCount);
    if (_entries.any((e) => e.bytes > fairShare)) {
      // Downgrade on the next frame, after current painters released their use.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        for (final e in _entries) {
          if (e.bytes > fairShare) {
            e.image?.dispose();
            e.image = null;
            e.failed = false;
          }
        }
        if (_owners.isNotEmpty) notifyListeners();
      });
    }
  }

  int get _activeSourceCount => _owners.values
      .expand((e) => e)
      .map((e) => e.target)
      .whereType<Uint8List>()
      .toSet()
      .length;

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
    // Waiting visible images get another admission attempt after resources
    // were released. Dispose can run while the widget tree is locked.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_owners.isNotEmpty) notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  ui.Image? lookup(Uint8List data) {
    final old = _entries
        .where((e) => identical(e.source.target, data))
        .firstOrNull;
    if (old != null) {
      _entries.remove(old);
      _entries.add(old);
      if (old.image != null || old.failed || old.pending) return old.image;
      // A downgraded entry is admitted again at its new quality.
      _entries.remove(old);
    }
    if (data.isEmpty) return null;
    if (_entries.length >= maxEntries) {
      final unpinned = _entries.where((e) => !_pinned(e)).firstOrNull;
      if (unpinned == null) return null;
      _entries.remove(unpinned);
      unpinned.image?.dispose();
    }
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
          final width = descriptor.width, height = descriptor.height;
          if (width <= 0 ||
              height <= 0 ||
              width > 16384 ||
              height > 16384 ||
              width * height > 16 * 1024 * 1024)
            throw const FormatException('Dimensioni immagine oltre il limite');
          final largest = descriptor.width > descriptor.height
              ? descriptor.width
              : descriptor.height;
          final bound = maxDimension ?? 2048;
          final allocation = math.min(
            maxBytes - byteCount,
            maxBytes ~/ math.max(1, _activeSourceCount),
          );
          if (allocation < 4) throw StateError('Budget immagini esaurito');
          final scale = math.min(
            1.0,
            math.min(
              bound / largest,
              math.sqrt(allocation / (width * height * 4)),
            ),
          );
          var targetWidth = (width * scale).floor().clamp(1, bound);
          var targetHeight = (height * scale).floor().clamp(1, bound);
          if (targetWidth * targetHeight * 4 > allocation) {
            if (targetWidth >= targetHeight)
              targetWidth = (allocation ~/ (4 * targetHeight)).clamp(
                1,
                targetWidth,
              );
            else
              targetHeight = (allocation ~/ (4 * targetWidth)).clamp(
                1,
                targetHeight,
              );
          }
          codec = await descriptor.instantiateCodec(
            targetWidth: targetWidth,
            targetHeight: targetHeight,
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
        if (result.width * result.height * 4 + byteCount > maxBytes)
          throw StateError('Decoder oltre il budget');
        entry.image = result;
        // A decode can finish after the visible sources changed its budget.
        // The next retain must check it even if that owner's sources match.
        _needsRetainMaintenance = true;
        _trim();
        notifyListeners();
      } catch (_) {
        result?.dispose();
        entry.failed = true;
      } finally {
        entry.pending = false;
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
