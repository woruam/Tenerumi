import 'package:flutter/material.dart';

import 'XppBackground.dart';
import 'XppPageSize.dart';

enum PaperTemplate {
  plain('Bianco'),
  lined('Righe'),
  ruled('Righe con margine'),
  graph('Quadretti'),
  dotted('Puntini'),
  smith('Carta di Smith'),
  nothingDark('Nothing Dark'),
  nothingLight('Nothing Light');

  const PaperTemplate(this.label);
  final String label;

  XppBackground build(XppPageSize size, {Color color = Colors.white}) =>
      switch (this) {
        plain => XppBackgroundSolidPlain(size: size, color: color),
        lined => XppBackgroundSolidLined(size: size, color: color),
        ruled => XppBackgroundSolidRuled(size: size, color: color),
        graph => XppBackgroundSolidGraph(size: size, color: color),
        dotted => XppBackgroundSolidDot(size: size, color: color),
        smith => XppBackgroundSmith(size: size, color: color),
        nothingDark => XppBackgroundNothingDark(size: size),
        nothingLight => XppBackgroundNothingLight(size: size),
      };

  static PaperTemplate fromBackground(XppBackground? background) =>
      switch (background) {
        XppBackgroundSolidLined() => lined,
        XppBackgroundSolidRuled() => ruled,
        XppBackgroundSolidGraph() => graph,
        XppBackgroundSolidDot() => dotted,
        XppBackgroundSmith() => smith,
        XppBackgroundNothingDark() => nothingDark,
        XppBackgroundNothingLight() => nothingLight,
        _ => plain,
      };
}

/// The creation paper remains stable when individual pages use another format.
class PaperSettings {
  final PaperTemplate template;
  final double width, height;
  final Color color;
  const PaperSettings({
    this.template = PaperTemplate.lined,
    this.width = 595.28,
    this.height = 841.89,
    this.color = Colors.white,
  });

  factory PaperSettings.fromBackground(
    XppBackground? background,
    XppPageSize? size,
  ) => PaperSettings(
    template: PaperTemplate.fromBackground(background),
    width: size?.width ?? 595.28,
    height: size?.height ?? 841.89,
    color: background is XppBackgroundSolid
        ? background.color ?? Colors.white
        : Colors.white,
  );

  XppPageSize get size => XppPageSize(width: width, height: height);
  XppBackground build() => template.build(size, color: color);
  Map<String, Object> toMap() => {
    'template': template.name,
    'width': width,
    'height': height,
    'color': color.toARGB32(),
  };

  static PaperSettings? fromMap(Object? value) {
    if (value is! Map) return null;
    final template = PaperTemplate.values
        .where((t) => t.name == value['template'])
        .firstOrNull;
    final width = value['width'],
        height = value['height'],
        color = value['color'];
    if (template == null ||
        width is! num ||
        height is! num ||
        color is! int ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        width > 20000 ||
        height > 20000 ||
        color < 0 ||
        color > 0xffffffff) {
      return null;
    }
    return PaperSettings(
      template: template,
      width: width.toDouble(),
      height: height.toDouble(),
      color: Color(color),
    );
  }
}
