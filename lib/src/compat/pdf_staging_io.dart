import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';

import 'backup_staging_io.dart';

const diskPdfStaging = true;
Future<String> createPdfStaging() => createStaging();
Future<Map<String, Object>> stagePdfPage(
  String root,
  int index,
  Map<String, Object> page,
) async {
  final parts = <Map<String, Object>>[];
  for (final source in page['parts'] as List<Map<String, Object>>) {
    final part = Map<String, Object>.of(source);
    if (part['png'] is Uint8List) {
      final bytes = part.remove('png') as Uint8List;
      final hash = sha256.convert(bytes).toString();
      final file = File('$root/$hash.png');
      if (!await file.exists()) {
        await checkQuota(root, bytes.length);
        await file.writeAsBytes(bytes, flush: true);
      }
      part['pngPath'] = file.path;
      part['imageKey'] = hash;
    }
    parts.add(part);
  }
  final encoded = utf8.encode(jsonEncode({...page, 'parts': parts}));
  if (encoded.length > 32 * 1024 * 1024)
    throw StateError('Pagina PDF oltre il budget di lavoro');
  await checkQuota(root, encoded.length);
  final file = File('$root/page-$index.json');
  await file.writeAsBytes(encoded, flush: true);
  return {
    'path': file.path,
    'width': page['width']!,
    'height': page['height']!,
  };
}

Map<String, Object> readPdfPage(Map<String, Object> entry) {
  final file = File(entry['path'] as String);
  if (file.lengthSync() > 32 * 1024 * 1024)
    throw StateError('Pagina PDF troppo grande');
  final page = Map<String, Object>.from(
    jsonDecode(file.readAsStringSync()) as Map,
  );
  page['parts'] = (page['parts'] as List).map((v) {
    final part = Map<String, Object>.from(v as Map);
    for (final key in ['ink', 'cuts']) {
      if (part[key] is List)
        part[key] = (part[key] as List)
            .map(
              (line) =>
                  (line as List).map((n) => (n as num).toDouble()).toList(),
            )
            .toList();
    }
    if (part['textLines'] is List)
      part['textLines'] = (part['textLines'] as List)
          .map((v) => Map<String, Object>.from(v as Map))
          .toList();
    return part;
  }).toList();
  return page;
}

Uint8List readPdfImage(String path) {
  final file = File(path);
  if (file.lengthSync() > 32 * 1024 * 1024)
    throw StateError('Immagine PDF troppo grande');
  return file.readAsBytesSync();
}

Future<Uint8List> readPdfResult(String path) async {
  if (await File(path).length() > 128 * 1024 * 1024)
    throw StateError('PDF troppo grande');
  return File(path).readAsBytes();
}

Future<void> disposePdfStaging(String root) => disposeStaging(root);

class DiskPdfStream extends PdfStream {
  DiskPdfStream(String path)
    : _file = File(path).openSync(mode: FileMode.write);
  final RandomAccessFile _file;
  final _buffer = Uint8List(65536);
  int _used = 0, _position = 0;
  @override
  int get offset => _position;
  void _flush() {
    if (_used > 0) {
      _file.writeFromSync(_buffer, 0, _used);
      _used = 0;
    }
  }

  @override
  void putByte(int byte) {
    if (_position >= 128 * 1024 * 1024) throw StateError('PDF oltre 128 MiB');
    _buffer[_used++] = byte;
    _position++;
    if (_used == _buffer.length) _flush();
  }

  @override
  void putBytes(List<int> bytes) {
    if (_position + bytes.length > 128 * 1024 * 1024)
      throw StateError('PDF oltre 128 MiB');
    var at = 0;
    while (at < bytes.length) {
      final count = (bytes.length - at).clamp(0, _buffer.length - _used);
      _buffer.setRange(_used, _used + count, bytes, at);
      _used += count;
      at += count;
      _position += count;
      if (_used == _buffer.length) _flush();
    }
  }

  @override
  void setBytes(int offset, Iterable<int> bytes) {
    _flush();
    final current = _file.positionSync();
    _file.setPositionSync(offset);
    _file.writeFromSync(bytes.toList());
    _file.setPositionSync(current);
  }

  @override
  void putStream(PdfStream stream) => putBytes(stream.output());
  @override
  Uint8List output() => throw UnsupportedError('Usare il file PDF prodotto');
  void close() {
    _flush();
    _file.flushSync();
    _file.closeSync();
  }
}
