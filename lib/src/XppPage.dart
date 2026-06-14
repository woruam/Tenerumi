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

  static XppPage empty({Color? background, XppPageSize? pageSize}) {
    return XppPage(
      pageSize: pageSize ?? XppPageSize.a4,
      background: background != null 
          ? XppBackgroundSolidLined(size: pageSize ?? XppPageSize.a4, color: background) 
          : XppBackground.none,
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