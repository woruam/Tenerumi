import 'package:xournalpp/src/app_brand.dart';

import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'compat/pdf_staging_stub.dart'
    if (dart.library.io) 'compat/pdf_staging_io.dart'
    as stage;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'compat/internal_storage_generic.dart'
    if (dart.library.io) 'compat/internal_storage_io.dart'
    as font_storage;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  int pixelBudget,
);

class PreparedPdf {
  final Uint8List? bytes;
  final String? path, root;
  PreparedPdf({this.bytes, this.path, this.root});
  Future<void> dispose() async {
    if (root != null) await stage.disposePdfStaging(root!);
  }
}

Future<Uint8List> buildNotesPdf(
  XppFile document, {
  required ExportBackgroundLoader loadBackground,
}) async {
  final result = await prepareNotesPdf(
    document,
    loadBackground: loadBackground,
  );
  try {
    return result.bytes ?? await stage.readPdfResult(result.path!);
  } finally {
    await result.dispose();
  }
}

/// Export model pages, including pages that have never been mounted or cached.
/// Mutable content is frozen before the first asynchronous operation.
Future<PreparedPdf> prepareNotesPdf(
  XppFile document, {
  required ExportBackgroundLoader loadBackground,
}) async {
  final pages = document.pages?.map(exportPageSnapshot).toList();
  if (pages == null || pages.isEmpty) {
    throw StateError('Il documento non contiene pagine');
  }
  final title = document.title;
  final exportPages = <Map<String, Object>>[];
  final root = stage.diskPdfStaging ? await stage.createPdfStaging() : null;
  var workingBytes = 0;
  final imageHashes = <String>{};
  final preparedImages = <Uint8List, Future<Uint8List>>{};
  final sourceImages = <Uint8List>{};
  var backgroundCount = 0;
  for (final page in pages) {
    if (page.background is XppBackgroundPdf ||
        page.background is XppBackgroundImage ||
        page.background is XppBackgroundSolidDot ||
        page.background is XppBackgroundSmith)
      backgroundCount++;
    for (final item
        in page.layers?.expand((l) => l.content ?? <XppContent?>[]) ??
            <XppContent?>[]) {
      if (item is XppImage && item.data != null) sourceImages.add(item.data!);
    }
  }
  final pixelBudget = math.min(
    4000000,
    16 * 1024 * 1024 ~/ math.max(1, sourceImages.length + backgroundCount),
  );
  Future<Uint8List> image(Uint8List data) => preparedImages.putIfAbsent(
    data,
    () => _boundedPdfImage(data, pixelBudget),
  );
  try {
    final fonts = <String, Uint8List>{};
    final unavailableFonts = <String>{};
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      final size = (page.pageSize ?? XppPageSize.a4).toSize();
      Uint8List? background;
      if (page.background case final XppBackground source
          when source is XppBackgroundPdf || source is XppBackgroundImage) {
        background = await loadBackground(index, source, pixelBudget);
        if (background == null) {
          throw StateError(
            'Impossibile caricare lo sfondo della pagina ${index + 1}',
          );
        }
      }
      final parts = <Map<String, Object>>[];
      if (page.background is XppBackgroundSolidDot ||
          page.background is XppBackgroundSmith) {
        // Dense dots and the Smith chart share the editor's bounded painter;
        // ink remains vector and the chart has identical clipped geometry.
        parts.add({
          'png': await rasterizeExportPage(
            XppPage(
              pageSize: page.pageSize,
              background: page.background,
              layers: [],
            ),
            maxScale: 4,
          ),
        });
      } else if (background != null) {
        parts.add({'png': await image(background)});
      } else {
        final source = page.background;
        parts.add({
          'paper': switch (source) {
            XppBackgroundNothingDark() => 'nothingDark',
            XppBackgroundNothingLight() => 'nothingLight',
            XppBackgroundSolidDot() => 'dot',
            XppBackgroundSolidGraph() => 'graph',
            XppBackgroundSolidLined() || XppBackgroundSolidRuled() => 'lines',
            _ => 'plain',
          },
          'color': (source?.color ?? Colors.white).toARGB32(),
        });
      }
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
          if (content is XppImage &&
              content.data != null &&
              content.bounds() != null) {
            await flush();
            final rect = content.bounds()!;
            parts.add({
              'png': await image(content.data!),
              'left': rect.left,
              'top': rect.top,
              'width': rect.width,
              'height': rect.height,
            });
          } else if (content is XppText &&
              _vectorFontAsset(content) != null &&
              !RegExp(r'[^\u000a\u000d\u0020-\u024f]')
                  .hasMatch(content.text ?? '')) {
            await flush();
            final asset = _vectorFontAsset(content)!;
            if (!fonts.containsKey(asset) &&
                !unavailableFonts.contains(asset)) {
              try {
                if (asset.startsWith('/system/fonts/')) {
                  fonts[asset] = await font_storage.readFile(asset);
                } else {
                  final data = await rootBundle.load(asset);
                  fonts[asset] = data.buffer.asUint8List(
                    data.offsetInBytes,
                    data.lengthInBytes,
                  );
                }
              } catch (_) {
                unavailableFonts.add(asset);
              }
            }
            if (fonts.containsKey(asset)) {
              parts.add(_vectorText(content, size, asset));
            } else {
              pending.add(content);
            }
          } else if (content is XppStroke) {
            await flush();
            parts.add({
              'ink': [
                for (final p in content.points ?? <XppStrokePoint>[])
                  [
                    p.x!,
                    p.y!,
                    inkRadius(
                      p.width,
                      pressureSensitive:
                          content.tool == XppStrokeTool.PEN &&
                          !content.widthIsDiameter,
                    ),
                  ],
              ],
              'shape': content.isShape,
              'smooth': content.smooth,
              'lineWidth': (content.points?.firstOrNull?.width ?? 2.5).clamp(
                1.0,
                double.infinity,
              ),
              'color':
                  (content.tool == XppStrokeTool.ERASER
                          ? Colors.white
                          : content.color ?? Colors.black)
                      .toARGB32(),
              'opacity': content.tool == XppStrokeTool.HIGHLIGHTER
                  ? .5
                  : content.tool == XppStrokeTool.ERASER
                  ? 1.0
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
      var pageBytes = 0;
      for (final part in parts) {
        if (part['png'] is Uint8List) {
          final bytes = part['png'] as Uint8List;
          final hash = sha256.convert(bytes).toString();
          if (imageHashes.add(hash)) workingBytes += bytes.length;
        }
        if (part['ink'] is List) pageBytes += (part['ink'] as List).length * 48;
        if (part['textLines'] is List) pageBytes += part.toString().length * 2;
      }
      workingBytes += pageBytes;
      if (workingBytes > 32 * 1024 * 1024)
        throw StateError('Export PDF oltre il budget di lavoro di 32 MiB');
      final record = <String, Object>{
        'parts': parts,
        'width': size.width,
        'height': size.height,
      };
      exportPages.add(
        root == null ? record : await stage.stagePdfPage(root, index, record),
      );
      // Release this page's GPU resources before starting the next page.
      await Future<void>.delayed(Duration.zero);
    }
    if (root != null) {
      final path = '$root/export.pdf';
      await compute(_assemblePdf, {
        'title': title,
        'pages': exportPages,
        'fonts': fonts,
        'output': path,
      });
      return PreparedPdf(path: path, root: root);
    }
    final bytes = await compute(_assemblePdf, {
      'title': title,
      'pages': exportPages,
      'fonts': fonts,
    });
    if (bytes.length > 128 * 1024 * 1024) throw StateError('PDF oltre 128 MiB');
    return PreparedPdf(bytes: bytes);
  } catch (_) {
    if (root != null) await stage.disposePdfStaging(root);
    rethrow;
  }
}

/// PNG decoding, PDF image compression and final document encoding are CPU
/// work and must not block gesture/input frames. Only portable data crosses.
Future<Uint8List> _assemblePdf(Map<String, Object?> input) async {
  final pdf = pw.Document(
    title: input['title'] as String?,
    creator: AppBrand.name,
  );
  final fonts = {
    for (final entry in (input['fonts'] as Map<String, Uint8List>).entries)
      entry.key: pw.Font.ttf(ByteData.sublistView(entry.value)),
  };
  final images = <String, pw.MemoryImage>{};
  for (final entry in input['pages'] as List<Map<String, Object>>) {
    final width = (entry['width'] as num).toDouble(),
        height = (entry['height'] as num).toDouble();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(width, height, marginAll: 0),
        build: (context) {
          final item = stage.readPdfPage(entry);
          pw.MemoryImage image(Map<String, Object> part) {
            final bytes = part['png'] as Uint8List?;
            final key =
                part['imageKey'] as String? ??
                sha256.convert(bytes!).toString();
            return images.putIfAbsent(
              key,
              () => pw.MemoryImage(
                bytes ?? stage.readPdfImage(part['pngPath'] as String),
              ),
            );
          }

          return pw.Stack(
            children: [
              for (final part in item['parts'] as List<Map<String, Object>>)
                if (part['png'] != null || part['pngPath'] != null)
                  pw.Positioned(
                    left: (part['left'] as double?) ?? 0,
                    top: (part['top'] as double?) ?? 0,
                    child: pw.Image(
                      image(part),
                      width: (part['width'] as double?) ?? width,
                      height: (part['height'] as double?) ?? height,
                      fit: pw.BoxFit.fill,
                    ),
                  )
                else if (part['textLines'] != null)
                  pw.CustomPaint(
                    size: PdfPoint(width, height),
                    painter: (canvas, _) => _paintPdfText(
                      canvas,
                      part,
                      height,
                      fonts[part['font']]!.getFont(context),
                    ),
                  )
                else if (part['paper'] != null)
                  pw.CustomPaint(
                    size: PdfPoint(width, height),
                    painter: (canvas, _) =>
                        _paintPdfPaper(canvas, part, width, height),
                  )
                else
                  pw.CustomPaint(
                    size: PdfPoint(width, height),
                    painter: (canvas, _) =>
                        _paintPdfInk(canvas, part, width, height),
                  ),
            ],
          );
        },
      ),
    );
  }
  if (input['output'] is String) {
    final output = stage.DiskPdfStream(input['output'] as String);
    try {
      await pdf.write(output, enableEventLoopBalancing: true);
    } finally {
      output.close();
    }
    return Uint8List(0);
  }
  return pdf.save(enableEventLoopBalancing: true);
}

