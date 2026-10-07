import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

import 'XppPageContentWidget.dart';

class XppLayer {
  XppLayer({
    this.content,
    this.name = 'Livello',
    this.visible = true,
    this.locked = false,
  });

  String name;
  bool visible;
  bool locked;

  List<XppContent?>? content;

  static XppLayer empty() => XppLayer(content: []);

  XmlElement toXmlElement() => XmlElement(XmlName('layer'), [
    XmlAttribute(XmlName('name'), name),
    XmlAttribute(XmlName('osipp-visible'), visible.toString()),
    XmlAttribute(XmlName('osipp-locked'), locked.toString()),
  ], (content ?? []).whereType<XppContent>().map((e) => e.toXmlElement()));
}

abstract class XppContent {
  Offset? getOffset();

  // VECCHIO METODO: Lo teniamo temporaneamente per non far esplodere tutto subito,
  // ma lo elimineremo alla fine.
  XppPageContentWidget render();

  // NUOVO METODO: Il futuro dell'app.
  // Ogni elemento (testo, immagine, tratto) dovrà saper disegnare se stesso su questa tela.
  void paintToCanvas(Canvas canvas, Size size);

  XmlElement toXmlElement();

  bool shouldSelectAt({Offset? coordinates, EditingTool? tool});

  bool inRegion({Offset? topLeft, Offset? bottomRight});

  Rect? bounds() => null;

  void translate(Offset delta) {}

  void scaleBy(double factor, Offset anchor) {}

  XppContentEraseData eraseWhere({Offset? coordinates, double? radius}) =>
      XppContentEraseData();
}

class XppContentEraseData {
  final bool affected;
  final bool delete;
  final List<XppContent> newContent;

  XppContentEraseData({
    this.affected = false,
    this.delete = false,
    this.newContent = const [],
  });
}
