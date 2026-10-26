import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Shared across page listeners so a pinch spanning two pages never adds ink.
/// Notifications request a hard input reset; ordinary input is read in callbacks.
class CanvasTouchSession extends ChangeNotifier with WidgetsBindingObserver {
  static const double palmRadiusThreshold = 28;
  CanvasTouchSession() {
    _awaitingHover = _nativeHoverEnded;
    _lastHoverExit = _lastNativeHoverExit;
    _sessions.add(this);
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_observeRemoval);
  }
  static final Set<CanvasTouchSession> _sessions = {};
  static bool _nativeHoverEnded = false;
  static Duration? _lastNativeHoverExit;
  static Duration? _lastRealHover;
  static void nativeProximityExit(int? timestampMicros) {
    final exit = timestampMicros == null
        ? null
        : Duration(microseconds: timestampMicros);
    _nativeHoverEnded =
        exit == null || _lastRealHover == null || exit >= _lastRealHover!;
    if (exit == null) _lastRealHover = null;
    if (exit == null ||
        _lastNativeHoverExit == null ||
        exit > _lastNativeHoverExit!) {
      _lastNativeHoverExit = exit;
    }
    for (final session in List.of(_sessions)) {
      if (exit != null &&
          session._lastRealHoverTime != null &&
          exit < session._lastRealHoverTime!)
        continue;
      session._hoverDevices.clear();
      session._awaitingHover = true;
      session._lastHoverExit = _lastNativeHoverExit;
    }
  }

  static void resetAll() {
    _resetNativeProximity();
    for (final session in List.of(_sessions)) {
      session.reset();
    }
  }

  static void _resetNativeProximity() {
    _nativeHoverEnded = true;
    _lastRealHover = null;
  }

  int pointers = 0;
  int cancellationEpoch = 0;
  final Set<int> stylusPointers = {};
  final Set<int> rejectedPointers = {};
  final Set<int> _cancelledGestureContacts = {};
  Timer? _postContactTimer;
  bool _postContactGrace = false;
  final Set<int> _hoverDevices = {};
  final Map<int, int> _stylusDevices = {};
  Duration? _lastHoverExit;
  Duration? _lastRealHoverTime;
  bool _awaitingHover = false;
  bool get penNear =>
      _postContactGrace ||
      _hoverDevices.isNotEmpty ||
      stylusPointers.isNotEmpty;
  void enterProximity(PointerEnterEvent event) {
    if (isPen(event) && !_awaitingHover && !_oldHover(event)) {
      _hoverDevices.add(event.device);
    }
  }

  void leaveProximity(PointerExitEvent event) {
    _hoverDevices.remove(event.device);
  }

  static bool isPen(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;
  void observePen(PointerEvent event, Iterable<int> touches) {
    if (!isPen(event)) return;
    if (event is PointerEnterEvent && _awaitingHover ||
        (event is PointerHoverEvent || event is PointerEnterEvent) &&
            _oldHover(event))
      return;
    if (event is PointerHoverEvent) {
      _nativeHoverEnded = false;
      _lastRealHoverTime = event.timeStamp;
      if (_lastRealHover == null || event.timeStamp > _lastRealHover!) {
        _lastRealHover = event.timeStamp;
      }
      _awaitingHover = false;
      _hoverDevices.add(event.device);
    }
    // Contact replaces the hover grant. Some Android pens never send a hover
    // exit after lifting from the screen; that old grant must not survive.
    if (event is PointerDownEvent) {
      stylusPointers.add(event.pointer);
      _hoverDevices.remove(event.device);
      _stylusDevices[event.pointer] = event.device;
    }
    if (touches.isNotEmpty) {
      _cancelledGestureContacts.addAll(touches);
      rejectedPointers.addAll(touches);
      cancellationEpoch++;
    }
    pointers = 0;
  }

  void _startPostContactGrace() {
    _postContactGrace = true;
    _postContactTimer?.cancel();
    _postContactTimer = Timer(const Duration(milliseconds: 300), () {
      _postContactGrace = false;
      _postContactTimer = null;
    });
  }

  /// Once a contact becomes palm-sized it stays rejected until UP or CANCEL.
  /// Do not notify reset listeners: a palm must not cancel an active pen stroke.
  void observeTouch(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch &&
        event.radiusMajor > palmRadiusThreshold &&
        rejectedPointers.add(event.pointer)) {
      cancellationEpoch++;
    }
  }

  void endPointer(PointerEvent event) {
    final wasStylusContact = stylusPointers.remove(event.pointer);
    _stylusDevices.remove(event.pointer);
    rejectedPointers.remove(event.pointer);
    _cancelledGestureContacts.remove(event.pointer);
    if (isPen(event) && wasStylusContact) _startPostContactGrace();
  }

  bool _oldHover(PointerEvent event) =>
      _lastHoverExit != null && event.timeStamp <= _lastHoverExit!;
  void _observeRemoval(PointerEvent event) {
    if (event is! PointerRemovedEvent || !isPen(event)) return;
    _hoverDevices.remove(event.device);
    if (_stylusDevices.containsValue(event.device)) {
      reset();
    }
  }

  /// Lost input cannot keep a hover grant or an unfinished gesture alive.
  void reset() {
    _postContactTimer?.cancel();
    _postContactTimer = null;
    _postContactGrace = false;
    _hoverDevices.clear();
    _stylusDevices.clear();
    stylusPointers.clear();
    rejectedPointers.clear();
    _cancelledGestureContacts.clear();
    _awaitingHover = true;
    pointers = 0;
    cancellationEpoch++;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _resetNativeProximity();
      reset();
    }
  }

  @override
  void dispose() {
    _sessions.remove(this);
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_observeRemoval);
    _postContactTimer?.cancel();
    super.dispose();
  }

  bool rejects(PointerEvent event) =>
      event.kind == PointerDeviceKind.touch &&
      (penNear ||
          _cancelledGestureContacts.isNotEmpty ||
          rejectedPointers.contains(event.pointer) ||
          event.radiusMajor > palmRadiusThreshold);
}

