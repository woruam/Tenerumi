import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/content_snapshot.dart';

/// Infinite notes export as a finite sheet fitted to visible content. Originals
/// retain their absolute (possibly negative) coordinates in the XOPP file.
XppPage exportPageSnapshot(XppPage source) {
  final layers = [
    for (final layer in source.layers ?? <XppLayer>[])
      XppLayer(
        name: layer.name,
        visible: layer.visible,
        locked: layer.locked,
        content: cloneContents(layer.content ?? []),
      ),
  ];
  if (!source.infinite) {
    return XppPage(
      pageSize: source.pageSize,
      background: source.background,
      layers: layers,
    );
  }
  Rect? bounds;
  for (final layer in layers.where((layer) => layer.visible)) {
    for (final content in layer.content ?? []) {
      final rect = content?.bounds();
      if (rect != null && rect.isFinite) {
        bounds = bounds == null ? rect : bounds.expandToInclude(rect);
      }
    }
  }
  final area = bounds?.inflate(24) ?? const Rect.fromLTWH(0, 0, 595, 842);
  for (final layer in layers) {
    for (final content in layer.content ?? []) {
      content?.translate(-area.topLeft);
    }
  }
  return XppPage(
    pageSize: XppPageSize(
      width: math.max(1, area.width),
      height: math.max(1, area.height),
    ),
    background: source.background,
    layers: layers,
  );
}

typedef ExportBackgroundLoader = Future<Uint8List?> Function(
  int index,
  XppBackground background,
);

/// Export model pages, including pages that have never been mounted or cached.
/// Mutable content is frozen before the first asynchronous operation.
Future<Uint8List> buildNotesPdf(
  XppFile document, {
  required ExportBackgroundLoader loadBackground,
}) async {
  final pages = document.pages?.map(exportPageSnapshot).toList();
  if (pages == null || pages.isEmpty) {
    throw StateError('Il documento non contiene pagine');
  }
  final pdf = pw.Document(title: document.title, creator: 'OSIpp');
  for (var index = 0; index < pages.length; index++) {
    final page = pages[index];
    final size = (page.pageSize ?? XppPageSize.a4).toSize();
    Uint8List? background;
    if (page.background case final XppBackground source
        when source is XppBackgroundPdf || source is XppBackgroundImage) {
      background = await loadBackground(index, source);
      if (background == null) {
        throw StateError(
          'Impossibile caricare lo sfondo della pagina ${index + 1}',
        );
      }
    }
    final png = await rasterizeExportPage(page, backgroundBytes: background);
    final image = pw.MemoryImage(png);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(size.width, size.height, marginAll: 0),
        build: (_) => pw.Image(
          image,
          width: size.width,
          height: size.height,
          fit: pw.BoxFit.fill,
        ),
      ),
    );
    // Release this page's GPU resources before starting the next page.
    await Future<void>.delayed(Duration.zero);
  }
  return pdf.save();
}

/// Shares the editor's content painters; images are decoded before painting,
/// so export never captures an asynchronous grey placeholder.
Future<Uint8List> rasterizeExportPage(
  XppPage page, {
  Uint8List? backgroundBytes,
}) async {
  if (page.infinite) page = exportPageSnapshot(page);
  final size = (page.pageSize ?? XppPageSize.a4).toSize();
  if (!size.width.isFinite || !size.height.isFinite || size.isEmpty) {
    throw StateError('Dimensioni della pagina non valide');
  }
  final scale = math.min(
    2.0,
    math.min(
      4096 / math.max(size.width, size.height),
      math.sqrt(4000000 / (size.width * size.height)),
    ),
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);
  final images = <ui.Image>[];
  ui.Picture? picture;
  ui.Image? output;
  Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final image = (await codec.getNextFrame()).image;
      images.add(image);
      return image;
    } finally {
      codec.dispose();
    }
  }

  void drawImage(ui.Image image, Rect destination) => canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    destination,
    Paint()..filterQuality = FilterQuality.high,
  );
  try {
    canvas.clipRect(Offset.zero & size);
    paintPaperBackground(canvas, size, page.background);
    if (backgroundBytes != null) {
      drawImage(await decode(backgroundBytes), Offset.zero & size);
    }
    for (final layer in page.layers ?? <XppLayer>[]) {
      if (!layer.visible) continue;
      for (final content in layer.content ?? <XppContent?>[]) {
        if (content == null) continue;
        if (content is XppImage) {
          if (content.data == null ||
              content.topLeft == null ||
              content.bottomRight == null) {
            throw StateError('Immagine non valida nel documento');
          }
          drawImage(await decode(content.data!), content.bounds()!);
        } else {
          canvas.save();
          final offset = content.getOffset();
          if (offset != null) canvas.translate(offset.dx, offset.dy);
          content.paintToCanvas(canvas, size);
          canvas.restore();
        }
      }
    }
    picture = recorder.endRecording();
    output = await picture.toImage(
      math.max(1, (size.width * scale).ceil()),
      math.max(1, (size.height * scale).ceil()),
    );
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Impossibile creare la pagina PDF');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    output?.dispose();
    (picture ?? recorder.endRecording()).dispose();
    for (final image in images) {
      image.dispose();
    }
  }
}
