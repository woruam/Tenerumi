import 'dart:typed_data';
import 'package:xournalpp/widgets/bounded_image.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart'; // <--- IMPORTANTE: aggiungi questo per FilePickerCross
import 'package:xournalpp/src/PdfImage.dart';
import 'package:xournalpp/src/XppPageSize.dart';

// Definizione unica
typedef Future<FilePickerCross> FileNotAvailableCallback(String? path);

abstract class XppBackground {
  XppBackgroundType? type;
  XppPageSize? size;
  Color? color; // Spostato qui per essere accessibile a tutti

  static XppBackground get none => _NoXppBackground();

  Widget render();
  XmlElement toXmlElement();
}

// Helper per convertire il colore in stringa per l'XML
String colorToString(Color color) {
  if (color == Colors.black) return "black";
  if (color == Colors.blue) return "blue";
  if (color == Colors.red) return "red";
  if (color == Colors.green) return "green";
  if (color == Colors.grey) return "grey";
  return "#${color.value.toRadixString(16).substring(2)}";
}

class PDfBackgroundWidget extends StatefulWidget {
  final XppBackgroundPdf provider;
  const PDfBackgroundWidget({Key? key, required this.provider})
    : super(key: key);
  @override
  _PDfBackgroundWidgetState createState() => _PDfBackgroundWidgetState();
}

