import 'dart:async';

import 'package:xournalpp/controllers/note_audio_controller.dart';
import 'package:xournalpp/src/note_audio.dart';

import 'dart:math';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppTexImage.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/src/ShapeRecognizer.dart';
import 'package:xournalpp/src/ink_geometry.dart';
import 'package:xournalpp/src/selection_clipboard.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';

class PointerListener extends StatefulWidget {
  final NoteAudioController? audio;
  final void Function(Offset)? onListenAt;
  final void Function(Rect)? onFlashcardSelection;
  final bool readOnly;
  final Future<XppImage?> Function(List<Offset>)? onCopyPdfRegion;
  final Object? selectionIdentity;
  final Offset canvasOrigin;
  final Function(XppContent?)? onNewContent;
  final Function({int? device, PointerDeviceKind? kind})? onDeviceChange;
  final Widget? child;
  final Map<PointerDeviceKind?, EditingTool> toolData;
  final Matrix4? translationMatrix;
  final double? strokeWidth;
  final double? highlighterWidth;
  final Color? highlighterColor;
  final SelectionClipboard? clipboard;
  final List<XppContent> Function(Offset)? onPasteContent;
  final Color? color;
  final Function({
    Offset? coordinates,
    Offset? previousCoordinates,
    double? radius,
  })?
  filterEraser;
  final double? eraserWidth;
  final VoidCallback? onEraserStart;
  final VoidCallback? onEraserEnd;
  final Function()? removeLastContent;

  final String buttonDownAction;
  final String buttonUpAction;

  final bool shapeRecognition;
  final List<XppContent?> Function()? getPageContent;
  final Function(List<XppContent>)? onDeleteContent;
  final VoidCallback? onContentChanged;
  final VoidCallback? onBeforeContentChanged;
  final Function(EditingTool)? onToolChanged;

  const PointerListener({
    Key? key,
    this.readOnly = false,
    this.onCopyPdfRegion,
    this.selectionIdentity,
    this.audio,
    this.onListenAt,
    this.onFlashcardSelection,
    this.canvasOrigin = Offset.zero,
    this.onNewContent,
    this.child,
    this.toolData = const {},
    this.translationMatrix,
    this.onDeviceChange,
    this.strokeWidth,
    this.highlighterWidth,
    this.highlighterColor,
    this.clipboard,
    this.onPasteContent,
    this.color,
    this.filterEraser,
    this.eraserWidth,
    this.onEraserStart,
    this.onEraserEnd,
    this.removeLastContent,
    this.buttonDownAction = 'eraser',
    this.buttonUpAction = 'select',
    this.shapeRecognition = false,
    this.getPageContent,
    this.onDeleteContent,
    this.onContentChanged,
    this.onBeforeContentChanged,
    this.onToolChanged,
  }) : super(key: key);

  @override
  PointerListenerState createState() => PointerListenerState();
}

enum _SelectionDragMode { none, lasso, move, resize }

class PointerListenerState extends State<PointerListener> {
  Offset? _flashcardStart;
  Rect? _flashcardRect;
  Offset? _lastEraserPosition;

  void _eraseAt(PointerEvent event, {bool begin = false}) {
    if (begin) widget.onEraserStart?.call();
    final position = _canvasPoint(event);
    widget.filterEraser?.call(
      coordinates: position,
      previousCoordinates: begin ? null : _lastEraserPosition,
      radius: (widget.eraserWidth ?? widget.strokeWidth ?? 5) / 2,
    );
    _lastEraserPosition = position;
  }

  bool drawingEnabled = true;
  AudioInput? _audioInput;
  StrokeAudioLink? _audioLink;
  List<XppStrokePoint> points = [];
  final _InkPreview _inkPreview = _InkPreview();
  XppStrokeTool tool = XppStrokeTool.PEN;
  final Set<int> _touchPointers = {};
  int? _drawingPointer;
  bool _multipleTouches = false;
  int _touchEpoch = 0;
  bool poppedContentForCurrentPointer = false;

  List<Offset> _lassoPoints = [];
  List<Offset>? _pdfPolygon;
  int _selectionEpoch = 0;
  bool _copyingPdf = false;
  List<XppContent> _selectedContent = [];
  Rect? _selectionRect;
  _SelectionDragMode _dragMode = _SelectionDragMode.none;
  Offset? _lastDragPosition;
  bool _moveSelectionArmed = false;
  bool _selectionMutationStarted = false;
  Timer? _pasteHoldTimer;
  Offset? _holdScreenPosition;
  Offset? _pastePosition;
  bool _longPressConsumed = false;

