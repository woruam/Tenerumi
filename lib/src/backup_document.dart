import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'bounded_archive.dart';
import 'document_limits.dart';
import 'compat/xml_compression_web.dart'
    if (dart.library.io) 'compat/xml_compression_io.dart'
    as compression;

/// Change only the root metadata. Audio, point timing and unsupported XML stay
/// byte-for-byte intact in the body; no document graph or base64 is rebuilt.
Future<Uint8List> copyBackupDocument(
  Uint8List bytes, {
  required String documentId,
  required String? tag,
}) => compute(_copyDocument, {'bytes': bytes, 'id': documentId, 'tag': tag});

Uint8List _copyDocument(Map<String, Object?> input) {
  final bytes = decodeBoundedGzip(
    input['bytes'] as Uint8List,
    maxInput: DocumentLimits.standard.compressedBytes,
    maxOutput: DocumentLimits.standard.xmlBytes,
  );
  final bom =
      bytes.length >= 3 && bytes[0] == 239 && bytes[1] == 187 && bytes[2] == 191
      ? 3
      : 0;
  final prefix = utf8.decode(
    Uint8List.sublistView(bytes, bom, (bom + 65536).clamp(bom, bytes.length)),
    allowMalformed: true,
  );
  var cursor = 0;
  late int start;
  while (true) {
    start = prefix.indexOf('<', cursor);
    if (start < 0) {
      throw const FormatException('Intestazione appunto non valida');
    }
    if (prefix.startsWith('<?', start) || prefix.startsWith('<!--', start)) {
      final comment = prefix.startsWith('<!--', start);
      final marker = comment ? '-->' : '?>';
      final end = prefix.indexOf(marker, start + 2);
      if (end < 0) {
        throw const FormatException('Intestazione appunto troppo lunga');
      }
      cursor = end + marker.length;
      continue;
    }
    break;
  }
  if (!RegExp(r'^<xournal(?:\s|>)').hasMatch(prefix.substring(start))) {
    throw const FormatException('Intestazione Xournal non valida');
  }
  int quote = 0, end = start;
  for (; end < prefix.length; end++) {
    final c = prefix.codeUnitAt(end);
    if (quote != 0) {
      if (c == quote) quote = 0;
    } else if (c == 34 || c == 39) {
      quote = c;
    } else if (c == 62) {
      break;
    }
  }
  if (end == prefix.length) {
    throw const FormatException('Intestazione appunto troppo lunga');
  }
  final root = XmlDocument.parse(
    '${prefix.substring(start, end + 1)}</xournal>',
  ).rootElement;
  root.setAttribute('osipp-id', input['id'] as String);
  if (input['tag'] case final String tag) {
    root.setAttribute('osipp-tag', tag);
  } else {
    root.removeAttribute('osipp-tag');
  }
  root.isSelfClosing = true;
  final opening = root.toXmlString();
  final replacement = utf8.encode(
    '${opening.substring(0, opening.length - 2)}>',
  );
  final before = bom + utf8.encode(prefix.substring(0, start)).length;
  final after = bom + utf8.encode(prefix.substring(0, end + 1)).length;
  Iterable<List<int>> parts() sync* {
    yield Uint8List.sublistView(bytes, 0, before);
    yield replacement;
    for (var offset = after; offset < bytes.length; offset += 65536) {
      yield Uint8List.sublistView(
        bytes,
        offset,
        (offset + 65536).clamp(0, bytes.length),
      );
    }
  }

  final copied = compression.compressBytes(parts());
  if (copied.length > DocumentLimits.standard.compressedBytes) {
    throw const FormatException('Appunto ripristinato troppo grande');
  }
  return copied;
}
