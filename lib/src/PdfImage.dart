import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/XppPageSize.dart';

Future<int> pdfPageCount(FilePickerCross pdf) async {
  final doc = await pdfx.PdfDocument.openData(pdf.toUint8List());
  try {
    return doc.pagesCount;
  } finally {
    await doc.close();
  }
}

Future<Uint8List> pdfImage(FilePickerCross pdf, int? index) async {
  final doc = await pdfx.PdfDocument.openData(pdf.toUint8List());
  try {
    final page = await doc.getPage((index ?? 0) + 1);
    try {
      final scale =
          math.min(2.0, math.sqrt(1000000 / (page.width * page.height)));
      final raster = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: pdfx.PdfPageImageFormat.png);
      if (raster == null) throw StateError('PDF page could not be rendered');
      return raster.bytes;
    } finally {
      await page.close();
    }
  } finally {
    await doc.close();
  }
}

Future<XppPageSize> pdfPageSize(FilePickerCross pdf, int index) async {
  final doc = await pdfx.PdfDocument.openData(pdf.toUint8List());
  try {
    final page = await doc.getPage(index + 1);
    try {
      return XppPageSize(width: page.width, height: page.height);
    } finally {
      await page.close();
    }
  } finally {
    await doc.close();
  }
}
