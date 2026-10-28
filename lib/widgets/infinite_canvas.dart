import 'package:provider/provider.dart';
import 'package:xournalpp/controllers/theme_controller.dart';

import 'note_flashcards_panel.dart';

import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/src/decoded_image_cache.dart';

import 'audio_timeline_overlay.dart';

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/app_features.dart';
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
  CanvasScaleRecognizer? _recognizer;
  CanvasGeometryCache _geometry = CanvasGeometryCache();
  @override
  void initState() {
    super.initState();
    _touch.addListener(_resetInput);
  }

  void _resetInput() {
    _touchIds.clear();
    _gesturePointers = 0;
    _gesturePen = false;
    _pinched = false;
    _suppressed = true;
    _recognizer?.cancelActivePointers();
  }

  @override
  void dispose() {
    _touch.dispose();
    DecodedImageCache.shared.release(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(InfiniteCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.canvas != widget.canvas) _geometry = CanvasGeometryCache();
  }

  double _initialScale = 1, _gestureScale = 1;
  int _gesturePointers = 0;
  bool _pinched = false, _suppressed = false;
  bool _gesturePen = false;
  final Set<int> _touchIds = {};
  Offset _anchor = Offset.zero;
  void _zoom(double scale, Offset local, Offset world) {
    final z = scale.clamp(0.1, 10.0);
    widget.transform.value = Matrix4.identity()
      ..translate(local.dx - world.dx * z, local.dy - world.dy * z)
      ..scale(z);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    opaque: false,
    onEnter: (event) {
      _touch.enterProximity(event);
      _observePen(event);
    },
    onExit: _touch.leaveProximity,
    child: Listener(
      onPointerHover: _observePen,
      onPointerMove: _onPointerMove,
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.stylus ||
            event.kind == PointerDeviceKind.invertedStylus) {
          _touch.stylusPointers.add(event.pointer);
          _observePen(event);
        }
        if (event.kind == PointerDeviceKind.touch) {
          _touch.observeTouch(event);
          if (_touch.rejects(event) || _touchIds.length >= 2) {
            _touch.rejectedPointers.add(event.pointer);
            return;
          }
          if (_touchIds.isEmpty) {
            _pinched = false;
            _suppressed = false;
          }
          _touchIds.add(event.pointer);
          _touch.pointers = _touchIds.length;
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
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          CanvasScaleRecognizer:
              GestureRecognizerFactoryWithHandlers<CanvasScaleRecognizer>(
                () => CanvasScaleRecognizer(),
                (instance) {
                  _recognizer = instance;
                  instance.allow = (event) =>
                      (!CanvasTouchSession.isPen(event) ||
                          widget.canvas.isPanEnabled) &&
                      !_touch.rejects(event) &&
                      (event.kind != PointerDeviceKind.touch ||
                          _touchIds.length < 2 ||
                          _touchIds.contains(event.pointer));
                  instance.onStart = (details) {
                    _gesturePen =
                        widget.canvas.isPanEnabled &&
                        _touch.stylusPointers.isNotEmpty;
                    if (_gesturePen) _suppressed = false;
                    _initialScale = widget.transform.value.getMaxScaleOnAxis();
                    _gestureScale = 1;
                    _gesturePointers = details.pointerCount;
                    _pinched |= details.pointerCount >= 2;
                    _anchor = widget.transform.toScene(details.localFocalPoint);
                  };
                  instance.onUpdate = (details) {
                    if (_suppressed ||
                        _touch.stylusMenuActive ||
                        (_touch.penNear && !_gesturePen))
                      return;
                    if (details.pointerCount != _gesturePointers) {
                      _gesturePointers = details.pointerCount;
                      _pinched |= details.pointerCount >= 2;
                      _initialScale = widget.transform.value
                          .getMaxScaleOnAxis();
                      _gestureScale = details.scale;
                      _anchor = widget.transform.toScene(
                        details.localFocalPoint,
                      );
                      return;
                    }
                    if (_pinched && details.pointerCount < 2) return;
                    if (widget.canvas.touchDrawingEnabled &&
                        !widget.canvas.isPanEnabled &&
                        details.pointerCount < 2)
                      return;
                    _zoom(
                      _initialScale * details.scale / _gestureScale,
                      details.localFocalPoint,
                      _anchor,
                    );
                  };
                },
              ),
        },
        child: LayoutBuilder(
          builder: (context, constraints) => ClipRect(
            child: AnimatedBuilder(
              animation: widget.transform,
              builder: (context, _) {
                final ctrl = widget.canvas;
                final appearance = context.watch<ThemeController?>();
                final scale = widget.transform.value.getMaxScaleOnAxis();
                final origin = widget.transform.toScene(Offset.zero);
                final size = constraints.biggest / scale;
                final viewport = (origin & size).inflate(64);
                DecodedImageCache.shared.retain(this, [
                  for (final layer in ctrl.file!.pages!.first.layers!)
                    if (layer.visible) ...[
                      for (final image
                          in (layer.content ?? []).whereType<XppImage>())
                        if (image.data != null &&
                            image.bounds()?.overlaps(viewport) == true)
                          image.data!,
                    ],
                ]);
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
                          audio: ctrl.audio,
                          onListenAt: (p) => ctrl.listenAt(0, p),
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
                          penPressureEnabled: ctrl.penPressureEnabled,
                          stylusShortcuts:
                              appearance?.stylusShortcuts ??
                              ctrl.stylusShortcuts,
                          stylusMenuHoldDelay: Duration(
                            milliseconds:
                                appearance?.stylusMenuHoldDelayMs ?? 1100,
                          ),
                          onStylusShortcut: ctrl.applyStylusShortcut,
                          shapeRecognition: ctrl.shapeRecognition,
                          buttonDownAction: ctrl.buttonDownAction,
                          stylusProfile: ctrl.stylusProfile,
                          buttonUpAction: ctrl.buttonUpAction,
                          onFlashcardSelection: AppFeatures.plugins
                              ? (region) => captureFlashcardSelection(
                                  context,
                                  ctrl,
                                  0,
                                  region,
                                )
                              : null,
                          clipboard: ctrl.clipboard,
                          onPasteContent: (p) => ctrl.pasteSelection(0, p),
                          getPageContent: () =>
                              ctrl.activeLayer(0).content ?? [],
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
                          child: Stack(
                            children: [
                              CustomPaint(
                                size: size,
                                painter: _InfinitePainter(
                                  ctrl,
                                  origin,
                                  _geometry,
                                ),
                              ),
                              Positioned.fill(
                                child: AudioTimelineOverlay(
                                  page: ctrl.file!.pages![0],
                                  audio: ctrl.audio,
                                  origin: origin,
                                ),
                              ),
                            ],
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
    ),
  );
  void _observePen(PointerEvent event) {
    if (!CanvasTouchSession.isPen(event)) return;
    final hadTouches = _touchIds.isNotEmpty;
    _touch.observePen(event, _touchIds);
    _touchIds.clear();
    if (hadTouches || !_gesturePen) _suppressed = true;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (CanvasTouchSession.isPen(event)) {
      _observePen(event);
      return;
    }
    _touch.observeTouch(event);
    if (_touchIds.contains(event.pointer) && _touch.rejects(event)) {
      _suppressed = true;
      _recognizer?.cancelActivePointers();
    }
  }

  void _endTouch(PointerEvent event) {
    _touch.endPointer(event);
    _touchIds.remove(event.pointer);
    _touch.pointers = _touchIds.length;
    if (_touchIds.isEmpty && _touch.stylusPointers.isEmpty) _suppressed = false;
  }
}

class _InfinitePainter extends CustomPainter {
  final CanvasController controller;
  final Offset origin;
  final CanvasGeometryCache geometry;
  _InfinitePainter(this.controller, this.origin, this.geometry)
    : super(repaint: Listenable.merge([controller, DecodedImageCache.shared]));
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
    final spacing = background is XppBackgroundSolidGraph
        ? graphPaperSpacing
        : 24.0;
    final startX = (-origin.dx) % spacing;
    final startY = (-origin.dy) % spacing;
    final dotted =
        background is XppBackgroundSolidDot ||
        background is XppBackgroundNothingLight ||
        dark;
    final ruled =
        background is XppBackgroundSolidLined ||
        background is XppBackgroundSolidRuled;
    if (background is XppBackgroundSmith) {
      // A Smith chart is a finite reference diagram anchored at world (0, 0).
      // Pan moves the diagram with the ink instead of repeating its circles.
      canvas.save();
      canvas.translate(-origin.dx, -origin.dy);
      paintPaperBackground(canvas, page.pageSize!.toSize(), background);
      canvas.restore();
    } else if (dotted) {
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
