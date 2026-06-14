import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppTexImage.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/ShapeRecognizer.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

class PointerListener extends StatefulWidget {
  final Function(XppContent?)? onNewContent;
  final Function({int? device, PointerDeviceKind? kind})? onDeviceChange;
  final Widget? child;
  final Map<PointerDeviceKind?, EditingTool> toolData;
  final Matrix4? translationMatrix;
  final double? strokeWidth;
  final Color? color;
  final Function({Offset? coordinates, double? radius})? filterEraser;
  final Function()? removeLastContent;
  
  // Le due azioni separate per i due tasti
  final String buttonDownAction;
  final String buttonUpAction;
  
  final bool shapeRecognition;
  final List<XppContent?> Function()? getPageContent;
  final Function(List<XppContent>)? onDeleteContent;
  final VoidCallback? onContentChanged;

  const PointerListener(
      {Key? key,
      this.onNewContent,
      this.child,
      this.toolData = const {},
      this.translationMatrix,
      this.onDeviceChange,
      this.strokeWidth,
      this.color,
      this.filterEraser,
      this.removeLastContent,
      this.buttonDownAction = 'eraser',
      this.buttonUpAction = 'select',
      this.shapeRecognition = false,
      this.getPageContent,
      this.onDeleteContent,
      this.onContentChanged})
      : super(key: key);

  @override
  PointerListenerState createState() => PointerListenerState();
}

enum _SelectionDragMode { none, lasso, move, resize }

class PointerListenerState extends State<PointerListener> {
  bool drawingEnabled = false;
  List<XppStrokePoint> points = [];
  XppStrokeTool tool = XppStrokeTool.PEN;
  Map<int, DateTime> pointerTimestamps = Map();
  bool poppedContentForCurrentPointer = false;

  List<Offset> _lassoPoints = [];
  List<XppContent> _selectedContent = [];
  Rect? _selectionRect;
  _SelectionDragMode _dragMode = _SelectionDragMode.none;
  Offset? _lastDragPosition;

  // --- GESTIONE AVANZATA DUE TASTI ---
  String? _activeOverrideAction; // null significa "Penna normale"
  static const platform = MethodChannel('online.xournal.mobile/pen');

  @override
  void initState() {
    super.initState();
    platform.setMethodCallHandler((call) async {
      setState(() {
        if (call.method == "redmiPenPageDown") {
          _activeOverrideAction = (_activeOverrideAction == widget.buttonDownAction) ? null : widget.buttonDownAction;
        } else if (call.method == "redmiPenPageUp") {
          _activeOverrideAction = (_activeOverrideAction == widget.buttonUpAction) ? null : widget.buttonUpAction;
        }
      });
    });
  }

