import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/layer_contents/XppTexImage.dart';
import 'package:xournalpp/src/ink_geometry.dart';
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
  final title = document.title;
  final exportPages = <Map<String, Object>>[];
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
    final parts = <Map<String, Object>>[];
    final paper = XppPage(
      pageSize: page.pageSize,
      background: page.background,
      layers: [],
    );
    parts.add({
      'png': await rasterizeExportPage(paper, backgroundBytes: background),
    });
    final pending = <XppContent?>[];
    Future<void> flush() async {
      if (pending.isEmpty) return;
      final overlay = XppPage(
        pageSize: page.pageSize,
        layers: [XppLayer(content: List.of(pending))],
      );
      Rect? bounds;
      for (final content in pending) {
        final rect = content == null
            ? null
            : _exportContentBounds(content, size);
        if (rect != null && rect.isFinite) {
          bounds = bounds == null ? rect : bounds.expandToInclude(rect);
        }
      }
      final crop = (bounds?.inflate(4) ?? (Offset.zero & size)).intersect(
        Offset.zero & size,
      );
      if (!crop.isEmpty) {
        parts.add({
          'png': await rasterizeExportPage(
            overlay,
            paintBackground: false,
            region: crop,
            maxScale: 4,
          ),
          'left': crop.left,
          'top': crop.top,
          'width': crop.width,
          'height': crop.height,
        });
      }
      pending.clear();
    }

    int batch = 0;
    for (final layer in page.layers ?? <XppLayer>[]) {
      if (!layer.visible) continue;
      for (final content in layer.content ?? <XppContent?>[]) {
        if (++batch % 64 == 0) await Future<void>.delayed(Duration.zero);
        if (content is XppStroke &&
            !content.isShape &&
            content.tool != XppStrokeTool.ERASER) {
          await flush();
          parts.add({
            'ink': [
              for (final p in content.points ?? <XppStrokePoint>[])
                [
                  p.x!,
                  p.y!,
                  inkRadius(
                    p.width,
                    pressureSensitive: content.tool == XppStrokeTool.PEN,
                  ),
                ],
            ],
            'color': (content.color ?? Colors.black).toARGB32(),
            'opacity': content.tool == XppStrokeTool.HIGHLIGHTER
                ? .5
                : (content.color ?? Colors.black).a,
            'cuts': [
              for (final cut in content.erasures.where((cut) => cut.isValid))
                [
                  cut.start.dx,
                  cut.start.dy,
                  cut.end.dx,
                  cut.end.dy,
                  cut.radius,
                ],
            ],
          });
        } else if (content != null) {
          pending.add(content);
        }
      }
    }
    await flush();
    exportPages.add({
      'parts': parts,
      'width': size.width,
      'height': size.height,
    });
    // Release this page's GPU resources before starting the next page.
    await Future<void>.delayed(Duration.zero);
  }
  return compute(_assemblePdf, {'title': title, 'pages': exportPages});
}

/// PNG decoding, PDF image compression and final document encoding are CPU
/// work and must not block gesture/input frames. Only portable data crosses.
Future<Uint8List> _assemblePdf(Map<String, Object?> input) async {
  final pdf = pw.Document(title: input['title'] as String?, creator: 'OSI');
  for (final item in input['pages'] as List<Map<String, Object>>) {
    final width = item['width'] as double, height = item['height'] as double;
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(width, height, marginAll: 0),
        build: (_) => pw.Stack(
          children: [
            for (final part in item['parts'] as List<Map<String, Object>>)
              if (part['png'] != null)
                pw.Positioned(
                  left: (part['left'] as double?) ?? 0,
                  top: (part['top'] as double?) ?? 0,
                  child: pw.Image(
                    pw.MemoryImage(part['png'] as Uint8List),
                    width: (part['width'] as double?) ?? width,
                    height: (part['height'] as double?) ?? height,
                    fit: pw.BoxFit.fill,
                  ),
                )
              else
                pw.CustomPaint(
                  size: PdfPoint(width, height),
                  painter: (canvas, _) =>
                      _paintPdfInk(canvas, part, width, height),
                ),
          ],
        ),
      ),
    );
  }
  return pdf.save();
}

// Selection bounds are approximate for text. Export crops must measure actual
// glyphs and wrapped lines, otherwise a sharp crop can silently truncate them.
Rect? _exportContentBounds(XppContent content, Size pageSize) {
  TextStyle? style;
  String? text;
  Offset? offset;
  if (content is XppText) {
    text = content.text;
    offset = content.offset;
    style = TextStyle(
      fontSize: content.size ?? 12,
      fontFamily: content.fontFamily ?? 'Sans',
    );
  } else if (content is XppTexImage) {
    text = content.text;
    offset = content.topLeft;
    style = const TextStyle(
      fontSize: 18,
      fontStyle: FontStyle.italic,
      fontFamily: 'serif',
    );
  }
  if (style == null || offset == null) return content.bounds();
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  );
  try {
    painter.layout(
      maxWidth: content is XppText ? pageSize.width : double.infinity,
    );
    return offset & painter.size;
  } finally {
    painter.dispose();
  }
}

