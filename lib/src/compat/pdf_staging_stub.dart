import 'dart:typed_data';

import 'package:pdf/pdf.dart';

const diskPdfStaging = false;
Future<String> createPdfStaging() =>
    throw UnsupportedError('Staging non disponibile');
Future<Map<String, Object>> stagePdfPage(
  String root,
  int index,
  Map<String, Object> page,
) => throw UnsupportedError('Staging non disponibile');
Map<String, Object> readPdfPage(Map<String, Object> entry) => entry;
Uint8List readPdfImage(String path) =>
    throw UnsupportedError('Staging non disponibile');
Future<Uint8List> readPdfResult(String path) =>
    throw UnsupportedError('Staging non disponibile');
Future<void> disposePdfStaging(String root) async {}

class DiskPdfStream extends PdfStream {
  DiskPdfStream(String path);
  void close() {}
}
