import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'plugin_manifest.dart';

/// Package layout: manifest.json, main.js and additional relative JS modules.
/// Read in memory; no archive paths are ever extracted onto the filesystem.
NotePlugin decodePluginPackage(Uint8List bytes) {
  if (bytes.length > 2 * 1024 * 1024) {
    throw const FormatException('Pacchetto troppo grande');
  }
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
    return NotePlugin.parse(utf8.decode(bytes));
  }
  // Inspect metadata first: ZipDecoder otherwise inflates symlink targets
  // before the caller has a chance to check their size or type.
  final directory = ZipDirectory()..read(InputMemoryStream(bytes));
  if (directory.fileHeaders.length > 65) {
    throw const FormatException('Troppi file nel pacchetto');
  }
  var size = 0;
  final files = <String, String>{};
  for (final header in directory.fileHeaders) {
    final file = header.file!;
    final name = file.filename;
    final type = (header.externalFileAttributes >> 16) & 0xf000;
    if ((header.generalPurposeBitFlag & 1) != 0 ||
        header.filename != name ||
        (type != 0 && type != 0x8000) ||
        (name != 'manifest.json' &&
            !RegExp(r'^[a-zA-Z0-9_-]+(/[a-zA-Z0-9_-]+)*\.js$')
                .hasMatch(name))) {
      throw const FormatException('Percorso non valido nel pacchetto');
    }
    size += file.uncompressedSize;
    if (size > 2 * 1024 * 1024 || files.containsKey(name)) {
      throw const FormatException('Pacchetto troppo grande o file duplicato');
    }
    final raw = file.getRawContent();
    final Uint8List content;
    if (file.compressionMethod == CompressionType.none) {
      content = raw;
    } else if (file.compressionMethod == CompressionType.deflate) {
      final output = _LimitedPluginOutput(file.uncompressedSize);
      ZLibDecoderWeb().decodeStream(InputMemoryStream(raw), output, raw: true);
      content = output.getBytes();
    } else {
      throw const FormatException('Compressione del pacchetto non supportata');
    }
    if (content.length != file.uncompressedSize ||
        getCrc32(content) != file.crc32) {
      throw const FormatException('Pacchetto danneggiato');
    }
    files[name] = utf8.decode(content);
  }
  final source = files.remove('manifest.json');
  if (source == null) throw const FormatException('manifest.json mancante');
  final manifest = jsonDecode(source) as Map<String, dynamic>;
  if (manifest['modules'] != null) {
    throw const FormatException(
      'I moduli del pacchetto devono essere file .js',
    );
  }
  manifest['runtime'] = 'javascript';
  manifest['modules'] = files;
  return NotePlugin.parse(jsonEncode(manifest));
}

/// Reject a forged size before any decompressor output allocation can grow.
class _LimitedPluginOutput extends OutputMemoryStream {
  final int limit;
  _LimitedPluginOutput(this.limit) : super(size: 32768);
  void _check(int count) {
    if (count < 0 || length + count > limit) {
      throw const FormatException(
        'Dimensione decompressa del pacchetto non valida',
      );
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
