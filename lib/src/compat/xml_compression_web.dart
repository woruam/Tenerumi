import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../document_limits.dart';

Uint8List compressXml(Iterable<String> parts) =>
    compressBytes(parts.map(utf8.encode));

Uint8List compressBytes(Iterable<List<int>> parts) {
  final output = BytesBuilder(copy: false);
  for (final part in parts) {
    final bytes = part;
    if (output.length + bytes.length > DocumentLimits.standard.xmlBytes) {
      throw const FormatException('Appunto oltre il limite XML di riapertura');
    }
    output.add(bytes);
  }
  return GZipEncoder().encodeBytes(output.takeBytes(), level: 1);
}
