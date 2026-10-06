import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// Importiamo le VERE classi dal loro file originale (che ha paintToCanvas)
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';

class XppPageStack extends StatefulWidget {
  final XppPage? page;
  final bool renderPdfBackground;

  const XppPageStack({Key? key, this.page, this.renderPdfBackground = true})
      : super(key: key);

  @override
  XppPageStackState createState() => XppPageStackState();
}

class XppPageStackState extends State<XppPageStack>
    with AutomaticKeepAliveClientMixin {
  GlobalKey pngKey = GlobalKey();
  XppPage? page;

  XppBackground? _lastKnownBackground;
  Widget background = Container();

  @override
  void initState() {
    page = widget.page;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    List<Widget> children = [];

    if (page!.background != null && _lastKnownBackground != page!.background) {
      _lastKnownBackground = page!.background;
      // Il RepaintBoundary per lo sfondo
      background =
          page!.background is XppBackgroundPdf && !widget.renderPdfBackground
              ? const SizedBox.shrink()
              : RepaintBoundary(child: page!.background!.render());
    }
    children.add(background);

    // Iteriamo sui layer passando anche le dimensioni della pagina al nuovo pittore
    if (page!.layers != null) {
      children.addAll(page!.layers!.map((e) => XppLayerStack(
            layer: e,
            pageSize: Size(page!.pageSize!.width, page!.pageSize!.height),
          )));
    }

    return RepaintBoundary(
        key: pngKey,
        child: SizedBox(
            width: page!.pageSize!.width,
            height: page!.pageSize!.height,
            child: Stack(children: children)));
  }

  void setPageData(XppPage pageData) {
    setState(() => page = pageData);
  }

  Future<Uint8List> toPng() async {
    RenderRepaintBoundary boundary =
        pngKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage();
    try {
      ByteData byteData = await (image.toByteData(
          format: ui.ImageByteFormat.png) as FutureOr<ByteData>);
      Uint8List pngBytes = byteData.buffer.asUint8List();
      return pngBytes;
    } finally {
      image.dispose();
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant XppPageStack oldWidget) {
    setState(() {});
    super.didUpdateWidget(oldWidget);
  }
}

// ---------------------------------------------------------
// NUOVA ARCHITETTURA: Il pittore Master per i contenuti
// ---------------------------------------------------------

class XppLayerStack extends StatelessWidget {
  final XppLayer? layer;
  final Size pageSize;

  const XppLayerStack({Key? key, this.layer, required this.pageSize})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (layer == null || layer!.content == null) return const SizedBox();

    return RepaintBoundary(
      child: CustomPaint(
        painter: XppMasterPainter(layerContents: layer!.content!),
        size: pageSize,
      ),
    );
  }
}

class XppMasterPainter extends CustomPainter {
  final List<XppContent?> layerContents;

  XppMasterPainter({required this.layerContents});

  @override
  void paint(Canvas canvas, Size size) {
    for (var element in layerContents) {
      if (element != null) {
        canvas.save();

        final offset = element.getOffset();
        if (offset != null) {
          canvas.translate(offset.dx, offset.dy);
        }

        element.paintToCanvas(canvas, size);

        canvas.restore();
      }
    }
  }

  // --- ECCO LA MODIFICA ---
  @override
  bool shouldRepaint(covariant XppMasterPainter oldDelegate) {
    // Ora si aggiornerà sempre non appena la gomma "mangia" un pezzo di inchiostro!
    return true;
  }
}