// Uses the same circles and tapered quadrilaterals as InkGeometry. A single
// nonzero fill per stroke prevents dark seams at highlighter intersections.
void _paintPdfInk(
  PdfGraphics canvas,
  Map<String, Object> part,
  double width,
  double height,
) {
  final samples = part['ink'] as List<List<double>>;
  if (samples.isEmpty) return;
  void polygon(List<List<double>> vertices) {
    canvas.moveTo(vertices.first[0], height - vertices.first[1]);
    for (final p in vertices.skip(1)) {
      canvas.lineTo(p[0], height - p[1]);
    }
    canvas.closePath();
  }

  List<List<double>> quad(List<double> a, List<double> b) {
    final dx = b[0] - a[0], dy = b[1] - a[1];
    final distance = math.sqrt(dx * dx + dy * dy);
    final nx = -dy / distance, ny = dx / distance;
    return [
      [a[0] - nx * a[2], a[1] - ny * a[2]],
      [b[0] - nx * b[2], b[1] - ny * b[2]],
      [b[0] + nx * b[2], b[1] + ny * b[2]],
      [a[0] + nx * a[2], a[1] + ny * a[2]],
    ];
  }

  canvas.saveContext();
  // Intersect complements of each primitive: overlapping cuts subtract their
  // union, rather than producing the holes of a single even-odd mask.
  for (final cut in part['cuts'] as List<List<double>>) {
    final a = [cut[0], cut[1], cut[4]], b = [cut[2], cut[3], cut[4]];
    for (final p in [a, b]) {
      canvas.drawRect(0, 0, width, height);
      canvas.drawEllipse(p[0], height - p[1], p[2], p[2]);
      canvas.clipPath(evenOdd: true);
    }
    if (a[0] != b[0] || a[1] != b[1]) {
      canvas.drawRect(0, 0, width, height);
      polygon(quad(a, b));
      canvas.clipPath(evenOdd: true);
    }
  }
  canvas.setFillColor(PdfColor.fromInt(part['color'] as int));
  canvas.setGraphicState(PdfGraphicState(opacity: part['opacity'] as double));
  List<double>? previous;
  for (final p in samples) {
    if (previous != null && (p[0] != previous[0] || p[1] != previous[1])) {
      polygon(quad(previous, p));
    }
    // Flipping the page Y axis reverses polygon winding.
    canvas.drawEllipse(p[0], height - p[1], p[2], p[2], clockwise: false);
    canvas.closePath();
    previous = p;
  }
  canvas.fillPath();
  canvas.restoreContext();
}

/// Shares the editor's content painters; images are decoded before painting,
/// so export never captures an asynchronous grey placeholder.
Future<Uint8List> rasterizeExportPage(
  XppPage page, {
  Uint8List? backgroundBytes,
  bool paintBackground = true,
  Rect? region,
  double maxScale = 2,
  int maxDimension = 4096,
  int pixelBudget = 4000000,
}) async {
  if (maxDimension < 1 || pixelBudget < 1) {
    throw ArgumentError('Raster budget must be positive');
  }
  if (page.infinite) page = exportPageSnapshot(page);
  final size = (page.pageSize ?? XppPageSize.a4).toSize();
  if (!size.width.isFinite || !size.height.isFinite || size.isEmpty) {
    throw StateError('Dimensioni della pagina non valide');
  }
  final area = region ?? (Offset.zero & size);
  final scale = math.min(
    maxScale,
    math.min(
      maxDimension / math.max(area.width, area.height),
      math.sqrt(pixelBudget / (area.width * area.height)),
    ),
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(scale)
    ..translate(-area.left, -area.top);
  final images = <ui.Image>[];
  ui.Picture? picture;
  ui.Image? output;
  Future<ui.Image> decode(Uint8List bytes, Rect destination) async {
    final targetWidth = math.max(
      1,
      math.min(maxDimension, (destination.width * scale).ceil()),
    );
    final targetHeight = math.max(
      1,
      math.min(maxDimension, (destination.height * scale).ceil()),
    );
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      allowUpscaling: false,
    );
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
    if (paintBackground) paintPaperBackground(canvas, size, page.background);
    if (backgroundBytes != null) {
      drawImage(
        await decode(backgroundBytes, Offset.zero & size),
        Offset.zero & size,
      );
    }
    int batch = 0;
    for (final layer in page.layers ?? <XppLayer>[]) {
      if (!layer.visible) continue;
      for (final content in layer.content ?? <XppContent?>[]) {
        if (content == null) continue;
        if (++batch % 64 == 0) await Future<void>.delayed(Duration.zero);
        if (content is XppImage) {
          if (content.data == null ||
              content.topLeft == null ||
              content.bottomRight == null) {
            throw StateError('Immagine non valida nel documento');
          }
          drawImage(
            await decode(content.data!, content.bounds()!),
            content.bounds()!,
          );
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
      math.max(1, (area.width * scale).ceil()),
      math.max(1, (area.height * scale).ceil()),
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
