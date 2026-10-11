import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'compat/gzip_decode_stub.dart'
    if (dart.library.io) 'compat/gzip_decode_io.dart'
    as native;

/// Checks every write BEFORE the inflater can grow its output buffer.
class LimitedArchiveOutput extends OutputMemoryStream {
  final int limit;
  final Stopwatch _clock;
  LimitedArchiveOutput(this.limit, {Stopwatch? clock})
    : _clock = clock ?? (Stopwatch()..start()),
      super(size: limit.clamp(1, 32768));
  void _check(int count) {
    if (_clock.elapsed > const Duration(seconds: 30)) {
      throw const FormatException('Decompressione troppo complessa');
    }
    if (count < 0 || length + count > limit) {
      throw const FormatException('Limite dei dati decompressi superato');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }
}

Uint8List decodeBoundedGzip(
  Uint8List bytes, {
  required int maxInput,
  required int maxOutput,
}) {
  if (bytes.length < 18 ||
      bytes.length > maxInput ||
      bytes[0] != 0x1f ||
      bytes[1] != 0x8b) {
    throw const FormatException('File GZIP non valido o troppo grande');
  }
  final decoded = native.decodeNativeGzip(bytes, maxOutput);
  if (decoded != null) return decoded;
  final output = LimitedArchiveOutput(maxOutput);
  // Web keeps the streaming Dart decoder with trailer/CRC checks.
  if (!GZipDecoderWeb().decodeStream(
    InputMemoryStream(bytes),
    output,
    verify: true,
  )) {
    throw const FormatException('File GZIP troncato o danneggiato');
  }
  return output.getBytes();
}

/// No extraction, no symlink decoding; metadata is checked before ANY inflate.
Map<String, Uint8List> decodeBoundedZip(
  Uint8List bytes, {
  required int maxInput,
  required int maxOutput,
  required int maxEntries,
  required int Function(String name) entryLimit,
}) => decodeBoundedZipStream(
  InputMemoryStream(bytes),
  maxInput: maxInput,
  maxOutput: maxOutput,
  maxEntries: maxEntries,
  entryLimit: entryLimit,
);

Map<String, Uint8List> decodeBoundedZipStream(
  InputStream input, {
  required int maxInput,
  required int maxOutput,
  required int maxEntries,
  required int Function(String name) entryLimit,
  void Function(String name, Uint8List bytes)? onEntry,
}) {
  final clock = Stopwatch()..start();
  final length = input.length;
  int get16(int position) => ByteData.sublistView(
    input.subset(position: position, length: 2).toUint8List(),
  ).getUint16(0, Endian.little);
  int get32(int position) => ByteData.sublistView(
    input.subset(position: position, length: 4).toUint8List(),
  ).getUint32(0, Endian.little);
  if (length < 22 || length > maxInput) {
    throw const FormatException('Archivio ZIP non valido o troppo grande');
  }
  // Preflight the central directory before ZipDirectory creates its objects.
  var end = -1;
  for (var i = length - 22; i >= (length - 65557).clamp(0, length); i--) {
    if (get32(i) == 0x06054b50 && i + 22 + get16(i + 20) == length) {
      end = i;
      break;
    }
  }
  if (end < 0) throw const FormatException('Indice ZIP mancante');
  final count = get16(end + 10);
  final size = get32(end + 12);
  final offset = get32(end + 16);
  if (count == 0 ||
      count > maxEntries ||
      count == 0xffff ||
      get16(end + 4) != 0 ||
      get16(end + 6) != 0 ||
      get16(end + 8) != count ||
      size > maxEntries * 1024 ||
      offset + size != end) {
    throw const FormatException('Indice ZIP non supportato o troppo grande');
  }
  var at = offset, actualCount = 0;
  while (at < end) {
    if (at + 46 > end || get32(at) != 0x02014b50) {
      throw const FormatException('Indice ZIP danneggiato');
    }
    final name = get16(at + 28);
    final extra = get16(at + 30);
    final comment = get16(at + 32);
    if (++actualCount > maxEntries ||
        name > 256 ||
        extra > 512 ||
        comment > 256 ||
        at + 46 + name + extra + comment > end) {
      throw const FormatException('Metadati ZIP troppo grandi');
    }
    final local = get32(at + 42);
    if (local + 30 > offset || get32(local) != 0x04034b50) {
      throw const FormatException('Header locale ZIP non valido');
    }
    final localName = get16(local + 26);
    final localExtra = get16(local + 28);
    final flags = get16(at + 8);
    final method = get16(at + 10);
    final compressed = get32(at + 20);
    if (localName > 256 ||
        localExtra > 512 ||
        local +
                30 +
                localName +
                localExtra +
                compressed +
                ((flags & 8) != 0 ? 12 : 0) >
            offset ||
        get16(local + 6) != flags ||
        (flags & 1) != 0 ||
        get16(local + 8) != method ||
        (method != 0 && method != 8)) {
      throw const FormatException('Metadati locali ZIP non validi');
    }
    at += 46 + name + extra + comment;
  }
  if (actualCount != count) {
    throw const FormatException('Conteggio ZIP non valido');
  }
  final directory = ZipDirectory()..read(input);
  final names = <String>{};
  var total = 0;
  for (final header in directory.fileHeaders) {
    final file = header.file;
    final type = (header.externalFileAttributes >> 16) & 0xf000;
    if (file == null ||
        header.filename != file.filename ||
        (header.generalPurposeBitFlag & 1) != 0 ||
        (type != 0 && type != 0x8000) ||
        !names.add(header.filename) ||
        file.uncompressedSize < 0 ||
        file.uncompressedSize > entryLimit(header.filename) ||
        file.compressedSize > entryLimit(header.filename) + 65536 ||
        header.uncompressedSize != file.uncompressedSize ||
        header.crc32 != file.crc32 ||
        header.compressedSize != file.compressedSize ||
        (file.compressionMethod != CompressionType.none &&
            file.compressionMethod != CompressionType.deflate)) {
      throw const FormatException('Voce ZIP non valida');
    }
    total += file.uncompressedSize;
    if (total > maxOutput) {
      throw const FormatException('Archivio espanso troppo grande');
    }
  }
  final result = <String, Uint8List>{};
  for (final header in directory.fileHeaders) {
    final file = header.file!;
    if (clock.elapsed > const Duration(seconds: 30)) {
      throw const FormatException('Decompressione troppo complessa');
    }
    final raw = file.getRawContent();
    final Uint8List content;
    if (file.compressionMethod == CompressionType.none) {
      content = raw;
    } else {
      final output = LimitedArchiveOutput(file.uncompressedSize, clock: clock);
      Inflate.stream(InputMemoryStream(raw), output: output);
      content = output.getBytes();
    }
    if (content.length != file.uncompressedSize ||
        getCrc32(content) != file.crc32) {
      throw const FormatException('Dimensione o checksum ZIP non valido');
    }
    if (onEntry != null) {
      onEntry(header.filename, content);
    } else {
      result[header.filename] = content;
    }
  }
  return result;
}