class _PDfBackgroundWidgetState extends State<PDfBackgroundWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<Uint8List>(
      future: widget.provider
          .onUnavailable(widget.provider.filename)
          .then((value) => pdfImage(value, widget.provider.page)),
      builder: (context, snapshot) => (snapshot.hasData)
          ? Image.memory(snapshot.data!)
          : snapshot.hasError
          ? const Center(child: Text('Seleziona l’allegato di sfondo'))
          : const Center(child: CircularProgressIndicator()),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class XppBackgroundImage extends XppBackground {
  final String? filename;
  final Uint8List? data;
  final XppBackgroundImageDomain domain;
  XppBackgroundType? type = XppBackgroundType.PIXMAP;

  XppBackgroundImage({
    this.filename,
    this.data,
    this.domain = XppBackgroundImageDomain.ABSOLUTE,
  });

  @override
  Widget render() => data == null
      ? const SizedBox.shrink()
      : BoundedImage(data!, fit: BoxFit.fill);

  @override
  XmlElement toXmlElement() {
    return XmlElement(XmlName('background'), [
      XmlAttribute(XmlName('type'), 'pixmap'),
      XmlAttribute(XmlName('domain'), domain.name.toLowerCase()),
      XmlAttribute(XmlName('filename'), filename!),
    ]);
  }
}

class XppBackgroundPdf extends XppBackground {
  final String? filename;
  final int? page;
  final FileNotAvailableCallback onUnavailable;

  XppBackgroundPdf({required this.onUnavailable, this.page, this.filename});

  @override
  Widget render() => PDfBackgroundWidget(provider: this);

  @override
  XmlElement toXmlElement() {
    return XmlElement(XmlName('background'), [
      XmlAttribute(XmlName('type'), 'pdf'),
      XmlAttribute(XmlName('domain'), 'absolute'),
      XmlAttribute(XmlName('pageno'), ((page ?? 0) + 1).toString()),
      XmlAttribute(XmlName('filename'), filename!),
    ]);
  }
}

abstract class XppBackgroundSolid extends XppBackground {
  XppBackgroundSolid({Color? color, XppPageSize? size}) {
    this.color = color ?? Colors.white;
    this.size = size;
    this.type = XppBackgroundType.SOLID;
  }

  XmlElement generateXmlElement(String style) {
    return XmlElement(XmlName('background'), [
      XmlAttribute(XmlName('type'), 'solid'),
      XmlAttribute(XmlName('style'), style),
      XmlAttribute(
        XmlName('color'),
        color != null ? colorToString(color!) : 'black',
      ),
    ]);
  }
}

class XppBackgroundSolidLined extends XppBackgroundSolid {
  XppBackgroundSolidLined({super.color, super.size});
  @override
  Widget render() => Container(
    color: color,
    child: CustomPaint(
      painter: _LinePainter(color: color),
      size: size?.toSize() ?? Size.zero,
    ),
  );
  @override
  XmlElement toXmlElement() => generateXmlElement('lined');
}

class XppBackgroundSolidRuled extends XppBackgroundSolid {
  XppBackgroundSolidRuled({super.color, super.size});
  @override
  Widget render() => Container(
    color: color,
    child: CustomPaint(
      painter: _RuledPainter(color: color),
      size: size?.toSize() ?? Size.zero,
    ),
  );
  @override
  XmlElement toXmlElement() => generateXmlElement('ruled');
}

class XppBackgroundSolidGraph extends XppBackgroundSolid {
  XppBackgroundSolidGraph({super.color, super.size});
  @override
  Widget render() => Container(
    color: color,
    child: CustomPaint(
      painter: _GraphPainter(color: color),
      size: size?.toSize() ?? Size.zero,
    ),
  );
  @override
  XmlElement toXmlElement() => generateXmlElement('graph');
}

class XppBackgroundSolidDot extends XppBackgroundSolid {
  XppBackgroundSolidDot({super.color, super.size});
  @override
  Widget render() => Container(
    color: color,
    child: CustomPaint(
      painter: _DotPainter(color: color),
      size: size?.toSize() ?? Size.zero,
    ),
  );
  @override
  XmlElement toXmlElement() => generateXmlElement('dotted');
}

class XppBackgroundSolidPlain extends XppBackgroundSolid {
  XppBackgroundSolidPlain({super.color, super.size});
  @override
  Widget render() =>
      Container(width: size?.width, height: size?.height, color: color);
  @override
  XmlElement toXmlElement() => generateXmlElement('plain');
}

/// Template "Nothing" SCURO: foglio quasi nero con matrice di punti chiari e
/// il caratteristico punto rosso in alto a destra. Viene salvato nel file
/// .xopp come sfondo "dotted" con colore scuro, cosi' resta compatibile con
/// Xournal++ desktop.
class XppBackgroundNothingDark extends XppBackgroundSolid {
  XppBackgroundNothingDark({XppPageSize? size})
    : super(color: const Color(0xFF0A0A0A), size: size);
  @override
  Widget render() => Container(
    color: color,
    child: CustomPaint(
      painter: _NothingMatrixPainter(
        dotColor: Colors.white.withOpacity(0.18),
        accent: const Color(0xFFD71921),
      ),
      size: size?.toSize() ?? Size.zero,
    ),
  );
  @override
  XmlElement toXmlElement() => generateXmlElement('dotted');
}

/// Template "Nothing" CHIARO: foglio bianco caldo con matrice di punti scuri
/// e punto rosso d'accento. Salvato come sfondo "dotted" chiaro.
class XppBackgroundNothingLight extends XppBackgroundSolid {
  XppBackgroundNothingLight({XppPageSize? size})
    : super(color: const Color(0xFFF6F5F2), size: size);
  @override
  Widget render() => Container(
    color: color,
    child: CustomPaint(
      painter: _NothingMatrixPainter(
        dotColor: Colors.black.withOpacity(0.22),
        accent: const Color(0xFFD71921),
      ),
      size: size?.toSize() ?? Size.zero,
    ),
  );
  @override
  XmlElement toXmlElement() => generateXmlElement('dotted');
}

class _NoXppBackground extends XppBackground {
  @override
  Widget render() => Container();
  @override
  XmlElement toXmlElement() => XmlElement(XmlName('background'), [
    XmlAttribute(XmlName('type'), 'solid'),
    XmlAttribute(XmlName('color'), 'white'),
    XmlAttribute(XmlName('style'), 'plain'),
  ]);
}

/// Paints the same paper templates as the editor without mounting a page.
void paintPaperBackground(Canvas canvas, Size size, XppBackground? background) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = background?.color ?? Colors.white,
  );
  final CustomPainter? painter = switch (background) {
    XppBackgroundSolidLined() => _LinePainter(),
    XppBackgroundSolidRuled() => _RuledPainter(),
    XppBackgroundSolidGraph() => _GraphPainter(),
    XppBackgroundSolidDot() => _DotPainter(),
    XppBackgroundNothingDark() => _NothingMatrixPainter(
      dotColor: Colors.white.withValues(alpha: .18),
      accent: const Color(0xFFD71921),
    ),
    XppBackgroundNothingLight() => _NothingMatrixPainter(
      dotColor: Colors.black.withValues(alpha: .22),
      accent: const Color(0xFFD71921),
    ),
    _ => null,
  };
  painter?.paint(canvas, size);
}

// ... (lascia qui sotto tutti i tuoi Painter: _LinePainter, _RuledPainter, _GraphPainter, _DotPainter)

class _LinePainter extends CustomPainter {
  final Color? color;

