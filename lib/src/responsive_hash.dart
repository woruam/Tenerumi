import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Hash large attachments in bounded views, yielding to input between chunks.
Future<String> responsiveHash(Uint8List bytes) async {
  if (bytes.length <= 1024 * 1024) return sha256.convert(bytes).toString();
  final result = _DigestSink();
  final sink = sha256.startChunkedConversion(result);
  for (var offset = 0; offset < bytes.length; offset += 256 * 1024) {
    final end = (offset + 256 * 1024).clamp(0, bytes.length);
    sink.add(Uint8List.sublistView(bytes, offset, end));
    await Future<void>.delayed(Duration.zero);
  }
  sink.close();
  return result.value!.toString();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest digest) => value = digest;
  @override
  void close() {}
}