Future<Uint8List> _boundedPdfImage(Uint8List bytes, int pixels) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    if (w <= 0 || h <= 0 || w > 16384 || h > 16384 || w * h > 16 * 1024 * 1024)
      throw const FormatException('Immagine PDF oltre il limite');
    final scale = math.min(1.0, math.sqrt(pixels / (w * h)));
    var width = math.max(1, (w * scale).floor()),
        height = math.max(1, (h * scale).floor());
    if (width * height > pixels) {
      if (width >= height)
        width = math.max(1, pixels ~/ height);
      else
        height = math.max(1, pixels ~/ width);
    }
    codec = await descriptor.instantiateCodec(
      targetWidth: width,
      targetHeight: height,
    );
    image = (await codec.getNextFrame()).image;
    // Keep already bounded PNG bytes. Decoding one frame still validates
    // the payload; avoiding another PNG encoding saves CPU and allocations.
    final pngInput =
        bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71 &&
        bytes[4] == 13 &&
        bytes[5] == 10 &&
        bytes[6] == 26 &&
        bytes[7] == 10;
    if (w == width && h == height && pngInput) return bytes;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('Immagine PDF non disponibile');
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

String? _vectorFontAsset(XppText text) => switch (text.fontFamily ?? 'Sans') {
  'Sans' || 'sans-serif' || 'Roboto'
      when !kIsWeb && defaultTargetPlatform == TargetPlatform.android =>
    '/system/fonts/Roboto-Regular.ttf',
  'Open Sans' => 'fonts/Open Sans/OpenSans-Regular.ttf',
  'Inter' => 'fonts/Inter/Inter-Variable.ttf',
  'VT323' => 'fonts/VT323/VT323-Regular.ttf',
  _ => null,
};