  // Helper per ottenere il colore corretto in base al tool
  Color _getToolColor(XppStrokeTool currentTool) {
    if (widget.color == null) return Colors.black;
    // Se è l'evidenziatore, applichiamo un'opacità fissa (es. 50%)
    if (currentTool == XppStrokeTool.HIGHLIGHTER) {
      return widget.color!.withOpacity(0.5);
    }
    return widget.color!;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) {
        widget.onDeviceChange!(device: event.device, kind: event.kind);
      },
      opaque: false,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerMove: _onPointerMove,
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: (data) {
          points.clear();
          _lassoPoints.clear();
          _dragMode = _SelectionDragMode.none;
          poppedContentForCurrentPointer = false;
        },
        onPointerSignal: (data) {
          setState(() {
            tool = getToolFromPointer(data);
          });
          widget.onDeviceChange!(device: data.device, kind: data.kind);
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child!,
            if (points.length > 0)
              CustomPaint(
                foregroundPainter: XppStrokePainter(
                    points: points,
                    color: _getToolColor(tool), // <-- Colore con opacità se evidenziatore
                    topLeft: Offset(0, 0),
                    smoothPressure: tool == XppStrokeTool.PEN),
              ),
            if (_lassoPoints.length > 1)
              CustomPaint(
                foregroundPainter: _LassoPainter(
                    points: _lassoPoints,
                    color: Theme.of(context).colorScheme.primary),
              ),
            if (_selectionRect != null) ..._buildSelectionOverlay(context),
            
            // Ho rimosso il grande banner indicatore "_activeOverrideAction"
            // per evitare sovrapposizioni fastidiose con la UI pulita.
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSelectionOverlay(BuildContext context) {
    final rect = _selectionRect!;
    final color = Theme.of(context).colorScheme.primary;
    return [
      Positioned(
        left: rect.left,
        top: rect.top,
        child: IgnorePointer(
          child: Container(
            width: rect.width,
            height: rect.height,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 1.5),
              color: color.withOpacity(0.08),
            ),
          ),
        ),
      ),
      Positioned(
        left: rect.right - 8,
        top: rect.bottom - 8,
        child: IgnorePointer(
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ),
      Positioned(
        left: rect.left,
        top: (rect.top - 44) < 0 ? rect.bottom + 8 : rect.top - 44,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          elevation: 4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 20,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete selection',
                onPressed: () {
                  widget.onDeleteContent?.call(List.of(_selectedContent));
                  setState(() {
                    _selectedContent.clear();
                    _selectionRect = null;
                  });
                },
              ),
              IconButton(
                iconSize: 20,
                icon: const Icon(Icons.check),
                tooltip: 'Done',
                onPressed: () => setState(() {
                  _selectedContent.clear();
                  _selectionRect = null;
                }),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  void _onPointerDown(PointerDownEvent data) {
    if (_detectTwoFingerGesture(data, shouldPop: true)) return;

    setState(() {
      tool = getToolFromPointer(data);
    });
    widget.onDeviceChange!(device: data.device, kind: data.kind);

    if (isSelect(data) && drawingEnabled) {
      final position = data.localPosition;
      if (_selectionRect != null) {
        final barTop = (_selectionRect!.top - 44) < 0 ? _selectionRect!.bottom + 8 : _selectionRect!.top - 44;
        final actionBar = Rect.fromLTWH(_selectionRect!.left, barTop, 112, 40);
        if (actionBar.contains(position)) return;
        final handle = Rect.fromCircle(center: _selectionRect!.bottomRight, radius: 24);
        if (handle.contains(position)) {
          _dragMode = _SelectionDragMode.resize;
        } else if (_selectionRect!.inflate(8).contains(position)) {
          _dragMode = _SelectionDragMode.move;
        } else {
          setState(() {
            _selectedContent.clear();
            _selectionRect = null;
            _lassoPoints = [position];
          });
          _dragMode = _SelectionDragMode.lasso;
        }
      } else {
        setState(() => _lassoPoints = [position]);
        _dragMode = _SelectionDragMode.lasso;
      }
      _lastDragPosition = position;
      return;
    }

    if (isLaTeX(data)) {
      XppTexImage.edit(context: context, topLeft: data.localPosition, color: widget.color).then((value) {
        widget.onNewContent!(value);
      }).catchError((e) {});
    }
    if (isText(data)) {
      _editText(data.localPosition);
    }
  }

  void _onPointerMove(PointerMoveEvent data) {
    if (_detectTwoFingerGesture(data)) return;
    widget.onDeviceChange!(device: data.device, kind: data.kind);
    if (!drawingEnabled) return;

    if (isSelect(data)) {
      final position = data.localPosition;
      switch (_dragMode) {
        case _SelectionDragMode.lasso:
          setState(() => _lassoPoints.add(position));
          break;
        case _SelectionDragMode.move:
          final delta = position - _lastDragPosition!;
          for (final content in _selectedContent) {
            content.translate(delta);
          }
          setState(() => _selectionRect = _selectionRect!.shift(delta));
          widget.onContentChanged?.call();
          _lastDragPosition = position;
          break;
        case _SelectionDragMode.resize:
          final anchor = _selectionRect!.topLeft;
          final oldDistance = (_lastDragPosition! - anchor).distance;
          final newDistance = (position - anchor).distance;
          if (oldDistance > 5 && newDistance > 5) {
            final factor = newDistance / oldDistance;
            for (final content in _selectedContent) {
              content.scaleBy(factor, anchor);
            }
            setState(() {
              _selectionRect = Rect.fromLTWH(anchor.dx, anchor.dy, _selectionRect!.width * factor, _selectionRect!.height * factor);
            });
            widget.onContentChanged?.call();
          }
          _lastDragPosition = position;
          break;
        case _SelectionDragMode.none:
          break;
      }
      return;
    }

    if (isPen(data) || isHighlighter(data)) {
      double? width = (data.pressure == 0 ? widget.strokeWidth : data.pressure * widget.strokeWidth!);
      if (isHighlighter(data)) width = width! * 5;
      points.add(XppStrokePoint(x: data.localPosition.dx, y: data.localPosition.dy, width: width));
      setState(() {});
    }

    if (isEraser(data))
      widget.filterEraser!(coordinates: Offset(data.localPosition.dx, data.localPosition.dy), radius: widget.strokeWidth);
  }

  void _onPointerUp(PointerUpEvent data) {
    if (_dragMode != _SelectionDragMode.none) {
      if (_dragMode == _SelectionDragMode.lasso) _finishLasso();
      _dragMode = _SelectionDragMode.none;
      return;
    }
    if (!poppedContentForCurrentPointer) saveStroke(tool);
    poppedContentForCurrentPointer = false;
    points.clear();
  }

  void _finishLasso() {
    final lasso = List<Offset>.of(_lassoPoints);
    setState(() => _lassoPoints.clear());
    if (lasso.length < 3) return;
    final content = widget.getPageContent?.call() ?? [];
    final selected = <XppContent>[];
    for (final element in content) {
      if (element == null) continue;
      if (element is XppStroke) {
        final strokePoints = element.points ?? [];
        if (strokePoints.isEmpty) continue;
        int inside = 0;
        for (final p in strokePoints) {
          if (_pointInPolygon(p.offset, lasso)) inside++;
        }
        if (inside / strokePoints.length > 0.5) selected.add(element);
      } else {
        final bounds = element.bounds();
        if (bounds != null && _pointInPolygon(bounds.center, lasso)) {
          selected.add(element);
        }
      }
    }
    if (selected.isEmpty) {
      setState(() {
        _selectedContent.clear();
        _selectionRect = null;
      });
      return;
    }
    Rect? union;
    for (final element in selected) {
      final b = element.bounds();
      if (b == null) continue;
      union = union == null ? b : union.expandToInclude(b);
    }
    setState(() {
      _selectedContent = selected;
      _selectionRect = union?.inflate(4);
    });
  }

  static bool _pointInPolygon(Offset point, List<Offset> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if ((polygon[i].dy > point.dy) != (polygon[j].dy > point.dy) &&
          point.dx <
              (polygon[j].dx - polygon[i].dx) * (point.dy - polygon[i].dy) / (polygon[j].dy - polygon[i].dy) + polygon[i].dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  Future<void> _editText(Offset position) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Insert text'),
              content: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: null,
                  decoration: const InputDecoration(border: OutlineInputBorder())),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Okay')),
              ],
            ));
    if (result == true && controller.text.trim().isNotEmpty) {
      widget.onNewContent!(XppText(
          text: controller.text, offset: position, color: widget.color, size: (widget.strokeWidth ?? 5) * 3, fontFamily: 'Sans'));
    }
  }