  _LinePainter({this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[500]!.withOpacity(.3)
      ..strokeWidth = 1;
    // 1 because no line at the top
    final clip = _paperClip(canvas, size);
    for (
      int i = math.max(1, (clip.top / 24).floor());
      i < clip.bottom / 24;
      i++
    ) {
      canvas.drawLine(
        Offset(0, i * 24.toDouble()),
        Offset(size.width, i * 24.toDouble()),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _RuledPainter extends CustomPainter {
  final Color? color;

  _RuledPainter({this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[500]!.withOpacity(.3)
      ..strokeWidth = 1;
    // 1 because no line at the top
    final clip = _paperClip(canvas, size);
    for (
      int i = math.max(1, (clip.top / 24).floor());
      i < clip.bottom / 24;
      i++
    ) {
      canvas.drawLine(
        Offset(0, i * 24.toDouble()),
        Offset(size.width, i * 24.toDouble()),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _GraphPainter extends CustomPainter {
  final Color? color;

  _GraphPainter({this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[500]!.withOpacity(.3)
      ..strokeWidth = 1;
    // 1 because no line at the top
    final clip = _paperClip(canvas, size);
    for (
      int i = math.max(1, (clip.top / XppPageSize.pt2mm(5)).floor());
      i < clip.bottom / XppPageSize.pt2mm(5);
      i++
    ) {
      canvas.drawLine(
        Offset(0, i * XppPageSize.pt2mm(5).toDouble()),
        Offset(size.width, i * XppPageSize.pt2mm(5).toDouble()),
        paint,
      );
    }
    // 1 because no line at the beginning
    for (
      int i = math.max(1, (clip.left / XppPageSize.pt2mm(5)).floor());
      i < clip.right / XppPageSize.pt2mm(5);
      i++
    ) {
      canvas.drawLine(
        Offset(i * XppPageSize.pt2mm(5).toDouble(), 0),
        Offset(i * XppPageSize.pt2mm(5).toDouble(), size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _DotPainter extends CustomPainter {
  final Color? color;

  _DotPainter({this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[500]!.withOpacity(.3)
      ..strokeWidth = 1;
    // 1 because no line at the top
    final clip = _paperClip(canvas, size);
    final spacing = _paperSpacing(clip, XppPageSize.pt2mm(5));
    for (
      int i = math.max(1, (clip.top / spacing).floor());
      i < clip.bottom / spacing;
      i++
    ) {
      // 1 because no line at the beginning
      for (
        int j = math.max(1, (clip.left / spacing).floor());
        j < clip.right / spacing;
        j++
      ) {
        canvas.drawCircle(
          Offset(j * spacing, i * spacing),
          XppPageSize.pt2mm(.5).toDouble(),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

enum XppBackgroundImageDomain { ABSOLUTE, ATTACH, CLONE }

enum XppBackgroundType { NONE, SOLID, PIXMAP }

/// Pittore della matrice di punti in stile "Nothing OS": griglia regolare di
/// punti, riga di margine superiore leggermente accentuata e il punto rosso
/// firma in alto a destra (con un sottile anello attorno).
class _NothingMatrixPainter extends CustomPainter {
  final Color dotColor;
  final Color accent;

  _NothingMatrixPainter({required this.dotColor, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final clip = _paperClip(canvas, size);
    final spacing = _paperSpacing(clip, 16);
    const double marginY = 40.0; // riga di margine "di intestazione"

    final Paint dot = Paint()..color = dotColor;
    final Paint marginDot = Paint()
      ..color = dotColor.withOpacity((dotColor.opacity * 1.8).clamp(0.0, 1.0));

    for (
      double y = math.max(spacing, (clip.top / spacing).floor() * spacing);
      y < math.min(size.height - 2, clip.bottom);
      y += spacing
    ) {
      final bool isMarginRow = (y - marginY).abs() < spacing / 2;
      for (
        double x = math.max(spacing, (clip.left / spacing).floor() * spacing);
        x < math.min(size.width - 2, clip.right);
        x += spacing
      ) {
        canvas.drawCircle(
          Offset(x, y),
          isMarginRow ? 1.1 : 0.8,
          isMarginRow ? marginDot : dot,
        );
      }
    }

    // Punto rosso firma in alto a destra, con anello sottile.
    final Offset accentPos = Offset(size.width - spacing * 1.5, spacing * 1.5);
    canvas.drawCircle(accentPos, 3.0, Paint()..color = accent);
    canvas.drawCircle(
      accentPos,
      6.0,
      Paint()
        ..color = accent.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant _NothingMatrixPainter oldDelegate) =>
      oldDelegate.dotColor != dotColor || oldDelegate.accent != accent;
}

Rect _paperClip(Canvas canvas, Size size) {
  if (!size.width.isFinite || !size.height.isFinite || size.isEmpty) {
    return Rect.zero;
  }
  final clip = canvas.getLocalClipBounds().intersect(Offset.zero & size);
  return clip.isEmpty || !clip.isFinite ? Rect.zero : clip;
}

double _paperSpacing(Rect clip, double spacing) => math.max(
  spacing,
  math.sqrt(math.max(0, clip.width * clip.height) / 180000),
);