  void _startPasteHold(PointerDownEvent event) {
    _pasteHoldTimer?.cancel();
    _longPressConsumed = false;
    if (widget.readOnly ||
        event.kind != PointerDeviceKind.stylus ||
        widget.toolData[event.kind] == EditingTool.FLASHCARD ||
        widget.clipboard?.hasContent != true ||
        widget.onPasteContent == null ||
        isEraser(event) ||
        isText(event) ||
        isLaTeX(event)) {
      return;
    }
    _holdScreenPosition = event.position;
    final position = _canvasPoint(event);
    _pasteHoldTimer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted || _drawingPointer != event.pointer) return;
      setState(() {
        _longPressConsumed = true;
        clearPoints();
        _lassoPoints.clear();
        _dragMode = _SelectionDragMode.none;
        _pastePosition = position;
      });
    });
  }

  void _clearSelection() {
    _selectionEpoch++;
    _pdfPolygon = null;
    _selectedContent.clear();
    _selectionRect = null;
    _moveSelectionArmed = false;
  }

  void _selectContent(List<XppContent> content) {
    Rect? bounds;
    for (final element in content) {
      final rect = element.bounds();
      if (rect == null) continue;
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    _selectedContent = content;
    _selectionRect = bounds?.inflate(4);
    _moveSelectionArmed = false;
  }

  void _beforeSelectionMutation() {
    if (_selectionMutationStarted) return;
    widget.onBeforeContentChanged?.call();
    _selectionMutationStarted = true;
  }

  /// Azione "fissa" (toggle): attivata dal click del tasto della penna in
  /// hover (stile Samsung Notes) o dal canale nativo (penne Redmi & simili).
  String? _activeOverrideAction;

  /// Azione "momentanea" (hold-to-use): attiva SOLO finche' il tasto laterale
  /// e' tenuto premuto mentre si scrive. Catturata all'inizio del tratto.
  String? _heldButtonAction;

  /// Stato dei tasti durante l'hover, per rilevare i fronti di salita.
  int _hoverButtons = 0;

  /// Strumento congelato per il tratto in corso: deciso al pointer-down, cosi'
  /// premere/rilasciare i tasti a meta' tratto non corrompe il disegno.
  XppStrokeTool? _strokeTool;

  static const platform = MethodChannel('online.xournal.mobile/pen');
  static final Set<PointerListenerState> _hardwareListeners = {};
  static PointerListenerState? _hardwareOwner;
  static MethodChannel? _hardwareChannel;

  static Future<void> _dispatchHardwareCall(MethodCall call) async {
    final owner = _hardwareOwner;
    if (owner == null || !owner.mounted) return;
    if (call.method == 'redmiPenPageDown') {
      owner._toggleOverride(owner.widget.buttonDownAction);
    } else if (call.method == 'redmiPenPageUp') {
      owner._toggleOverride(owner.widget.buttonUpAction);
    }
  }

  /// Mappa i bit dei tasti hardware sull'azione configurata.
  ///
  /// - kPrimaryStylusButton  (0x02): tasto laterale 1 della penna
  ///   (S Pen, penne per tavolette grafiche); coincide col tasto DESTRO del mouse.
  /// - kSecondaryStylusButton (0x04): tasto laterale 2 (penne a due tasti);
  ///   coincide col tasto CENTRALE del mouse.
  String? _actionFromButtons(int buttons) {
    if (buttons & kPrimaryStylusButton != 0) return widget.buttonDownAction;
    if (buttons & kSecondaryStylusButton != 0) return widget.buttonUpAction;
    return null;
  }

  /// L'azione effettiva: il tasto tenuto premuto vince sul toggle fisso.
  String? get _effectiveOverride => _heldButtonAction ?? _activeOverrideAction;

  void _toggleOverride(String action) {
    setState(() {
      _activeOverrideAction = (_activeOverrideAction == action) ? null : action;
      _notifyParentTool();
    });
  }

  /// Click del tasto della penna MENTRE SI E' IN HOVER (senza toccare lo
  /// schermo): commuta lo strumento in modo fisso, come su Samsung Notes.
  void _handleHoverButtons(PointerHoverEvent event) {
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      _hoverButtons = event.buttons;
      return;
    }
    _hardwareOwner = this;
    final int pressed = event.buttons & ~_hoverButtons; // fronti di salita
    if (pressed & kPrimaryStylusButton != 0) {
      _toggleOverride(widget.buttonDownAction);
    } else if (pressed & kSecondaryStylusButton != 0) {
      _toggleOverride(widget.buttonUpAction);
    }
    _hoverButtons = event.buttons;
  }

  @override
  void initState() {
    super.initState();
    if (_hardwareListeners.isEmpty) {
      _hardwareChannel = MethodChannel(
        platform.name,
        platform.codec,
        ServicesBinding.instance.defaultBinaryMessenger,
      );
      _hardwareChannel!.setMethodCallHandler(_dispatchHardwareCall);
    }
    _hardwareListeners.add(this);
  }

  @override
  void dispose() {
    _pasteHoldTimer?.cancel();
    _inkPreview.dispose();
    if (identical(_hardwareOwner, this)) _hardwareOwner = null;
    _hardwareListeners.remove(this);
    if (_hardwareListeners.isEmpty) {
      _hardwareChannel?.setMethodCallHandler(null);
      _hardwareChannel = null;
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PointerListener oldWidget) {
    if (oldWidget.selectionIdentity != widget.selectionIdentity) {
      _clearSelection();
      _lassoPoints.clear();
      _dragMode = _SelectionDragMode.none;
      _drawingPointer = null;
    }
    if (oldWidget.toolData != widget.toolData) {
      _flashcardStart = null;
      _flashcardRect = null;
      if (oldWidget.toolData[PointerDeviceKind.stylus] ==
          EditingTool.FLASHCARD) {
        _drawingPointer = null;
        _heldButtonAction = null;
        _strokeTool = null;
      }
    }
    if (widget.readOnly && !oldWidget.readOnly) {
      _pasteHoldTimer?.cancel();
      _pastePosition = null;
      _drawingPointer = null;
      clearPoints();
      _lassoPoints.clear();
      _clearSelection();
      _dragMode = _SelectionDragMode.none;
      widget.onEraserEnd?.call();
    }
    final content = widget.getPageContent?.call();
    if (content != null &&
        _selectedContent.any((item) => !content.contains(item))) {
      _clearSelection();
    }
    if (oldWidget.toolData != widget.toolData) {
      final currentStylusTool = widget.toolData[PointerDeviceKind.stylus];
      if ((_activeOverrideAction == 'eraser' &&
              currentStylusTool != EditingTool.ERASER) ||
          (_activeOverrideAction == 'highlighter' &&
              currentStylusTool != EditingTool.HIGHLIGHT) ||
          (_activeOverrideAction == 'select' &&
              currentStylusTool != EditingTool.SELECT)) {
        _activeOverrideAction = null;
      }
    }
    super.didUpdateWidget(oldWidget);
  }

  void _notifyParentTool() {
    if (widget.onToolChanged == null) return;
    switch (_activeOverrideAction) {
      case 'eraser':
        widget.onToolChanged!(EditingTool.ERASER);
        break;
      case 'highlighter':
        widget.onToolChanged!(EditingTool.HIGHLIGHT);
        break;
      case 'select':
        widget.onToolChanged!(EditingTool.SELECT);
        break;
      default:
        widget.onToolChanged!(EditingTool.STYLUS);
    }
  }

  Color _getToolColor(XppStrokeTool currentTool) {
    final color = currentTool == XppStrokeTool.HIGHLIGHTER
        ? widget.highlighterColor ?? widget.color
        : widget.color;
    return currentTool == XppStrokeTool.HIGHLIGHTER
        ? (color ?? Colors.black).withOpacity(0.5)
        : color ?? Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) {
        widget.onDeviceChange?.call(device: event.device, kind: event.kind);
        _handleHoverButtons(event);
      },
      opaque: false,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerMove: _onPointerMove,
            onPointerDown: _onPointerDown,
            onPointerUp: _onPointerUp,
            onPointerCancel: (data) {
              _pasteHoldTimer?.cancel();
              _touchPointers.remove(data.pointer);
              if (_touchPointers.isEmpty) _multipleTouches = false;
              if (_drawingPointer != data.pointer) return;
              if (_strokeTool == XppStrokeTool.ERASER) {
                widget.onEraserEnd?.call();
              }
              _drawingPointer = null;
              setState(() {
                _flashcardStart = null;
                _flashcardRect = null;
              });
              _longPressConsumed = false;
              clearPoints();
              _lassoPoints.clear();
              _dragMode = _SelectionDragMode.none;
              poppedContentForCurrentPointer = false;
              _heldButtonAction = null;
              _strokeTool = null;
            },
            onPointerSignal: (data) {
              setState(() {
                tool = getToolFromPointer(data);
              });
              widget.onDeviceChange?.call(device: data.device, kind: data.kind);
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                widget.child!,
                if (_flashcardRect != null)
                  Positioned.fromRect(
                    rect: _flashcardRect!.shift(-widget.canvasOrigin),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: .12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _ShapePreviewPainter(
                          origin: widget.canvasOrigin,
                          points: points,
                          preview: _inkPreview,
                          color: () => _getToolColor(tool),
                          tool: () =>
                              widget.toolData[PointerDeviceKind.stylus] ??
                              EditingTool.STYLUS,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_lassoPoints.length > 1)
                  CustomPaint(
                    foregroundPainter: _LassoPainter(
                      origin: widget.canvasOrigin,
                      points: _lassoPoints,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          if (_selectionRect != null) ..._buildSelectionOverlay(context),
          if (_pastePosition != null) _buildPasteMenu(context),
        ],
      ),
    );
  }

  List<Widget> _buildSelectionOverlay(BuildContext context) {
    final rect = _selectionRect!.shift(-widget.canvasOrigin);
    final color = Theme.of(context).colorScheme.primary;
    final pageSize = _canvasSize;
    final columns = (pageSize.width / 48).floor().clamp(1, 4);
    final barWidth = _pdfPolygon != null
        ? pageSize.width.clamp(48.0, 240.0)
        : columns * 48.0;
    final pdfActionWidth = min(192.0, barWidth);
    final barHeight = _pdfPolygon != null
        ? ((_selectedContent.isNotEmpty ? 1 : 0) +
                  ((pdfActionWidth + 48) / barWidth).ceil()) *
              48.0
        : (4 / columns).ceil() * 48.0;
    final preferredTop = rect.top >= barHeight + 8
        ? rect.top - barHeight - 8
        : rect.bottom + 8;
    final barPosition = _menuPosition(
      Offset(rect.left, preferredTop),
      Size(barWidth, barHeight),
    );

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
        left: barPosition.dx,
        top: barPosition.dy,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          elevation: 4,
          child: SizedBox(
            width: barWidth,
            child: Wrap(
              children: [
                if (_selectedContent.isNotEmpty && !widget.readOnly)
                  _CanvasActionButton(
                    actionKey: const ValueKey('selection-delete'),
                    icon: Icons.delete_outline,
                    label: 'Elimina',
                    onPressed: () {
                      widget.onDeleteContent?.call(List.of(_selectedContent));
                      setState(_clearSelection);
                    },
                  ),
                if (_selectedContent.isNotEmpty)
                  _CanvasActionButton(
                    actionKey: const ValueKey('selection-copy'),
                    icon: Icons.copy,
                    label: 'Copia',
                    onPressed: widget.clipboard == null
                        ? null
                        : () {
                            if (widget.clipboard!.copy(
                              _selectedContent,
                              audio:
                                  widget.audio?.document.recordings ?? const {},
                            )) {
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Selezione copiata. Tieni premuta la penna per incollare.',
                                  ),
                                ),
                              );
                            }
                          },
                  ),
                if (_pdfPolygon != null)
                  _CanvasActionButton(
                    actionKey: const ValueKey('selection-copy-pdf'),
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'Copia porzione PDF',
                    showLabel: true,
                    labelWidth: pdfActionWidth,
                    onPressed: _copyingPdf || widget.clipboard == null
                        ? null
                        : _copyPdfRegion,
                  ),
                if (_selectedContent.isNotEmpty && !widget.readOnly)
                  _CanvasActionButton(
                    actionKey: const ValueKey('selection-move'),
                    icon: Icons.open_with,
                    label: 'Sposta',
                    selected: _moveSelectionArmed,
                    onPressed: () => setState(() => _moveSelectionArmed = true),
                  ),
                _CanvasActionButton(
                  actionKey: const ValueKey('selection-done'),
                  icon: Icons.check,
                  label: 'Fine',
                  onPressed: () => setState(_clearSelection),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Size get _canvasSize {
    final renderBox = context.findRenderObject();
    return renderBox is RenderBox && renderBox.hasSize
        ? renderBox.size
        : const Size(595, 842);
  }

  Offset _menuPosition(Offset preferred, Size size) {
    final page = _canvasSize;
    return Offset(
      preferred.dx.clamp(0.0, max(0.0, page.width - size.width)),
      preferred.dy.clamp(0.0, max(0.0, page.height - size.height)),
    );
  }

  Widget _buildPasteMenu(BuildContext context) {
    // Keep the control the same size on screen at every page zoom.
    final box = context.findRenderObject() as RenderBox;
    final scale = box.getTransformTo(null).getMaxScaleOnAxis();
    final menuScale = scale.isFinite && scale > 0 ? scale : 1.0;
    final menuSize = Size(120 / menuScale, 48 / menuScale);
    final position = _menuPosition(
      _pastePosition! - widget.canvasOrigin,
      menuSize,
    );
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: menuSize.width,
      height: menuSize.height,
      child: FittedBox(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(20),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: _CanvasActionButton(
            actionKey: const ValueKey('selection-paste'),
            icon: Icons.content_paste,
            label: 'Incolla',
            showLabel: true,
            labelWidth: 120,
            onPressed: () {
              final pasted = widget.onPasteContent?.call(_pastePosition!) ?? [];
              setState(() {
                _pastePosition = null;
                if (pasted.isNotEmpty) {
                  _selectContent(pasted);
                  _moveSelectionArmed = true;
                }
              });
            },
          ),
        ),
      ),
    );
  }

  void _onPointerDown(PointerDownEvent data) {
    if (data.kind == PointerDeviceKind.touch &&
        ((CanvasTouchScope.of(context)?.rejects(data) ?? false) ||
            data.radiusMajor > 28))
      return;
    if (widget.readOnly &&
        (widget.onCopyPdfRegion == null || !isSelect(data))) {
      widget.onDeviceChange?.call(device: data.device, kind: data.kind);
      return;
    }
    _hardwareOwner = this;
    if (data.kind == PointerDeviceKind.touch) {
      final session = CanvasTouchScope.of(context);
      _touchEpoch = session?.cancellationEpoch ?? 0;
      _touchPointers.add(data.pointer);
      if (_touchPointers.length > 1) {
        _multipleTouches = true;
        setState(() {
          clearPoints();
          _lassoPoints.clear();
          _flashcardStart = null;
          _flashcardRect = null;
        });
        _drawingPointer = null;
      }
      if (_multipleTouches ||
          _drawingPointer != null ||
          (session?.pointers ?? 0) > 1 ||
          widget.toolData[data.kind] == null ||
          widget.toolData[data.kind] == EditingTool.MOVE)
        return;
    } else if (_drawingPointer != null) {
      return;
    }
    if (widget.audio?.listenMode == true) {
      if (data.kind != PointerDeviceKind.invertedStylus &&
          (data.buttons & (kPrimaryStylusButton | kSecondaryStylusButton)) == 0)
        widget.onListenAt?.call(_canvasPoint(data));
      return;
    }
    _drawingPointer = data.pointer;
    _selectionMutationStarted = false;
    if (_pastePosition != null) {
      setState(() => _pastePosition = null);
    }

    // HOLD-TO-USE (stile Samsung): se il tasto della penna e' PREMUTO nel
    // momento in cui la punta tocca lo schermo, per tutto il tratto vale
    // l'azione mappata su quel tasto (gomma/lazo/evidenziatore).
    _heldButtonAction = _actionFromButtons(data.buttons);
    _startPasteHold(data);
    if (widget.toolData[data.kind] == EditingTool.MOVE &&
        !_moveSelectionArmed) {
      _strokeTool = null;
      return;
    }

    final currentTool = getToolFromPointer(data);
    // Congela lo strumento per l'intero tratto: premere/rilasciare il tasto a
    // meta' tratto non deve cambiare strumento in corsa.
    _strokeTool = currentTool;
    tool = currentTool;
    widget.onDeviceChange?.call(device: data.device, kind: data.kind);

    if (widget.toolData[data.kind] == EditingTool.FLASHCARD && drawingEnabled) {
      _pasteHoldTimer?.cancel();
      setState(() {
        _flashcardStart = _canvasPoint(data);
        _flashcardRect = Rect.fromPoints(_flashcardStart!, _flashcardStart!);
        _selectedContent.clear();
        _selectionRect = null;
      });
      return;
    }

    if ((isSelect(data) || _moveSelectionArmed) && drawingEnabled) {
      final position = _canvasPoint(data);
      if (_selectionRect != null &&
          _selectedContent.isNotEmpty &&
          !widget.readOnly) {
        final handle = Rect.fromCircle(
          center: _selectionRect!.bottomRight,
          radius: 24,
        );
        if (!_moveSelectionArmed && handle.contains(position)) {
          _dragMode = _SelectionDragMode.resize;
        } else if (_moveSelectionArmed ||
            _selectionRect!.inflate(8).contains(position)) {
          _dragMode = _SelectionDragMode.move;
        } else {
          setState(() {
            _clearSelection();
            _lassoPoints = [position];
          });
          _dragMode = _SelectionDragMode.lasso;
        }
      } else {
        setState(() {
          _clearSelection();
          _lassoPoints = [position];
        });
        _dragMode = _SelectionDragMode.lasso;
      }
      _lastDragPosition = position;
      return;
    }

    if (currentTool == XppStrokeTool.ERASER) {
      _eraseAt(data, begin: true);
    } else if (isLaTeX(data)) {
      XppTexImage.edit(
            context: context,
            topLeft: _canvasPoint(data),
            color: widget.color,
          )
          .then((value) {
            widget.onNewContent!(value);
          })
          .catchError((e) {});
    } else if (isText(data)) {
      _editText(_canvasPoint(data));
    } else if (currentTool == XppStrokeTool.PEN ||
        currentTool == XppStrokeTool.HIGHLIGHTER) {
      _audioInput = widget.audio?.beginInput();
      _addDrawingPoint(data, currentTool);
    }
  }

  void _onPointerMove(PointerMoveEvent data) {
    if (data.kind == PointerDeviceKind.touch &&
        (CanvasTouchScope.of(context)?.cancellationEpoch ?? 0) != _touchEpoch) {
      clearPoints();
      _lassoPoints.clear();
      _flashcardStart = null;
      _flashcardRect = null;
      _drawingPointer = null;
      return;
    }
    if (_drawingPointer != data.pointer ||
        (data.kind == PointerDeviceKind.touch && _multipleTouches))
      return;
    if (_holdScreenPosition != null &&
        (data.position - _holdScreenPosition!).distance > kTouchSlop) {
      _pasteHoldTimer?.cancel();
    }
    if (_longPressConsumed) return;
    widget.onDeviceChange?.call(device: data.device, kind: data.kind);
    if (!drawingEnabled) return;

    if (_flashcardStart != null) {
      setState(
        () => _flashcardRect = Rect.fromPoints(
          _flashcardStart!,
          _canvasPoint(data),
        ),
      );
      return;
    }

    if (_dragMode != _SelectionDragMode.none) {
      final position = _canvasPoint(data);
      switch (_dragMode) {
        case _SelectionDragMode.lasso:
          setState(() => _lassoPoints.add(position));
          break;
        case _SelectionDragMode.move:
          _pdfPolygon = null;
          _selectionEpoch++;
          final delta = position - _lastDragPosition!;
          if (delta == Offset.zero) break;
          _pasteHoldTimer?.cancel();
          _beforeSelectionMutation();
          for (final content in _selectedContent) {
            content.translate(delta);
          }
          setState(() => _selectionRect = _selectionRect!.shift(delta));
          widget.onContentChanged?.call();
          _lastDragPosition = position;
          break;
        case _SelectionDragMode.resize:
          _pdfPolygon = null;
          _selectionEpoch++;
          final anchor = _selectionRect!.topLeft;
          final oldDistance = (_lastDragPosition! - anchor).distance;
          final newDistance = (position - anchor).distance;
          if (oldDistance > 5 && newDistance > 5) {
            final factor = newDistance / oldDistance;
            if (factor == 1) break;
            _pasteHoldTimer?.cancel();
            _beforeSelectionMutation();
            for (final content in _selectedContent) {
              content.scaleBy(factor, anchor);
            }
            setState(() {
              _selectionRect = Rect.fromLTWH(
                anchor.dx,
                anchor.dy,
                _selectionRect!.width * factor,
                _selectionRect!.height * factor,
              );
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

    if (widget.toolData[data.kind] == EditingTool.MOVE && _strokeTool == null) {
      return;
    }
    final currentTool = _strokeTool ?? getToolFromPointer(data);
    if (currentTool == XppStrokeTool.ERASER) {
      _eraseAt(data);
    } else if (currentTool == XppStrokeTool.HIGHLIGHTER ||
        currentTool == XppStrokeTool.PEN) {
      _addDrawingPoint(data, currentTool);
    }
  }

  void _onPointerUp(PointerUpEvent data) {
    if (data.kind == PointerDeviceKind.touch &&
        (CanvasTouchScope.of(context)?.cancellationEpoch ?? 0) != _touchEpoch) {
      clearPoints();
      _lassoPoints.clear();
      setState(() {
        _flashcardStart = null;
        _flashcardRect = null;
      });
      _drawingPointer = null;
    }
    if (data.kind == PointerDeviceKind.touch) {
      _touchPointers.remove(data.pointer);
      if (_touchPointers.isEmpty) _multipleTouches = false;
    }
    if (_drawingPointer != data.pointer) return;
    _pasteHoldTimer?.cancel();
    _drawingPointer = null;
    if (_flashcardStart != null) {
      final rect = Rect.fromPoints(_flashcardStart!, _canvasPoint(data));
      setState(() {
        _flashcardStart = null;
        _flashcardRect = null;
      });
      _heldButtonAction = null;
      _strokeTool = null;
      if (widget.toolData[data.kind] == EditingTool.FLASHCARD) {
        widget.onFlashcardSelection?.call(rect);
      }
      return;
    }
    if (_longPressConsumed) {
      _longPressConsumed = false;
      clearPoints();
      _heldButtonAction = null;
      _strokeTool = null;
      return;
    }

    if (_dragMode != _SelectionDragMode.none) {
      if (_dragMode == _SelectionDragMode.lasso) _finishLasso();
      _dragMode = _SelectionDragMode.none;
      _moveSelectionArmed = false;
      _heldButtonAction = null;
      _strokeTool = null;
      return;
    }

    if (widget.toolData[data.kind] == EditingTool.MOVE && _strokeTool == null) {
      _heldButtonAction = null;
      return;
    }
    final currentTool = _strokeTool ?? getToolFromPointer(data);
    if (!poppedContentForCurrentPointer &&
        currentTool != XppStrokeTool.ERASER) {
      _audioLink = widget.audio?.endInput(_audioInput, points.length);
      saveStroke(currentTool);
    }
    if (currentTool == XppStrokeTool.ERASER) {
      _eraseAt(data);
      // End after the final sample, independent of ancestor event ordering.
      widget.onEraserEnd?.call();
    }
    _lastEraserPosition = null;
    poppedContentForCurrentPointer = false;
    clearPoints();
    // Fine tratto: l'azione "hold-to-use" si spegne col rilascio della punta.
    _heldButtonAction = null;
    _strokeTool = null;
  }

  // Motore di Calcolo Avanzato della Pressione
  /// Converte l'evento puntatore in coordinate della TELA (foglio non scalato).
  ///
  /// Il PointerListener e' figlio dell'InteractiveViewer (zoom/pan) e del
  /// FittedBox (scala foglio->schermo): Flutter applica GIA' automaticamente
  /// l'inversa delle relative Matrix4, quindi `localPosition` e' gia' in
  /// coordinate-tela. Centralizziamo qui la conversione: e' l'unico punto da cui
  /// passano i punti prima del CustomPainter, ed e' indipendente per pannello
  /// (split-screen). NB: applicare qui un'altra Matrix4 inversa raddoppierebbe la
  /// trasformazione e ri-romperebbe l'allineamento in zoom-out.
  Offset _canvasPoint(PointerEvent data) =>
      data.localPosition + widget.canvasOrigin;

  void _addDrawingPoint(PointerEvent data, XppStrokeTool currentTool) {
    double baseWidth = currentTool == XppStrokeTool.HIGHLIGHTER
        ? widget.highlighterWidth ?? widget.strokeWidth ?? 15
        : widget.strokeWidth ?? 2.5;
    double pressure = data.pressure;

    // COMPATIBILITA' TAVOLETTE GRAFICHE: molte tavolette (Wacom, XP-Pen,
    // Huion collegate ad Android) riportano la pressione su un intervallo
    // diverso da 0..1. Normalizziamo usando pressureMin/pressureMax forniti
    // dal driver, cosi' la curva di spessore resta identica su ogni hardware.
    final double pMin = data.pressureMin;
    final double pMax = data.pressureMax;
    final bool isStylusKind =
        data.kind == PointerDeviceKind.stylus ||
        data.kind == PointerDeviceKind.invertedStylus;
    if (isStylusKind && pMax > pMin) {
      pressure = ((pressure - pMin) / (pMax - pMin)).clamp(0.0, 1.0);
    }

    // Sicurezza per dispositivi che non passano la pressione
    if (pressure <= 0.0 || !isStylusKind) {
      pressure = 0.5;
    }

    // Curva Esponenziale per lo spessore (la magia per la tua Redmi Pen)
    double multiplier = 0.1 + ((pressure * pressure) * 3.5);
    double dynamicThickness = baseWidth * multiplier;

    final minimumThickness = min(baseWidth, 0.5);
    if (dynamicThickness < minimumThickness) {
      dynamicThickness = minimumThickness;
    }

    if (currentTool == XppStrokeTool.HIGHLIGHTER) {
      dynamicThickness = baseWidth;
    }

    final point = XppStrokePoint(
      x: _canvasPoint(data).dx,
      y: _canvasPoint(data).dy,
      width: dynamicThickness,
    );
    points.add(point);
    widget.audio?.sampleInput(_audioInput);
    _inkPreview.append(
      point,
      pressureSensitive: currentTool == XppStrokeTool.PEN,
    );
  }

  void _finishLasso() {
    final lasso = List<Offset>.of(_lassoPoints);
    setState(() => _lassoPoints.clear());
    if (lasso.length < 3) return;

    final content = widget.readOnly
        ? <XppContent?>[]
        : widget.getPageContent?.call() ?? [];
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

    if (selected.isEmpty && widget.onCopyPdfRegion == null) {
      setState(() {
        _selectedContent.clear();
        _selectionRect = null;
      });
      return;
    }

    setState(() {
      _selectionEpoch++;
      _selectContent(selected);
      _pdfPolygon = widget.onCopyPdfRegion != null ? lasso : null;
      if (_pdfPolygon != null) {
        final bounds = (Path()..addPolygon(lasso, true)).getBounds();
        if (bounds.width >= 0.1 && bounds.height >= 0.1) {
          _selectionRect = _selectionRect?.expandToInclude(bounds) ?? bounds;
        } else {
          _pdfPolygon = null;
        }
      }
    });
  }

  Future<void> _copyPdfRegion() async {
    final polygon = _pdfPolygon;
    final copy = widget.onCopyPdfRegion;
    final clipboard = widget.clipboard;
    if (_copyingPdf || polygon == null || copy == null || clipboard == null)
      return;
    final epoch = _selectionEpoch;
    setState(() => _copyingPdf = true);
    try {
      final image = await copy(List.of(polygon));
      if (!mounted || epoch != _selectionEpoch || image == null) return;
      if (clipboard.copy([image])) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Porzione PDF copiata. Tieni premuta la penna per incollare.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted && epoch == _selectionEpoch) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Impossibile copiare la porzione PDF: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _copyingPdf = false);
    }
  }

  static bool _pointInPolygon(Offset point, List<Offset> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if ((polygon[i].dy > point.dy) != (polygon[j].dy > point.dy) &&
          point.dx <
              (polygon[j].dx - polygon[i].dx) *
                      (point.dy - polygon[i].dy) /
                      (polygon[j].dy - polygon[i].dy) +
                  polygon[i].dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  Future<void> _editText(Offset position) async {
    final controller = TextEditingController();
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Insert text'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
            decoration: const InputDecoration(border: OutlineInputBorder()),
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
      if (mounted && result == true && controller.text.trim().isNotEmpty) {
        widget.onNewContent!(
          XppText(
            text: controller.text,
            offset: position,
            color: widget.color,
            size: (widget.strokeWidth ?? 5) * 3,
            fontFamily: 'Sans',
          ),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  void clearPoints() {
    _audioInput = null;
    _audioLink = null;
    _lastEraserPosition = null;
    points.clear();
    _inkPreview.clear();
  }

  void _emitAudioStroke(XppStroke stroke) {
    final link = _audioLink;
    if (link != null) {
      stroke.audioLink =
          !stroke.isShape && link.samples.length == stroke.points!.length
          ? link
          : StrokeAudioLink(link.recordingId, link.startMs, link.endMs);
    }
    widget.onNewContent?.call(stroke);
  }

  void saveStroke(XppStrokeTool currentTool) {
    if (points.isNotEmpty) {
      var strokePoints = List<XppStrokePoint>.from(points);
      bool renderAsShape = false;
      bool renderSmooth = false;

      final currentStylusTool = widget.toolData[PointerDeviceKind.stylus];
      final isShapeTool =
          currentStylusTool == EditingTool.SHAPE_LINE ||
          currentStylusTool == EditingTool.SHAPE_RECT ||
          currentStylusTool == EditingTool.SHAPE_CIRCLE ||
          currentStylusTool == EditingTool.SHAPE_SQUARE ||
          currentStylusTool == EditingTool.SHAPE_DASHED_LINE ||
          currentStylusTool == EditingTool.SHAPE_CUBE ||
          currentStylusTool == EditingTool.SHAPE_CYLINDER ||
          currentStylusTool == EditingTool.SHAPE_SPHERE;

      if ((widget.shapeRecognition || isShapeTool) &&
          currentTool == XppStrokeTool.PEN) {
        List<XppStrokePoint>? recognized;

        if (isShapeTool) {
          final start = Offset(strokePoints.first.x!, strokePoints.first.y!);
          final end = Offset(strokePoints.last.x!, strokePoints.last.y!);
          final width =
              (strokePoints.first.width! + strokePoints.last.width!) / 2;

          if (currentStylusTool == EditingTool.SHAPE_DASHED_LINE) {
            _commitDashedLine(start, end, width, currentTool);
            return;
          }

          if (currentStylusTool == EditingTool.SHAPE_CUBE ||
              currentStylusTool == EditingTool.SHAPE_CYLINDER ||
              currentStylusTool == EditingTool.SHAPE_SPHERE) {
            _commit3DShape(currentStylusTool!, start, end, width, currentTool);
            return;
          }

          if (currentStylusTool == EditingTool.SHAPE_LINE) {
            recognized = [
              XppStrokePoint(x: start.dx, y: start.dy, width: width),
              XppStrokePoint(x: end.dx, y: end.dy, width: width),
            ];
          } else if (currentStylusTool == EditingTool.SHAPE_RECT ||
              currentStylusTool == EditingTool.SHAPE_SQUARE) {
            double left = min(start.dx, end.dx);
            double top = min(start.dy, end.dy);
            double right = max(start.dx, end.dx);
            double bottom = max(start.dy, end.dy);

            if (currentStylusTool == EditingTool.SHAPE_SQUARE) {
              double side = max(right - left, bottom - top);
              right = left + side;
              bottom = top + side;
            }

            recognized = [
              XppStrokePoint(x: left, y: top, width: width),
              XppStrokePoint(x: right, y: top, width: width),
              XppStrokePoint(x: right, y: bottom, width: width),
              XppStrokePoint(x: left, y: bottom, width: width),
              XppStrokePoint(x: left, y: top, width: width),
            ];
          } else if (currentStylusTool == EditingTool.SHAPE_CIRCLE) {
            renderSmooth = true; // cerchio = curva liscia
            final center = (start + end) / 2;
            final radius = (end - start).distance / 2;
            const segments = 64;
            recognized = List.generate(segments + 1, (i) {
              final angle = 2 * pi * i / segments;
              return XppStrokePoint(
                x: center.dx + radius * cos(angle),
                y: center.dy + radius * sin(angle),
                width: width,
              );
            });
          }
        } else {
          recognized = ShapeRecognizer.recognize(strokePoints);
        }

        if (recognized != null) {
          strokePoints = recognized;
          renderAsShape = true;
        }
      }
      _emitAudioStroke(
        XppStroke.byTool(
          tool: currentTool,
          points: strokePoints,
          color: _getToolColor(currentTool),
          isShape: renderAsShape,
          smooth: renderSmooth,
        ),
      );
    }
  }

  // Linea tratteggiata: emessa come serie di piccole linee solide (i trattini),
  // cosi' resta nel formato esistente e si salva/renderizza senza modifiche al painter.
  void _commitDashedLine(
    Offset start,
    Offset end,
    double width,
    XppStrokeTool currentTool,
  ) {
    final double total = (end - start).distance;
    if (total <= 0) return;
    final Offset dir = (end - start) / total;
    const double dashLen = 14.0;
    const double gapLen = 9.0;
    double d = 0;
    while (d < total) {
      final Offset a = start + dir * d;
      final Offset b =
          start + dir * (d + dashLen > total ? total : d + dashLen);
      _emitAudioStroke(
        XppStroke.byTool(
          tool: currentTool,
          points: [
            XppStrokePoint(x: a.dx, y: a.dy, width: width),
            XppStrokePoint(x: b.dx, y: b.dy, width: width),
          ],
          color: _getToolColor(currentTool),
          isShape: true,
        ),
      );
      d += dashLen + gapLen;
    }
  }

  // ----- Forme 3D: proiezioni vettoriali 2D (wireframe) dal box di trascinamento -----
  List<Offset> _ellipse(
    double cx,
    double cy,
    double rx,
    double ry, {
    int seg = 48,
  }) {
    return List.generate(seg + 1, (i) {
      final double ang = 2 * pi * i / seg;
      return Offset(cx + rx * cos(ang), cy + ry * sin(ang));
    });
  }

  void _emitPolyline(
    List<Offset> pts,
    double width,
    XppStrokeTool currentTool, {
    bool smooth = false,
  }) {
    if (pts.length < 2) return;
    _emitAudioStroke(
      XppStroke.byTool(
        tool: currentTool,
        points: pts
            .map((p) => XppStrokePoint(x: p.dx, y: p.dy, width: width))
            .toList(),
        color: _getToolColor(currentTool),
        isShape: true,
        smooth: smooth,
      ),
    );
  }

  void _commit3DShape(
    EditingTool tool,
    Offset start,
    Offset end,
    double width,
    XppStrokeTool currentTool,
  ) {
    final double left = min(start.dx, end.dx), top = min(start.dy, end.dy);
    final double right = max(start.dx, end.dx), bottom = max(start.dy, end.dy);
    final double w = right - left, h = bottom - top;
    if (w <= 0 || h <= 0) return;
    final double cx = (left + right) / 2, cy = (top + bottom) / 2;
    if (tool == EditingTool.SHAPE_CUBE) {
      final double depth = (w < h ? w : h) * 0.35;
      final Offset fTL = Offset(left, top + depth),
          fTR = Offset(right - depth, top + depth);
      final Offset fBR = Offset(right - depth, bottom),
          fBL = Offset(left, bottom);
      final Offset bTL = Offset(left + depth, top), bTR = Offset(right, top);
      final Offset bBR = Offset(right, bottom - depth),
          bBL = Offset(left + depth, bottom - depth);
      _emitPolyline([fTL, fTR, fBR, fBL, fTL], width, currentTool);
      _emitPolyline([bTL, bTR, bBR, bBL, bTL], width, currentTool);
      _emitPolyline([fTL, bTL], width, currentTool);
      _emitPolyline([fTR, bTR], width, currentTool);
      _emitPolyline([fBR, bBR], width, currentTool);
      _emitPolyline([fBL, bBL], width, currentTool);
    } else if (tool == EditingTool.SHAPE_CYLINDER) {
      final double rx = w / 2, ry = h * 0.12;
      _emitPolyline(
        _ellipse(cx, top + ry, rx, ry),
        width,
        currentTool,
        smooth: true,
      );
      _emitPolyline(
        _ellipse(cx, bottom - ry, rx, ry),
        width,
        currentTool,
        smooth: true,
      );
      _emitPolyline(
        [Offset(left, top + ry), Offset(left, bottom - ry)],
        width,
        currentTool,
      );
      _emitPolyline(
        [Offset(right, top + ry), Offset(right, bottom - ry)],
        width,
        currentTool,
      );
    } else if (tool == EditingTool.SHAPE_SPHERE) {
      final double r = (w < h ? w : h) / 2;
      _emitPolyline(_ellipse(cx, cy, r, r), width, currentTool, smooth: true);
      _emitPolyline(
        _ellipse(cx, cy, r, r * 0.3),
        width,
        currentTool,
        smooth: true,
      );
      _emitPolyline(
        _ellipse(cx, cy, r * 0.3, r),
        width,
        currentTool,
        smooth: true,
      );
    }
  }

  bool _isActionActive(String targetAction, PointerEvent data) {
    // Azione dai tasti tenuti premuti in questo istante (down/move)...
    final String? held = _heldButtonAction ?? _actionFromButtons(data.buttons);
    if (held == targetAction) return true;
    // ...oppure toggle fisso (click in hover / canale nativo Redmi).
    return _activeOverrideAction == targetAction;
  }

  bool isPen(PointerEvent data) {
    if (_effectiveOverride != null || _actionFromButtons(data.buttons) != null)
      return false;
    final hasKind = widget.toolData.containsKey(data.kind);
    final currentTool = widget.toolData[data.kind];
    return (hasKind &&
            (currentTool == EditingTool.STYLUS ||
                currentTool == EditingTool.SHAPE_LINE ||
                currentTool == EditingTool.SHAPE_RECT ||
                currentTool == EditingTool.SHAPE_CIRCLE ||
                currentTool == EditingTool.SHAPE_SQUARE ||
                currentTool == EditingTool.SHAPE_DASHED_LINE ||
                currentTool == EditingTool.SHAPE_CUBE ||
                currentTool == EditingTool.SHAPE_CYLINDER ||
                currentTool == EditingTool.SHAPE_SPHERE)) ||
        (!hasKind && data.kind == PointerDeviceKind.stylus);
  }

  bool isHighlighter(PointerEvent data) =>
      widget.toolData[data.kind] == EditingTool.HIGHLIGHT ||
      _isActionActive('highlighter', data);

  bool isEraser(PointerEvent data) {
    final hasKind = widget.toolData.containsKey(data.kind);
    return (hasKind && widget.toolData[data.kind] == EditingTool.ERASER) ||
        (!hasKind && data.kind == PointerDeviceKind.invertedStylus) ||
        _isActionActive('eraser', data);
  }

  bool isSelect(PointerEvent data) =>
      widget.toolData[data.kind] == EditingTool.SELECT ||
      _isActionActive('select', data);
  bool isText(PointerEvent data) =>
      widget.toolData[data.kind] == EditingTool.TEXT;
  bool isLaTeX(PointerEvent data) =>
      widget.toolData[data.kind] == EditingTool.LATEX;

  XppStrokeTool getToolFromPointer(PointerEvent data) {
    if (isEraser(data)) return XppStrokeTool.ERASER;
    if (isHighlighter(data)) return XppStrokeTool.HIGHLIGHTER;
    return XppStrokeTool.PEN;
  }
}

/// Canvas controls must also work when the ancestor recognizer claims stylus
/// gestures to prevent panning. Raw pen taps bypass that arena; touch/mouse
/// taps retain the normal recognizer and accessibility activation.
class _CanvasActionButton extends StatefulWidget {
  final Key actionKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final bool showLabel;
  final double labelWidth;

  const _CanvasActionButton({
    required this.actionKey,
    required this.icon,
    required this.label,
    this.onPressed,
    this.selected = false,
    this.showLabel = false,
    this.labelWidth = 160,
  });

  @override
  State<_CanvasActionButton> createState() => _CanvasActionButtonState();
}

class _CanvasActionButtonState extends State<_CanvasActionButton> {
  int? _penPointer;
  Offset? _origin;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      label: widget.label,
      enabled: enabled,
      selected: widget.selected,
      onTap: widget.onPressed,
      child: Tooltip(
        message: widget.label,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (!enabled ||
                (event.kind != PointerDeviceKind.stylus &&
                    event.kind != PointerDeviceKind.invertedStylus)) {
              return;
            }
            _penPointer = event.pointer;
            _origin = event.position;
          },
          onPointerMove: (event) {
            if (_penPointer == event.pointer &&
                (event.position - _origin!).distance > kTouchSlop) {
              _penPointer = null;
            }
          },
          onPointerUp: (event) {
            if (_penPointer != event.pointer) return;
            _penPointer = null;
            final box = context.findRenderObject() as RenderBox;
            if ((Offset.zero & box.size).contains(
              box.globalToLocal(event.position),
            )) {
              widget.onPressed?.call();
            }
          },
          onPointerCancel: (event) {
            if (_penPointer == event.pointer) _penPointer = null;
          },
          child: GestureDetector(
            excludeFromSemantics: true,
            supportedDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: SizedBox(
              key: widget.actionKey,
              width: widget.showLabel ? widget.labelWidth : 48,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.selected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.icon,
                      size: 20,
                      color: enabled ? null : Colors.grey,
                    ),
                    if (widget.showLabel) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.label,
                          style: Theme.of(context).textTheme.labelLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShapePreviewPainter extends CustomPainter {
  final Offset origin;
  final List<XppStrokePoint> points;
  final Color Function() color;
  final EditingTool Function() tool;
  final _InkPreview preview;

  _ShapePreviewPainter({
    this.origin = Offset.zero,
    required this.points,
    required this.color,
    required this.tool,
    required this.preview,
  }) : super(repaint: preview);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-origin.dx, -origin.dy);
    if (points.isEmpty) return;
    final tool = this.tool();

    final paint = Paint()
      ..color = color()
      ..strokeWidth = points.first.width ?? 2.5
      ..style = PaintingStyle.stroke;

    final start = Offset(points.first.x!, points.first.y!);
    final end = Offset(points.last.x!, points.last.y!);

    if (tool == EditingTool.SHAPE_LINE) {
      canvas.drawLine(start, end, paint);
    } else if (tool == EditingTool.SHAPE_RECT ||
        tool == EditingTool.SHAPE_SQUARE) {
      double left = min(start.dx, end.dx);
      double top = min(start.dy, end.dy);
      double right = max(start.dx, end.dx);
      double bottom = max(start.dy, end.dy);
      if (tool == EditingTool.SHAPE_SQUARE) {
        double side = max(right - left, bottom - top);
        right = left + side;
        bottom = top + side;
      }
      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), paint);
    } else if (tool == EditingTool.SHAPE_CIRCLE) {
      final center = (start + end) / 2;
      final radius = (end - start).distance / 2;
      canvas.drawCircle(center, radius, paint);
    } else if (tool == EditingTool.SHAPE_DASHED_LINE) {
      final double total = (end - start).distance;
      if (total > 0) {
        final Offset dir = (end - start) / total;
        double d = 0;
        while (d < total) {
          final Offset a = start + dir * d;
          final Offset b = start + dir * (d + 14.0 > total ? total : d + 14.0);
          canvas.drawLine(a, b, paint);
          d += 23.0;
        }
      }
    } else if (tool == EditingTool.SHAPE_CUBE) {
      final double left = min(start.dx, end.dx), top = min(start.dy, end.dy);
      final double right = max(start.dx, end.dx),
          bottom = max(start.dy, end.dy);
      final double depth =
          ((right - left) < (bottom - top) ? (right - left) : (bottom - top)) *
          0.35;
      final Offset fTL = Offset(left, top + depth),
          fTR = Offset(right - depth, top + depth),
          fBR = Offset(right - depth, bottom),
          fBL = Offset(left, bottom);
      final Offset bTL = Offset(left + depth, top),
          bTR = Offset(right, top),
          bBR = Offset(right, bottom - depth),
          bBL = Offset(left + depth, bottom - depth);
      final path = Path()
        ..addPolygon([fTL, fTR, fBR, fBL], true)
        ..addPolygon([bTL, bTR, bBR, bBL], true)
        ..moveTo(fTL.dx, fTL.dy)
        ..lineTo(bTL.dx, bTL.dy)
        ..moveTo(fTR.dx, fTR.dy)
        ..lineTo(bTR.dx, bTR.dy)
        ..moveTo(fBR.dx, fBR.dy)
        ..lineTo(bBR.dx, bBR.dy)
        ..moveTo(fBL.dx, fBL.dy)
        ..lineTo(bBL.dx, bBL.dy);
      canvas.drawPath(path, paint);
    } else if (tool == EditingTool.SHAPE_CYLINDER) {
      final double left = min(start.dx, end.dx), top = min(start.dy, end.dy);
      final double right = max(start.dx, end.dx),
          bottom = max(start.dy, end.dy);
      final double cx = (left + right) / 2,
          rx = (right - left) / 2,
          ry = (bottom - top) * 0.12;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, top + ry),
          width: rx * 2,
          height: ry * 2,
        ),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, bottom - ry),
          width: rx * 2,
          height: ry * 2,
        ),
        paint,
      );
      canvas.drawLine(Offset(left, top + ry), Offset(left, bottom - ry), paint);
      canvas.drawLine(
        Offset(right, top + ry),
        Offset(right, bottom - ry),
        paint,
      );
    } else if (tool == EditingTool.SHAPE_SPHERE) {
      final double left = min(start.dx, end.dx), top = min(start.dy, end.dy);
      final double right = max(start.dx, end.dx),
          bottom = max(start.dy, end.dy);
      final double cx = (left + right) / 2, cy = (top + bottom) / 2;
      final double r =
          ((right - left) < (bottom - top) ? (right - left) : (bottom - top)) /
          2;
      canvas.drawCircle(Offset(cx, cy), r, paint);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: r * 2, height: r * 0.6),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: r * 0.6, height: r * 2),
        paint,
      );
    } else {
      // Geometry is appended once per input sample, never rebuilt per frame.
      // A single fill prevents alpha buildup where highlighter segments overlap.
      canvas.drawPath(preview.path, paint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePreviewPainter oldDelegate) => true;
}

