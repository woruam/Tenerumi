import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/HexColor.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/editing_tool.dart';

class XppText extends XppContent {
  Color? color;
  double? size;
  String? text;
  Offset? offset;
  String? fontFamily;

  XppText({this.size, this.offset, this.fontFamily, this.color, this.text});

  @override
  Offset? getOffset() => offset;

  // --- NUOVO METODO AD ALTE PRESTAZIONI ---
  @override
  void paintToCanvas(Canvas canvas, Size size) {
    if (text == null || text!.isEmpty) return;

    // Definiamo lo stile del testo
    final textStyle = TextStyle(
      color: color ?? Colors.black,
      fontSize: this.size ?? 12.0,
      fontFamily: fontFamily ?? 'Sans',
    );

    // Creiamo uno span di testo
    final textSpan = TextSpan(text: text, style: textStyle);

    // Usiamo il pittore di testo di Flutter
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    // Calcola l'ingombro del testo (gli diamo lo spazio della pagina intera come limite)
    try {
      textPainter.layout(minWidth: 0, maxWidth: size.width);

      // Il MasterPainter ha già spostato l'origine (0,0) esattamente dove deve iniziare la scritta!
      textPainter.paint(canvas, const Offset(0, 0));
    } finally {
      textPainter.dispose();
    }
  }

  @override
  XmlElement toXmlElement() => XmlElement(
    XmlName('text'),
    [
      XmlAttribute(XmlName('font'), fontFamily ?? 'Sans'),
      XmlAttribute(XmlName('size'), this.size.toString()),
      XmlAttribute(XmlName('x'), offset!.dx.toString()),
      XmlAttribute(XmlName('y'), offset!.dy.toString()),
      XmlAttribute(XmlName('color'), color!.toHexTriplet()),
    ],
    // XmlText escapes XML characters when the element is serialized.
    [XmlText(text ?? '')],
  );

  @override
  Rect? bounds() {
    final fontSize = size ?? 12;
    // Questo è un calcolo approssimativo ereditato dal codice originale,
    // andrà benissimo per il rilevamento della selezione.
    final width = (text ?? '').length * fontSize * 0.6;
    return Rect.fromLTWH(offset!.dx, offset!.dy, width, fontSize * 1.4);
  }

  @override
  void translate(Offset delta) {
    offset = offset! + delta;
  }

  @override
  void scaleBy(double factor, Offset anchor) {
    offset = anchor + (offset! - anchor) * factor;
    size = (size ?? 12) * factor;
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
