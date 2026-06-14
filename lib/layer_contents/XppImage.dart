import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:flutter/material.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPageContentWidget.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

class XppImage extends XppContent {
  Offset? topLeft = Offset(0, 0);
  Offset? bottomRight = Offset(0, 0);

  @required
  final Uint8List? data;

  XppImage({this.data, this.topLeft, this.bottomRight});

  static Future<XppImage> open({required Offset topLeft}) async {
    FilePickerCross image =
        await FilePickerCross.importFromStorage(type: FileTypeCross.image);

    /// rendering the [Uint8List] into an image to determinate the height and width
    MemoryImage memoryImage = MemoryImage(image.toUint8List());
    final completer = Completer<ui.Image>();
    memoryImage.resolve(const ImageConfiguration()).addListener(
        ImageStreamListener(
            (ImageInfo info, bool _) => completer.complete(info.image)));
    final ui.Image renderedImage = await completer.future;
    Offset bottomRight = Offset(topLeft.dx + renderedImage.width.toDouble(),
        topLeft.dy + renderedImage.height.toDouble());
    return XppImage(
        data: image.toUint8List(), topLeft: topLeft, bottomRight: bottomRight);
  }

  @override
  XppPageContentWidget render() {
    return XppPageContentWidget(
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(),
          FadeInImage(
            image: MemoryImage(data!),
            placeholder: MemoryImage(kTransparentImage),
            width: bottomRight!.dx - topLeft!.dx,
            height: bottomRight!.dy - topLeft!.dy,
          )
        ],
      ),
      tool: EditingTool.IMAGE,
    );
  }

  @override
  Offset? getOffset() => topLeft;

  @override
  XmlElement toXmlElement() => XmlElement(XmlName('image'), [
        XmlAttribute(XmlName('left'), topLeft!.dx.toString()),
        XmlAttribute(XmlName('right'), bottomRight!.dx.toString()),
        XmlAttribute(XmlName('top'), topLeft!.dy.toString()),
        XmlAttribute(XmlName('bottom'), bottomRight!.dy.toString()),
      ], [
        XmlText(base64Encode(data!))
      ]);

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