Map<String, Object> _vectorText(XppText text, Size size, String asset) {
  final painter = TextPainter(
    text: TextSpan(
      text: text.text,
      style: TextStyle(
        fontFamily: text.fontFamily ?? 'Sans',
        fontSize: text.size ?? 12,
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  try {
    painter.layout(maxWidth: size.width);
    final lines = <Map<String, Object>>[];
    for (final line in painter.computeLineMetrics()) {
      final position = painter.getPositionForOffset(
        Offset(line.left, line.baseline - line.ascent / 2),
      );
      final range = painter.getLineBoundary(position);
      lines.add({
        'text': (text.text ?? '')
            .substring(range.start, range.end)
            .replaceAll('\n', '')
            .replaceAll('\r', ''),
        'x': (text.offset?.dx ?? 0) + line.left,
        'y': (text.offset?.dy ?? 0) + line.baseline,
      });
    }
    return {
      'textLines': lines,
      'font': asset,
      'size': text.size ?? 12,
      'color': (text.color ?? Colors.black).toARGB32(),
      'opacity': (text.color ?? Colors.black).a,
    };
  } finally {
    painter.dispose();
  }
}

void _paintPdfText(
  PdfGraphics canvas,
  Map<String, Object> part,
  double height,
  PdfFont font,
) {
  canvas.saveContext();
  canvas.setFillColor(PdfColor.fromInt(part['color'] as int));
  canvas.setGraphicState(PdfGraphicState(opacity: part['opacity'] as double));
  for (final line in part['textLines'] as List<Map<String, Object>>) {
    canvas.drawString(
      font,
      part['size'] as double,
      line['text'] as String,
      line['x'] as double,
      height - (line['y'] as double),
    );
  }
  canvas.restoreContext();
}

void _paintPdfPaper(
  PdfGraphics canvas,
  Map<String, Object> part,
  double width,
  double height,
) {
  canvas.saveContext();
  final paperColor = Color(part['color'] as int);
  canvas.setFillColor(PdfColor.fromInt(paperColor.toARGB32()));
  canvas.setGraphicState(PdfGraphicState(opacity: paperColor.a));
  canvas.drawRect(0, 0, width, height);
  canvas.fillPath();
  canvas.setGraphicState(const PdfGraphicState(opacity: 1));
  final kind = part['paper'] as String;
  void circle(double x, double y, double r) {
    canvas.drawEllipse(x, height - y, r, r);
    canvas.fillPath();
  }

  if (kind.startsWith('nothing')) {
    canvas.setFillColor(
      kind == 'nothingDark' ? PdfColors.white : PdfColors.black,
    );
    final alpha = kind == 'nothingDark' ? .18 : .22;
    for (double y = 16; y < height - 2; y += 16) {
      final margin = (y - 40).abs() < 8;
      canvas.setGraphicState(
        PdfGraphicState(opacity: margin ? alpha * 1.8 : alpha),
      );
      for (double x = 16; x < width - 2; x += 16) {
        circle(x, y, margin ? 1.1 : .8);
      }
    }
    canvas.setGraphicState(const PdfGraphicState(opacity: 1));
    canvas.setFillColor(PdfColor.fromInt(0xffd71921));
    circle(width - 24, 24, 3);
    canvas.setGraphicState(const PdfGraphicState(opacity: .55));
    canvas.setStrokeColor(PdfColor.fromInt(0xffd71921));
    canvas.setLineWidth(1);
    canvas.drawEllipse(width - 24, height - 24, 6, 6);
    canvas.strokePath();
  } else if (kind != 'plain') {
    canvas.setGraphicState(const PdfGraphicState(opacity: .3));
    canvas.setStrokeColor(PdfColor.fromInt(0xff9e9e9e));
    canvas.setFillColor(PdfColor.fromInt(0xff9e9e9e));
    canvas.setLineWidth(1);
    final spacing = kind == 'lines'
        ? 24.0
        : kind == 'graph'
        ? graphPaperSpacing
        : XppPageSize.pt2mm(5);
    for (double y = spacing; y < height; y += spacing) {
      if (kind == 'dot') {
        for (double x = spacing; x < width; x += spacing) {
          circle(x, y, XppPageSize.pt2mm(.5));
        }
      } else {
        canvas.drawLine(0, height - y, width, height - y);
        canvas.strokePath();
      }
    }
    if (kind == 'graph') {
      for (double x = spacing; x < width; x += spacing) {
        canvas.drawLine(x, 0, x, height);
        canvas.strokePath();
      }
    }
  }
  canvas.restoreContext();
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
  if (part['shape'] == true) {
    final closed =
        (samples.first[0] - samples.last[0]).abs() +
            (samples.first[1] - samples.last[1]).abs() <
        1;
    final points =
        closed &&
            samples.length > 1 &&
            math.sqrt(
                  math.pow(samples.first[0] - samples.last[0], 2) +
                      math.pow(samples.first[1] - samples.last[1], 2),
                ) <
                1
        ? samples.sublist(0, samples.length - 1)
        : samples;
    canvas.setStrokeColor(PdfColor.fromInt(part['color'] as int));
    canvas.setLineWidth(part['lineWidth'] as double);
    canvas.setLineCap(PdfLineCap.round);
    canvas.setLineJoin(PdfLineJoin.round);
    canvas.moveTo(points.first[0], height - points.first[1]);
    if (part['smooth'] == true && samples.length >= 4) {
      List<double> at(int i) =>
          points[closed ? i % points.length : i.clamp(0, points.length - 1)];
      for (var i = 0; i < (closed ? points.length : points.length - 1); i++) {
        final p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
        canvas.curveTo(
          p1[0] + (p2[0] - p0[0]) / 6,
          height - (p1[1] + (p2[1] - p0[1]) / 6),
          p2[0] - (p3[0] - p1[0]) / 6,
          height - (p2[1] - (p3[1] - p1[1]) / 6),
          p2[0],
          height - p2[1],
        );
      }
    } else {
      for (final p in samples.skip(1)) {
        canvas.lineTo(p[0], height - p[1]);
      }
    }
    if (closed) canvas.closePath();
    canvas.strokePath();
    canvas.restoreContext();
    return;
  }
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
  bool clipToPage = true,
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
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width > 16384 ||
          descriptor.height > 16384 ||
          descriptor.width * descriptor.height > 16 * 1024 * 1024)
        throw const FormatException('Dimensioni immagine oltre il limite');
      final imageCount =
          (backgroundBytes == null ? 0 : 1) +
          (page.layers
                  ?.where((l) => l.visible)
                  .expand((l) => l.content ?? <XppContent?>[])
                  .whereType<XppImage>()
                  .length ??
              0);
      final budget = math.max(1, pixelBudget ~/ math.max(1, imageCount));
      final shrink = math.min(
        1.0,
        math.sqrt(budget / (targetWidth * targetHeight)),
      );
      var width = math.max(1, (targetWidth * shrink).floor()),
          height = math.max(1, (targetHeight * shrink).floor());
      if (width * height > budget) {
        if (width >= height)
          width = math.max(1, budget ~/ height);
        else
          height = math.max(1, budget ~/ width);
      }
      codec = await descriptor.instantiateCodec(
        targetWidth: width,
        targetHeight: height,
      );
      final image = (await codec.getNextFrame()).image;
      images.add(image);
      return image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  void drawImage(ui.Image image, Rect destination) => canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    destination,
    Paint()..filterQuality = FilterQuality.high,
  );
  try {
    canvas.clipRect(clipToPage ? Offset.zero & size : area);
    if (paintBackground) {
      if (!clipToPage) {
        canvas.drawRect(
          area,
          Paint()
            ..color = page.background is XppBackgroundNothingDark
                ? const Color(0xff161616)
                : Colors.white,
        );
      }
      paintPaperBackground(canvas, size, page.background);
    }
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