class CanvasTouchScope extends InheritedWidget {
  final CanvasTouchSession session;
  const CanvasTouchScope({
    super.key,
    required this.session,
    required super.child,
  });
  static CanvasTouchSession? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CanvasTouchScope>()?.session;
  @override
  bool updateShouldNotify(CanvasTouchScope oldWidget) =>
      session != oldWidget.session;
}

class CanvasScaleRecognizer extends ScaleGestureRecognizer {
  bool Function(PointerDownEvent)? allow;
  final Map<int, PointerEvent> _activePointers = {};
  @override
  void addAllowedPointer(PointerDownEvent event) {
    _activePointers[event.pointer] = event;
    super.addAllowedPointer(event);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    _activePointers[event.pointer] = event;
    super.addAllowedPointerPanZoom(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent ||
        event is PointerCancelEvent ||
        event is PointerPanZoomEndEvent) {
      _activePointers.remove(event.pointer);
    } else {
      _activePointers[event.pointer] = event;
    }
    super.handleEvent(event);
  }

  @override
  void rejectGesture(int pointer) {
    _activePointers.remove(pointer);
    super.rejectGesture(pointer);
  }

  void cancelActivePointers() {
    final start = onStart, update = onUpdate, end = onEnd;
    onStart = null;
    onUpdate = null;
    onEnd = null;
    try {
      for (final event in List.of(_activePointers.values)) {
        handleEvent(
          event is PointerPanZoomStartEvent ||
                  event is PointerPanZoomUpdateEvent
              ? PointerPanZoomEndEvent(
                  pointer: event.pointer,
                  device: event.device,
                )
              : PointerCancelEvent(
                  pointer: event.pointer,
                  device: event.device,
                  kind: event.kind,
                  position: event.position,
                ),
        );
      }
    } finally {
      onStart = start;
      onUpdate = update;
      onEnd = end;
    }
  }

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      (allow?.call(event) ?? true) && super.isPointerAllowed(event);
}

class ZoomableWidget extends StatefulWidget {
  @required
  final Widget? child;
  @required
  final TransformationController? controller;
  @required
  final GestureScaleUpdateCallback? onInteractionUpdate;
  final GestureScaleStartCallback? onInteractionStart;
  final bool touchDrawingEnabled;
  final bool interactionsEnabled;
  final bool stylusPanEnabled;
  final Size? sceneSize;
  final VoidCallback? onEndReached;

  const ZoomableWidget({
    Key? key,
    this.child,
    this.controller,
    this.onInteractionUpdate,
    this.touchDrawingEnabled = false,
    this.interactionsEnabled = true,
    this.stylusPanEnabled = false,
    this.sceneSize,
    this.onEndReached,
    this.onInteractionStart,
  }) : super(key: key);

  @override
  ZoomableWidgetState createState() => ZoomableWidgetState();
}

class ZoomableWidgetState extends State<ZoomableWidget> {
  // Mantenuto per compatibilita' con il codice esistente che lo imposta.
  bool enabled = true;

  static const double _kMinScale = 0.1;
  static const double _kMaxScale = 10.0;

