import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/HexColor.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPageContentWidget.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

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

  // --- VECCHIO METODO (Inattivo) ---
  @override
  XppPageContentWidget render() {
    return XppPageContentWidget(
      tool: EditingTool.TEXT,
      child: const SizedBox.shrink(), // Niente più TextField pesanti in background!
    );
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
    [XmlText(encodeText(text ?? ''))],
  );

  static String encodeText(String text) {
    return text
        .replaceAll(r'&', r'&amp;')
        .replaceAll(r'<', r'&lt;')
        .replaceAll(r'>', r'&gt;');
  }

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

// -----------------------------------------------------------------------------
// Ho mantenuto la vecchia classe RichTextField qui in fondo nel caso servisse
// ancora ad altri file dell'app, ma ora non viene più usata per il rendering!
// -----------------------------------------------------------------------------
class RichTextField extends StatefulWidget {
  final Function(String text)? onChange;
  final String? text;
  final double? size;
  final Color? color;

  const RichTextField({
    Key? key,
    this.onChange,
    this.text,
    this.size,
    this.color,
  }) : super(key: key);

  @override
  _RichTextFieldState createState() => _RichTextFieldState();
}

class _RichTextFieldState extends State<RichTextField> {
  TextEditingController? _controller;
  FocusNode? _focusNode;
  bool active = false;

  @override
  void initState() {
    _controller = TextEditingController(text: widget.text);
    _focusNode = FocusNode();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return XppPageContentWidget(
      child: TextField(controller: _controller, focusNode: _focusNode),
    );
  }
}
