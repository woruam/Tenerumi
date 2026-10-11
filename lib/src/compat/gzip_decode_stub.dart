import 'dart:typed_data';

// Browser builds retain the bounded Dart inflater and its CRC verification.
Uint8List? decodeNativeGzip(Uint8List bytes, int maxOutput) => null;
