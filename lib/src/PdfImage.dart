import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/XppPageSize.dart';

import 'document_limits.dart';

void validatePdfPage(pdfx.PdfDocument doc, int index) {
  if (doc.pagesCount < 1 ||
      doc.pagesCount > DocumentLimits.standard.pages ||
      index < 0 ||
      index >= doc.pagesCount) {
    throw const FormatException('Pagina PDF fuori intervallo');
  }
}

void validatePdfSize(pdfx.PdfPage page) {
  documentNumber(
    '${page.width}',
    min: 0.01,
    max: DocumentLimits.maxPageDimension,
  );
  documentNumber(
    '${page.height}',
    min: 0.01,
    max: DocumentLimits.maxPageDimension,
  );
}

void _validatePdfBytes(FilePickerCross pdf) {
  if (pdf.toUint8List().length > DocumentLimits.standard.mediaBytes) {
    throw const FormatException('PDF troppo grande');
  }
}

Future<int> pdfPageCount(FilePickerCross pdf) async {
  _validatePdfBytes(pdf);
  final doc = await pdfx.PdfDocument.openData(pdf.toUint8List());
  try {
    validatePdfPage(doc, 0);
    return doc.pagesCount;
  } finally {
    await doc.close();
  }
}

Future<Uint8List> pdfImage(FilePickerCross pdf, int? index) async {
  _validatePdfBytes(pdf);
  final doc = await pdfx.PdfDocument.openData(pdf.toUint8List());
  try {
    validatePdfPage(doc, index ?? 0);
    final page = await doc.getPage((index ?? 0) + 1);
    try {
      validatePdfSize(page);
      final scale = math.min(
        2.0,
        math.sqrt(1000000 / (page.width * page.height)),
      );
      final raster = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: pdfx.PdfPageImageFormat.png,
      );
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
  _validatePdfBytes(pdf);
  final doc = await pdfx.PdfDocument.openData(pdf.toUint8List());
  try {
    validatePdfPage(doc, index);
    final page = await doc.getPage(index + 1);
    try {
      validatePdfSize(page);
      return XppPageSize(width: page.width, height: page.height);
    } finally {
      await page.close();
    }
  } finally {
    await doc.close();
  }
}