  void clearPoints() {
    setState(() {
      points.clear();
    });
  }

  void saveStroke(XppStrokeTool tool) {
    if (points.isNotEmpty) {
      List<XppStrokePoint> strokePoints = List.from(points);
      if (widget.shapeRecognition && tool == XppStrokeTool.PEN) {
        final recognized = ShapeRecognizer.recognize(strokePoints);
        if (recognized != null) strokePoints = recognized;
      }
      // Passiamo il colore con l'opacità corretta se evidenziatore
      XppStroke stroke = XppStroke.byTool(tool: tool, points: strokePoints, color: _getToolColor(tool));
      widget.onNewContent!(stroke);
    }
  }

  // --- CONTROLLO STRUMENTI INTELLIGENTE ---
  bool _isActionActive(String targetAction, PointerEvent data) {
    if (data.kind == PointerDeviceKind.stylus && data.buttons == kSecondaryButton && widget.buttonDownAction == targetAction) return true;
    return _activeOverrideAction == targetAction;
  }

  bool isPen(PointerEvent data) {
    if (_activeOverrideAction != null) return false;

    return (widget.toolData.keys.contains(data.kind) && widget.toolData[data.kind] == EditingTool.STYLUS) ||
        (!widget.toolData.keys.contains(data.kind) && data.kind == PointerDeviceKind.stylus);
  }

  bool isHighlighter(PointerEvent data) {
    return (widget.toolData.keys.contains(data.kind) && widget.toolData[data.kind] == EditingTool.HIGHLIGHT) || 
           _isActionActive('highlighter', data);
  }

  bool isEraser(PointerEvent data) {
    return (widget.toolData.keys.contains(data.kind) && widget.toolData[data.kind] == EditingTool.ERASER) ||
        (!widget.toolData.keys.contains(data.kind) && data.kind == PointerDeviceKind.invertedStylus) || 
        _isActionActive('eraser', data);
  }

  bool isSelect(PointerEvent data) {
    return (widget.toolData.keys.contains(data.kind) && widget.toolData[data.kind] == EditingTool.SELECT) || 
           _isActionActive('select', data);
  }

  bool isText(PointerEvent data) {
    return (widget.toolData.keys.contains(data.kind) && widget.toolData[data.kind] == EditingTool.TEXT);
  }

  bool isLaTeX(PointerEvent data) {
    return (widget.toolData.keys.contains(data.kind) && widget.toolData[data.kind] == EditingTool.LATEX);
  }

  XppStrokeTool getToolFromPointer(PointerEvent data) {
    if (isHighlighter(data)) return XppStrokeTool.HIGHLIGHTER;
    if (isEraser(data)) return XppStrokeTool.ERASER;
    return XppStrokeTool.PEN;
  }

  bool _detectTwoFingerGesture(PointerEvent data, {bool shouldPop = false}) {
    final timestamp = DateTime.now();
    bool foundCloseOffset = false;
    pointerTimestamps.remove(data.device);
    pointerTimestamps.forEach((key, value) {
      if (value.difference(timestamp).inMilliseconds.abs() < 100) {
        foundCloseOffset = true;
      }
    });
    if (shouldPop && foundCloseOffset && !poppedContentForCurrentPointer) {
      poppedContentForCurrentPointer = true;
    }
    pointerTimestamps[data.device] = timestamp;
    return foundCloseOffset;
  }
}

class _LassoPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;

  _LassoPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()..color = color..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      if (i.isEven) { path.moveTo(points[i].dx, points[i].dy); } 
      else { path.lineTo(points[i].dx, points[i].dy); }
    }
    canvas.drawPath(path, paint);
    final fill = Paint()..color = color.withOpacity(0.06)..style = PaintingStyle.fill;
    final closed = Path()..addPolygon(points, true);
    canvas.drawPath(closed, fill);
  }
  @override
  bool shouldRepaint(covariant _LassoPainter oldDelegate) => true;
}