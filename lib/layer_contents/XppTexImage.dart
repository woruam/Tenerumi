import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/HexColor.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPageContentWidget.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

class XppTexImage extends XppContent {
  Offset? topLeft = const Offset(0, 0);

  /// TODO: proper implementation of bottom and right
  Offset? bottomRight = const Offset(0, 0);

  final String? text;

  Color? color;

  XppTexImage({this.text, this.topLeft, this.bottomRight, this.color});

  static Future<XppTexImage> edit({
    required BuildContext context,
    String text = 'x^2',
    Offset? topLeft,
    Color? color,
  }) async {
    var laTeXController = TextEditingController(text: text);
    bool? result = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter LaTeX code'),
        content: TextField(
          controller: laTeXController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'LaTeX code',
            helperText: 'No delimiter required',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Okay'),
          ),
        ],
      ),
    );
    final editedText = laTeXController.text;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => laTeXController.dispose(),
    );
    if (result != true) throw (UnsupportedError('Aborted.'));
    return (XppTexImage(text: editedText, topLeft: topLeft, color: color));
  }

  // --- NUOVO METODO AD ALTE PRESTAZIONI ---
  @override
  void paintToCanvas(Canvas canvas, Size size) {
    if (text == null || text!.isEmpty) return;

    // Ricreiamo lo stile "math-like" del vecchio render
    final textStyle = TextStyle(
      color: color ?? Colors.black,
      fontSize: 18,
      fontStyle: FontStyle.italic,
      fontFamily: 'serif',
    );

    final textSpan = TextSpan(text: text, style: textStyle);

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    // Diciamo al testo di calcolare il suo ingombro senza limiti di larghezza
    try {
      textPainter.layout();

      // Disegniamo sul canvas all'origine (il MasterPainter ha già spostato le coordinate corrette)
      textPainter.paint(canvas, const Offset(0, 0));
    } finally {
      textPainter.dispose();
    }
  }

  // --- VECCHIO METODO (Inattivo) ---
  @override
  XppPageContentWidget render() {
    return XppPageContentWidget(
      tool: EditingTool.LATEX,
      child: const SizedBox.shrink(),
    );
  }

  @override
  Offset? getOffset() => topLeft;

  @override
  Rect? bounds() {
    final width = (bottomRight!.dx > topLeft!.dx)
        ? bottomRight!.dx - topLeft!.dx
        : (text ?? '').length * 10.0;
    final height = (bottomRight!.dy > topLeft!.dy)
        ? bottomRight!.dy - topLeft!.dy
        : 24.0;
    return Rect.fromLTWH(topLeft!.dx, topLeft!.dy, width, height);
  }

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
  XmlElement toXmlElement() => XmlElement(
    XmlName('teximage'),
    [
      XmlAttribute(XmlName('text'), text!),
      XmlAttribute(XmlName('color'), color!.toHexTriplet()),
      XmlAttribute(XmlName('left'), topLeft!.dx.toString()),
      XmlAttribute(XmlName('right'), bottomRight?.dx.toString() ?? '0'),
      XmlAttribute(XmlName('top'), topLeft!.dy.toString()),
      XmlAttribute(XmlName('bottom'), bottomRight?.dy.toString() ?? '0'),
    ],
    [XmlText(XppText.encodeText(text!))],
  );

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
