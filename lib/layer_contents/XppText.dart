import 'package:flutter/cupertino.dart';
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

  @override
  XppPageContentWidget render() {
    return XppPageContentWidget(
      child: RichTextField(),
      tool: EditingTool.TEXT,
    );
  }

  @override
  XmlElement toXmlElement() => XmlElement(XmlName('text'), [
        XmlAttribute(XmlName('font'), fontFamily!),
        XmlAttribute(XmlName('size'), size.toString()),
        XmlAttribute(XmlName('x'), offset!.dx.toString()),
        XmlAttribute(XmlName('y'), offset!.dy.toString()),
        XmlAttribute(XmlName('color'), color!.toHexTriplet()),
      ], [
        XmlText(encodeText(text!))
      ]);

  static String encodeText(String text) {
    return text
        .replaceAll(r'&', r'&amp;')
        .replaceAll(r'<', r'&lt;')
        .replaceAll(r'>', r'&gt;');
  }

  @override
  Rect? bounds() {
    final fontSize = size ?? 12;
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

class RichTextField extends StatefulWidget {
  final Function(String text)? onChange;

  final String? text;

  final double? size;

  final Color? color;

  const RichTextField(
      {Key? key, this.onChange, this.text, this.size, this.color})
      : super(key: key);

  @override
  _RichTextFieldState createState() => _RichTextFieldState();
}

class _RichTextFieldState extends State<RichTextField> {
  //ZefyrController _controller;
  TextEditingController? _controller;
  FocusNode? _focusNode;

  bool active = false;

  @override
  void initState() {
    _controller = TextEditingController(text: widget.text);
    //_controller = ZefyrController(
    //   NotusDocument.fromDelta(NotusMarkdownCodec().decode(widget.text)));
    _focusNode = FocusNode();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return XppPageContentWidget(
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
      ),
    );
    /*return ZefyrEditor(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      mode: active ? ZefyrMode.edit : ZefyrMode.select,
    );*/
  }

  /*@override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }*/
}
