import 'dart:collection';
import 'dart:typed_data';

/// LRU bounded by both compressed bytes and page count.
class PdfRasterCache extends MapBase<int, Uint8List> {
  final int maxPages;
  final int maxBytes;
  final _entries = LinkedHashMap<int, Uint8List>();
  int byteCount = 0;
  PdfRasterCache({this.maxPages = 8, this.maxBytes = 16 * 1024 * 1024});
  @override
  Uint8List? operator [](Object? key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key as int] = value;
    return value;
  }

  @override
  void operator []=(int key, Uint8List value) {
    remove(key);
    if (value.lengthInBytes > maxBytes) return;
    _entries[key] = value;
    byteCount += value.lengthInBytes;
    while (_entries.length > maxPages || byteCount > maxBytes) {
      remove(_entries.keys.first);
    }
  }

  @override
  Iterable<int> get keys => _entries.keys;
  @override
  Uint8List? remove(Object? key) {
    final value = _entries.remove(key);
    if (value != null) byteCount -= value.lengthInBytes;
    return value;
  }

  @override
  void clear() {
    _entries.clear();
    byteCount = 0;
  }
}
