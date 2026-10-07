import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/canvas_geometry_cache.dart';

import 'PointerListener.dart';
import 'ZoomableWidget.dart';

/// No scene-sized widget or texture: the surface always equals the viewport.
/// Content keeps absolute document coordinates, including negative positions.
class InfiniteCanvas extends StatefulWidget {
  final CanvasController canvas;
  final TransformationController transform;
  const InfiniteCanvas({
    super.key,
    required this.canvas,
    required this.transform,
  });
  @override
  State<InfiniteCanvas> createState() => _InfiniteCanvasState();
}

class _InfiniteCanvasState extends State<InfiniteCanvas> {
  final _touch = CanvasTouchSession();
  CanvasGeometryCache _geometry = CanvasGeometryCache();
  @override
  void didUpdateWidget(InfiniteCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.canvas != widget.canvas) _geometry = CanvasGeometryCache();
  }

  double _initialScale = 1;
  Offset _anchor = Offset.zero;
  void _zoom(double scale, Offset local, Offset world) {
    final z = scale.clamp(0.1, 10.0);
    widget.transform.value = Matrix4.identity()
      ..translate(local.dx - world.dx * z, local.dy - world.dy * z)
      ..scale(z);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (event.kind == PointerDeviceKind.touch) {
        _touch.pointers++;
        if (_touch.pointers == 2) _touch.cancellationEpoch++;
      }
    },
    onPointerUp: _endTouch,
    onPointerCancel: _endTouch,
    onPointerSignal: (event) {
      if (event is PointerScrollEvent) {
        GestureBinding.instance.pointerSignalResolver.register(event, (_) {
          _zoom(
            widget.transform.value.getMaxScaleOnAxis() *
                math.exp(-event.scrollDelta.dy / 500),
            event.localPosition,
            widget.transform.toScene(event.localPosition),
          );
        });
      }
    },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      },
      onScaleStart: (details) {
        _initialScale = widget.transform.value.getMaxScaleOnAxis();
        _anchor = widget.transform.toScene(details.localFocalPoint);
      },
      onScaleUpdate: (details) {
        if (widget.canvas.touchDrawingEnabled &&
            !widget.canvas.isPanEnabled &&
            details.pointerCount < 2) {
          return;
        }
        _zoom(_initialScale * details.scale, details.localFocalPoint, _anchor);
      },
      child: LayoutBuilder(
        builder: (context, constraints) => ClipRect(
          child: AnimatedBuilder(
            animation: widget.transform,
            builder: (context, _) {
              final ctrl = widget.canvas;
              final scale = widget.transform.value.getMaxScaleOnAxis();
              final origin = widget.transform.toScene(Offset.zero);
              final size = constraints.biggest / scale;
              return OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: size.width,
                maxWidth: size.width,
                minHeight: size.height,
                maxHeight: size.height,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: SizedBox.fromSize(
                    size: size,
                    child: CanvasTouchScope(
                      session: _touch,
                      child: PointerListener(
                        key: ObjectKey(ctrl.activeLayer(0)),
                        readOnly: !ctrl.canEditLayer(0),
                        canvasOrigin: origin,
                        toolData: ctrl.toolData,
                        translationMatrix: widget.transform.value,
                        strokeWidth: ctrl.getCurrentToolWidth(),
                        color: ctrl.getCurrentToolColor(),
                        highlighterWidth: ctrl.highlighterWidth,
                        highlighterColor: ctrl.highlighterColor,
                        eraserWidth: ctrl.eraserWidth,
                        shapeRecognition: ctrl.shapeRecognition,
                        buttonDownAction: ctrl.buttonDownAction,
                        buttonUpAction: ctrl.buttonUpAction,
                        clipboard: ctrl.clipboard,
                        onPasteContent: (p) => ctrl.pasteSelection(0, p),
                        getPageContent: () => ctrl.activeLayer(0).content ?? [],
                        onNewContent: (c) => ctrl.addNewContent(0, c),
                        onDeleteContent: (c) => ctrl.deleteContent(0, c),
                        onBeforeContentChanged: () => ctrl.saveSnapshot(0),
                        onContentChanged: () => ctrl.markContentChanged(0),
                        removeLastContent: () => ctrl.removeLastContent(0),
                        filterEraser:
                            ({coordinates, previousCoordinates, radius}) =>
                                ctrl.filterEraser(
                                  pageIndex: 0,
                                  coordinates: coordinates,
                                  previousCoordinates: previousCoordinates,
                                  radius: radius,
                                ),
                        onEraserStart: ctrl.beginEraserGesture,
                        onEraserEnd: ctrl.endEraserGesture,
                        onToolChanged: ctrl.setTool,
                        child: CustomPaint(
                          size: size,
                          painter: _InfinitePainter(ctrl, origin, _geometry),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  void _endTouch(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touch.pointers = math.max(0, _touch.pointers - 1);
    }
  }
}

class _InfinitePainter extends CustomPainter {
  final CanvasController controller;
  final Offset origin;
  final CanvasGeometryCache geometry;
  _InfinitePainter(this.controller, this.origin, this.geometry)
    : super(repaint: controller);
  @override
  void paint(Canvas canvas, Size size) {
    geometry.updateRevision(controller.pluginRevision);
    final page = controller.file!.pages!.first;
    final background = page.background;
    final dark = background is XppBackgroundNothingDark;
    canvas.drawColor(
      dark ? const Color(0xff161616) : Colors.white,
      BlendMode.src,
    );
    final grid = Paint()
      ..color = dark ? Colors.white12 : const Color(0xffdbe1ea)
      ..strokeWidth = 0.5;
    const spacing = 24.0;
    final startX = (-origin.dx) % spacing;
    final startY = (-origin.dy) % spacing;
    final dotted =
        background is XppBackgroundSolidDot ||
        background is XppBackgroundNothingLight ||
        dark;
    final ruled =
        background is XppBackgroundSolidLined ||
        background is XppBackgroundSolidRuled;
    if (dotted) {
      for (var x = startX; x < size.width; x += spacing) {
        for (var y = startY; y < size.height; y += spacing) {
          canvas.drawCircle(Offset(x, y), 0.8, grid);
        }
      }
    } else if (ruled || background is XppBackgroundSolidGraph) {
      for (var y = startY; y < size.height; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
      if (!ruled) {
        for (var x = startX; x < size.width; x += spacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
        }
      }
    }
    final viewport = (origin & size).inflate(64);
    canvas.save();
    canvas.translate(-origin.dx, -origin.dy);
    for (final layer in page.layers!) {
      if (!layer.visible) continue;
      for (final content in layer.content ?? []) {
        if (content == null) continue;
        final bounds = geometry.bounds(content);
        if (bounds != null && !viewport.overlaps(bounds)) continue;
        canvas.save();
        final offset = geometry.offset(content);
        if (offset != null) canvas.translate(offset.dx, offset.dy);
        content.paintToCanvas(canvas, size);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InfinitePainter oldDelegate) => true;
}
