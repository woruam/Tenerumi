import 'package:xournalpp/src/decoded_image_cache.dart';

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

class XppImage extends XppContent {
  Offset? topLeft = const Offset(0, 0);
  Offset? bottomRight = const Offset(0, 0);

  @required
  final Uint8List? data;

  // --- VARIABILI INTERNE PER IL CANVAS ---

  XppImage({this.data, this.topLeft, this.bottomRight});

  static Future<XppImage> open({required Offset topLeft}) async {
    FilePickerCross image = await FilePickerCross.importFromStorage(
      type: FileTypeCross.image,
    );

    final buffer = await ui.ImmutableBuffer.fromUint8List(image.toUint8List());
    ui.ImageDescriptor? descriptor;
    late final Offset bottomRight;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      bottomRight =
          topLeft +
          Offset(descriptor.width.toDouble(), descriptor.height.toDouble());
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
    return XppImage(
      data: image.toUint8List(),
      topLeft: topLeft,
      bottomRight: bottomRight,
    );
  }

  // --- NUOVO METODO AD ALTE PRESTAZIONI ---
  @override
  void paintToCanvas(Canvas canvas, Size size) {
    if (data == null || topLeft == null || bottomRight == null) return;

    // Poiché il MasterPainter ha già spostato l'origine del Canvas su 'topLeft',
    // disegniamo partendo da 0,0 fino alla larghezza/altezza dell'immagine.
    final double width = bottomRight!.dx - topLeft!.dx;
    final double height = bottomRight!.dy - topLeft!.dy;
    final Rect destRect = Rect.fromLTWH(0, 0, width, height);

    final decodedImage = DecodedImageCache.shared.lookup(data!);
    if (decodedImage != null) {
      // L'immagine è decodificata e pronta in RAM: la "stampiamo" alla massima velocità GPU
      final Rect srcRect = Rect.fromLTWH(
        0,
        0,
        decodedImage.width.toDouble(),
        decodedImage.height.toDouble(),
      );
      canvas.drawImageRect(decodedImage, srcRect, destRect, Paint());
    } else {
      // Disegna un placeholder grigio per far capire che sta caricando
      canvas.drawRect(destRect, Paint()..color = Colors.grey.withOpacity(0.2));
    }
  }

  @override
  Offset? getOffset() => topLeft;

  @override
  XmlElement toXmlElement() => XmlElement(
    XmlName('image'),
    [
      XmlAttribute(XmlName('left'), topLeft!.dx.toString()),
      XmlAttribute(XmlName('right'), bottomRight!.dx.toString()),
      XmlAttribute(XmlName('top'), topLeft!.dy.toString()),
      XmlAttribute(XmlName('bottom'), bottomRight!.dy.toString()),
    ],
    [XmlText(base64Encode(data!))],
  );

  @override
  Rect? bounds() => Rect.fromPoints(topLeft!, bottomRight!);

  @override
  void translate(Offset delta) {
    topLeft = topLeft! + delta;
    bottomRight = bottomRight! + delta;
  }

  @override
  void scaleBy(double factor, Offset anchor) {
    topLeft = anchor + (topLeft! - anchor) * factor;
    bottomRight = anchor + (bottomRight! - anchor) * factor;
  }

  @override
  bool inRegion({Offset? topLeft, Offset? bottomRight}) {
    final rect = Rect.fromPoints(topLeft!, bottomRight!);
    return rect.overlaps(bounds()!);
  }

  @override
  bool shouldSelectAt({Offset? coordinates, EditingTool? tool}) {
    if (coordinates == null) return false;
    return bounds()!.inflate(8).contains(coordinates);
  }
}