/// Live and committed ink use identical round geometry and every raw sample.
class _InkPreview extends ChangeNotifier {
  final InkGeometry _geometry = InkGeometry();
  Path get path => _geometry.path;

  void append(XppStrokePoint point, {required bool pressureSensitive}) {
    _geometry.append(
      point.offset,
      point.width,
      pressureSensitive: pressureSensitive,
    );
    // RenderCustomPaint schedules one paint per frame; samples are never dropped.
    notifyListeners();
  }

  void clear() {
    _geometry.clear();
    notifyListeners();
  }
}

class _LassoPainter extends CustomPainter {
  final Offset origin;
  final List<Offset> points;
  final Color color;

  _LassoPainter({
    required this.points,
    required this.color,
    this.origin = Offset.zero,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    canvas.translate(-origin.dx, -origin.dy);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      if (i.isEven) {
        path.moveTo(points[i].dx, points[i].dy);
      } else {
        path.lineTo(points[i].dx, points[i].dy);
      }
    }
    canvas.drawPath(path, paint);

    final fill = Paint()
      ..color = color.withOpacity(0.06)
      ..style = PaintingStyle.fill;
    final closed = Path()..addPolygon(points, true);
    canvas.drawPath(closed, fill);
  }

  @override
  bool shouldRepaint(covariant _LassoPainter oldDelegate) => true;
}
