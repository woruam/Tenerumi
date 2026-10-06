import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'XppLayer.dart';

class XppPage {
  XppPageSize? pageSize;
  XppBackground? background;
  List<XppLayer>? layers;

  XppPage({this.pageSize, this.background, this.layers});

  static XppPage empty(
      {Color? background, XppPageSize? pageSize, XppBackground? template}) {
    final XppPageSize size = pageSize ?? XppPageSize.a4;
    // [template] ha la precedenza: permette di creare pagine con un modello
    // preciso (righe, quadretti, puntini, Nothing scuro/chiaro...).
    XppBackground? resolved = template;
    if (resolved != null) resolved.size ??= size;
    resolved ??= background != null
        ? XppBackgroundSolidLined(size: size, color: background)
        : XppBackground.none;
    return XppPage(
      pageSize: size,
      background: resolved,
      layers: [XppLayer.empty()],
    );
  }

  XmlElement toXmlElement() {
    return XmlElement(XmlName('page'), [
      XmlAttribute(XmlName('width'), (pageSize?.width ?? 595.28).toString()),
      XmlAttribute(XmlName('height'), (pageSize?.height ?? 841.89).toString()),
    ], [
      if (background != null && background != XppBackground.none)
        background!.toXmlElement(),
      ...layers!.map((layer) => layer.toXmlElement())
    ]);
  }
}
