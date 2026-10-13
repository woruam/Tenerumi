import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../layer_contents/XppImage.dart';

/// Crop in document coordinates, keeping the area outside the lasso transparent.
Future<XppImage?> cropPdfSelection(
  Uint8List raster,
  ui.Size pageSize,
  List<ui.Offset> polygon,
) async {
  if (polygon.length < 3 ||
      polygon.length > 20000 ||
      polygon.any((p) => !p.dx.isFinite || !p.dy.isFinite) ||
      pageSize.isEmpty ||
      !pageSize.width.isFinite ||
      !pageSize.height.isFinite) {
    return null;
  }
  final path = ui.Path()..addPolygon(polygon, true);
  final bounds = path.getBounds().intersect(ui.Offset.zero & pageSize);
  if (bounds.isEmpty || bounds.width < 0.1 || bounds.height < 0.1) return null;
  final codec = await ui.instantiateImageCodec(raster);
  ui.Image? source;
  ui.Image? cropped;
  ui.Picture? picture;
  try {
    source = (await codec.getNextFrame()).image;
    final scale = math.min(
      4.0,
      math.min(
        source.width / pageSize.width,
        math.min(
          source.height / pageSize.height,
          math.sqrt(4000000 / (bounds.width * bounds.height)),
        ),
      ),
    );
    final width = (bounds.width * scale).ceil().clamp(1, 4096);
    final height = (bounds.height * scale).ceil().clamp(1, 4096);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(width / bounds.width, height / bounds.height);
    canvas.translate(-bounds.left, -bounds.top);
    canvas.clipPath(path);
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Offset.zero & pageSize,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    picture = recorder.endRecording();
    cropped = await picture.toImage(width, height);
    final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return null;
    return XppImage(
      data: png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      topLeft: bounds.topLeft,
      bottomRight: bounds.bottomRight,
    );
  } finally {
    cropped?.dispose();
    picture?.dispose();
    source?.dispose();
    codec.dispose();
  }
}
