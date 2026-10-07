import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Render native math offscreen into a transparent PNG, for the canvas and XOPP.
Future<Map<String, dynamic>> renderPluginLatex(
  Map<String, dynamic> args,
) async {
  final source = args['text'];
  if (source is! String || source.isEmpty || source.length > 8192) {
    throw StateError('Formula vuota o troppo lunga');
  }
  final rawSize = args['size'] ?? 24;
  if (rawSize is! num || !rawSize.isFinite || rawSize < 8 || rawSize > 128) {
    throw StateError('size deve essere da 8 a 128');
  }
  final hex = args['color'] as String? ?? '#000000';
  if (!RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(hex)) {
    throw StateError('color richiede #RRGGBB');
  }
  final color = Color(0xff000000 | int.parse(hex.substring(1), radix: 16));
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final owner = PipelineOwner();
  final boundary = RenderRepaintBoundary();
  final root = RenderView(
    view: view,
    configuration: const ViewConfiguration(
      logicalConstraints: BoxConstraints.tightFor(width: 2048, height: 1024),
      physicalConstraints: BoxConstraints.tightFor(width: 2048, height: 1024),
      devicePixelRatio: 1,
    ),
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
  );
  owner.rootNode = root;
  root.prepareInitialFrame();
  final buildOwner = BuildOwner(focusManager: FocusManager());
  Object? failure;
  final element = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Math.tex(
          source,
          mathStyle: MathStyle.display,
          textStyle: TextStyle(fontSize: rawSize.toDouble(), color: color),
          onErrorFallback: (error) {
            failure = error;
            return const SizedBox();
          },
        ),
      ),
    ),
  ).attachToRenderTree(buildOwner);
  try {
    buildOwner.buildScope(element);
    buildOwner.finalizeTree();
    owner.flushLayout();
    owner.flushCompositingBits();
    owner.flushPaint();
    if (failure != null) {
      throw FormatException('Formula LaTeX non valida: $failure');
    }
    if (boundary.size.width >= 2048 || boundary.size.height >= 1024) {
      throw StateError('Formula troppo grande');
    }
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return {
        'base64': base64Encode(bytes!.buffer.asUint8List()),
        'width': boundary.size.width,
        'height': boundary.size.height,
      };
    } finally {
      image.dispose();
    }
  } finally {
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary)
        .attachToRenderTree(buildOwner, element);
    buildOwner.buildScope(element);
    buildOwner.finalizeTree();
    owner.rootNode = null;
    root.dispose();
    buildOwner.focusManager.dispose();
    owner.dispose();
  }
}
