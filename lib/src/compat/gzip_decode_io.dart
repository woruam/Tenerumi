import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Native zlib emits bounded output chunks; the sink refuses growth beyond the
/// reader budget. GZipCodec validates CRC/trailers and all concatenated members.
Uint8List decodeNativeGzip(Uint8List bytes, int maxOutput) {
  final output = _BoundedOutput(maxOutput);
  final decoder = GZipCodec().decoder.startChunkedConversion(output);
  try {
    for (var offset = 0; offset < bytes.length; offset += 16384) {
      output.checkTime();
      decoder.add(
        Uint8List.sublistView(
          bytes,
          offset,
          (offset + 16384).clamp(0, bytes.length),
        ),
      );
    }
    // Dart's native decoder can accept an incomplete final trailer on close.
    // A complete empty member forces it to finish/verify the previous member
    // before recognizing another gzip header. It contributes no output bytes.
    decoder.add(const [
      31,
      139,
      8,
      0,
      0,
      0,
      0,
      0,
      0,
      3,
      3,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);
  } finally {
    // Close releases the filter, and checks the final trailer on success.
    decoder.close();
  }
  return output.bytes.takeBytes();
}

class _BoundedOutput extends ByteConversionSink {
  _BoundedOutput(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);
  final clock = Stopwatch()..start();
  void checkTime() {
    if (clock.elapsed > const Duration(seconds: 30)) {
      throw const FormatException('Decompressione troppo complessa');
    }
  }

  @override
  void add(List<int> chunk) {
    checkTime();
    if (bytes.length + chunk.length > limit) {
      throw const FormatException('Limite dei dati decompressi superato');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
