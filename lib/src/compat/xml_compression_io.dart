import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../document_limits.dart';

Uint8List compressXml(Iterable<String> parts) {
  final output = BytesBuilder(copy: false);
  final encoder = GZipCodec(level: 1).encoder
      .startChunkedConversion(_Output(output));
  var length = 0;
  try {
    for (final part in parts) {
      final bytes = utf8.encode(part);
      length += bytes.length;
      if (length > DocumentLimits.standard.xmlBytes) {
        throw const FormatException(
          'Appunto oltre il limite XML di riapertura',
        );
      }
      encoder.add(bytes);
    }
  } finally {
    encoder.close();
  }
  return output.takeBytes();
}

class _Output implements Sink<List<int>> {
  final BytesBuilder output;
  _Output(this.output);
  @override
  void add(List<int> bytes) => output.add(bytes);
  @override
  void close() {}
}
