import 'dart:math' as math;
import 'dart:async';

import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/XppPageSize.dart';

import 'document_limits.dart';

Future<void>? _openingPdf;

/// Serialize platform transfers as well as native parsing: scrolling must not
/// enqueue many complete copies of one PDF in the Android message queue.
Future<pdfx.PdfDocument> openPdfData(Uint8List bytes) {
  final opening = (_openingPdf ?? Future.value()).then((_) {
    if (bytes.length > DocumentLimits.standard.mediaBytes) {
      throw const FormatException('PDF troppo grande');
    }
    return pdfx.PdfDocument.openData(bytes);
  });
  final completed = opening.then<void>(
    (_) {},
    onError: (Object _, StackTrace _) {},
  );
  _openingPdf = completed;
  unawaited(
    completed.then((_) {
      if (identical(_openingPdf, completed)) _openingPdf = null;
    }),
  );
  return opening;
}

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
  final doc = await openPdfData(pdf.toUint8List());
  try {
    validatePdfPage(doc, 0);
    return doc.pagesCount;
  } finally {
    await doc.close();
  }
}

Future<Uint8List> pdfImage(FilePickerCross pdf, int? index) async {
  _validatePdfBytes(pdf);
  final doc = await openPdfData(pdf.toUint8List());
  try {
    validatePdfPage(doc, index ?? 0);
    final page = await doc.getPage((index ?? 0) + 1);
    try {
      validatePdfSize(page);
      final scale = math.min(
        2.0,
        math.min(
          4096 / math.max(page.width, page.height),
          math.sqrt(1000000 / (page.width * page.height)),
        ),
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
  final doc = await openPdfData(pdf.toUint8List());
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

Future<List<XppPageSize>> pdfPageSizes(FilePickerCross pdf) async {
  _validatePdfBytes(pdf);
  final doc = await openPdfData(pdf.toUint8List());
  try {
    return await pdfDocumentSizes(doc);
  } finally {
    await doc.close();
  }
}

Future<List<XppPageSize>> pdfDocumentSizes(pdfx.PdfDocument doc) async {
  validatePdfPage(doc, 0);
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final values = await const MethodChannel(
        'online.xournal.mobile/pdf-metadata',
      ).invokeMethod<List<dynamic>>('pageSizes', {'documentId': doc.id});
      if (values == null || values.length != doc.pagesCount * 2) {
        throw const FormatException('Dimensioni PDF incomplete');
      }
      return List.generate(
        doc.pagesCount,
        (i) => XppPageSize(
          width: documentNumber(
            '${values[i * 2]}',
            min: .01,
            max: DocumentLimits.maxPageDimension,
          ),
          height: documentNumber(
            '${values[i * 2 + 1]}',
            min: .01,
            max: DocumentLimits.maxPageDimension,
          ),
        ),
      );
    } on MissingPluginException {
      // Older platforms/test backends retain the exact per-page fallback.
    }
  }
  final sizes = <XppPageSize>[];
  for (var index = 0; index < doc.pagesCount; index++) {
    final page = await doc.getPage(index + 1);
    try {
      validatePdfSize(page);
      sizes.add(XppPageSize(width: page.width, height: page.height));
    } finally {
      await page.close();
    }
  }
  return sizes;
}