  TransformationController? _internalController;
  TransformationController get _controller =>
      widget.controller ?? (_internalController ??= TransformationController());

  int _touchPointers = 0;
  final CanvasTouchSession _touchSession = CanvasTouchSession();
  CanvasScaleRecognizer? _recognizer;
  final Set<int> _touchIds = {};
  int _gesturePointers = 0;
  double _baseScale = 1, _gestureScale = 1;
  Offset _anchor = Offset.zero, _startFocal = Offset.zero;
  bool _gestureTouch = false, _gestureRejected = false;
  bool _wasPinch = false, _suppressPan = false, _startedAtEnd = false;
  double _upwardDrag = 0;
  Size _viewport = Size.zero;

  // Badge percentuale zoom
  bool _badgeVisible = false;
  Timer? _badgeTimer;

  double get _scale => _controller.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _touchSession.addListener(_resetInput);
  }

  void _resetInput() {
    _touchIds.clear();
    _touchPointers = 0;
    _gesturePointers = 0;
    _gestureTouch = false;
    _gestureRejected = true;
    _suppressPan = true;
    _wasPinch = false;
    _upwardDrag = 0;
    _recognizer?.cancelActivePointers();
  }

  @override
  void dispose() {
    _touchSession.dispose();
    _badgeTimer?.cancel();
    _internalController?.dispose();
    super.dispose();
  }

  bool _isPen(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;
  bool _allowPointer(PointerDownEvent event) {
    if (!widget.interactionsEnabled) return false;
    if (_isPen(event)) return widget.stylusPanEnabled;
    if (event.kind == PointerDeviceKind.touch) {
      return !_touchSession.rejects(event) &&
          (_touchIds.length < 2 || _touchIds.contains(event.pointer));
    }
    return true;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_isPen(event)) {
      _touchSession.stylusPointers.add(event.pointer);
      _observePen(event);
      return;
    }
    if (event.kind != PointerDeviceKind.touch) return;
    _touchSession.observeTouch(event);
    if (_touchSession.rejects(event) || _touchIds.length >= 2) {
      _touchSession.rejectedPointers.add(event.pointer);
      return;
    }
    if (_touchIds.isEmpty) {
      _wasPinch = false;
      _gestureRejected = false;
      _suppressPan = false;
    }
    _touchIds.add(event.pointer);
    _touchPointers = _touchIds.length;
    _touchSession.pointers = _touchPointers;
    if (_touchPointers == 2) _touchSession.cancellationEpoch++;
    if (widget.touchDrawingEnabled) setState(() {});
  }

  void _observePen(PointerEvent event) {
    if (!_isPen(event)) return;
    final hadTouches = _touchIds.isNotEmpty;
    _touchSession.observePen(event, _touchIds);
    _touchIds.clear();
    _touchPointers = 0;
    if (hadTouches || _gestureTouch) {
      _gestureRejected = true;
      _suppressPan = true;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_isPen(event)) {
      _observePen(event);
      return;
    }
    _touchSession.observeTouch(event);
    if (_touchIds.contains(event.pointer) && _touchSession.rejects(event)) {
      _gestureRejected = true;
      _suppressPan = true;
      _recognizer?.cancelActivePointers();
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _touchSession.endPointer(event);
    _touchIds.remove(event.pointer);
    _touchPointers = _touchIds.length;
    _touchSession.pointers = _touchPointers;
    if (_touchIds.isEmpty && _touchSession.stylusPointers.isEmpty)
      _suppressPan = false;
    if (widget.touchDrawingEnabled && mounted) setState(() {});
  }

  void _rebase(Offset focal, double gestureScale) {
    _baseScale = _scale;
    _gestureScale = gestureScale;
    _anchor = _controller.toScene(focal);
  }

  // Center a scene that fits; otherwise keep its edges inside the viewport.
  // Pinch and wheel zoom must use the same bounds and focal-point rules.
  void _applyTransform(double scale, Offset translation) {
    double x = translation.dx, y = translation.dy;
    if (widget.sceneSize case final Size size) {
      final remainingX = _viewport.width - size.width * scale;
      final remainingY = _viewport.height - size.height * scale;
      x = remainingX >= 0 ? remainingX / 2 : x.clamp(remainingX, 0);
      y = remainingY >= 0 ? remainingY / 2 : y.clamp(remainingY, 0);
    }
    _controller.value = Matrix4.identity()
      ..translate(x, y)
      ..scale(scale);
  }

  void _startGesture(ScaleStartDetails details) {
    _gesturePointers = details.pointerCount;
    _gestureTouch = _touchIds.isNotEmpty;
    _gestureRejected =
        (_touchSession.penNear && (_gestureTouch || !widget.stylusPanEnabled));
    _wasPinch |= details.pointerCount >= 2;
    _upwardDrag = 0;
    _startFocal = details.localFocalPoint;
    _startedAtEnd =
        widget.sceneSize != null &&
        _controller.toScene(Offset(0, _viewport.height)).dy >=
            widget.sceneSize!.height - 100;
    _rebase(details.localFocalPoint, 1);
    widget.onInteractionStart?.call(details);
  }

  void _updateGesture(ScaleUpdateDetails details) {
    if (!widget.interactionsEnabled ||
        _gestureRejected ||
        (_gestureTouch && _touchSession.penNear) ||
        (_suppressPan && !widget.stylusPanEnabled))
      return;
    // Coincident fingers have zero span; do not use it as the next divisor.
    if (!details.scale.isFinite || details.scale <= 0) return;
    if (details.pointerCount != _gesturePointers) {
      _wasPinch |= details.pointerCount >= 2;
      _gesturePointers = details.pointerCount;
      _rebase(details.localFocalPoint, details.scale);
      return;
    }
    if (_wasPinch && details.pointerCount < 2) return;
    if (widget.touchDrawingEnabled &&
        details.pointerCount < 2 &&
        !widget.stylusPanEnabled)
      return;
    final z = (_baseScale * details.scale / _gestureScale).clamp(
      _kMinScale,
      _kMaxScale,
    );
    _applyTransform(z, details.localFocalPoint - _anchor * z);
    // Use the applied position, not an out-of-bounds target: reversing at an
    // edge or scale limit must respond immediately, without retracing the drag.
    _rebase(details.localFocalPoint, details.scale);
    _upwardDrag = _startFocal.dy - details.localFocalPoint.dy;
    widget.onInteractionUpdate?.call(details);
    if (details.pointerCount >= 2) _showBadge();
  }

  void _endGesture(ScaleEndDetails details) {
    if (_gestureTouch &&
        !_gestureRejected &&
        !_wasPinch &&
        !_suppressPan &&
        _startedAtEnd &&
        _upwardDrag >= 80 &&
        !widget.touchDrawingEnabled)
      widget.onEndReached?.call();
    _gesturePointers = 0;
    // Deliberately no inertia: a pinch never turns into an unexpected page fling.
  }

  void _showBadge() {
    _badgeTimer?.cancel();
    if (!_badgeVisible && mounted) setState(() => _badgeVisible = true);
    _badgeTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _badgeVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return MouseRegion(
      opaque: false,
      onEnter: (event) {
        _touchSession.enterProximity(event);
        _observePen(event);
      },
      onExit: _touchSession.leaveProximity,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerHover: _observePen,
        onPointerMove: _onPointerMove,
        onPointerSignal: (event) {
          if (event is PointerScrollEvent &&
              widget.interactionsEnabled &&
              _touchSession.stylusPointers.isEmpty) {
            GestureBinding.instance.pointerSignalResolver.register(event, (_) {
              final anchor = _controller.toScene(event.localPosition);
              final z = (_scale * math.exp(-event.scrollDelta.dy / 500)).clamp(
                _kMinScale,
                _kMaxScale,
              );
              _applyTransform(z, event.localPosition - anchor * z);
              _showBadge();
            });
          }
        },
        onPointerUp: _onPointerEnd,
        onPointerCancel: _onPointerEnd,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            CanvasScaleRecognizer:
                GestureRecognizerFactoryWithHandlers<CanvasScaleRecognizer>(
                  () => CanvasScaleRecognizer(),
                  (instance) {
                    _recognizer = instance;
                    instance.allow = _allowPointer;
                    instance.onStart = _startGesture;
                    instance.onUpdate = _updateGesture;
                    instance.onEnd = _endGesture;
                  },
                ),
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _viewport = constraints.biggest;
                    return ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: 0,
                        maxWidth: double.infinity,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: AnimatedBuilder(
                          animation: _controller,
                          child: CanvasTouchScope(
                            session: _touchSession,
                            child: widget.child!,
                          ),
                          builder: (context, child) => Transform(
                            alignment: Alignment.topLeft,
                            transform: _controller.value,
                            child: child,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Badge "Nothing" con la percentuale di zoom (appare durante il pinch)
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _badgeVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: ShapeDecoration(
                          color: const Color(0xE0101010),
                          shape: StadiumBorder(
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.12),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ValueListenableBuilder<Matrix4>(
                              valueListenable: _controller,
                              builder: (context, matrix, _) => Text(
                                '${(matrix.getMaxScaleOnAxis() * 100).round()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
