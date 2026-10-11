import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../document_limits.dart';

Uint8List compressXml(Iterable<String> parts) {
  final output = BytesBuilder(copy: false);
  for (final part in parts) {
    final bytes = utf8.encode(part);
    if (output.length + bytes.length > DocumentLimits.standard.xmlBytes) {
      throw const FormatException('Appunto oltre il limite XML di riapertura');
    }
    output.add(bytes);
  }
  return GZipEncoder().encodeBytes(output.takeBytes(), level: 1);
}
