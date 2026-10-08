import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Shared across page listeners so a pinch spanning two pages never adds ink.
class CanvasTouchSession {
  int pointers = 0;
  int cancellationEpoch = 0;
  final Set<int> stylusPointers = {};
  final Set<int> rejectedPointers = {};
  bool rejects(PointerEvent event) =>
      event.kind == PointerDeviceKind.touch &&
      (stylusPointers.isNotEmpty ||
          rejectedPointers.contains(event.pointer) ||
          event.radiusMajor > 28);
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

/// Riconoscitore di doppio tocco limitato al SOLO dito: il doppio tap con la
/// penna non deve mai zoomare (con lo stilo si disegnano i puntini!).
class _TouchOnlyDoubleTapRecognizer extends DoubleTapGestureRecognizer {
  bool Function(PointerDownEvent)? allow;
  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      event.kind == PointerDeviceKind.touch &&
      (allow?.call(event) ?? true) &&
      event.radiusMajor <= 28 &&
      super.isPointerAllowed(event);
}

class CanvasScaleRecognizer extends ScaleGestureRecognizer {
  bool Function(PointerDownEvent)? allow;
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

class ZoomableWidgetState extends State<ZoomableWidget>
    with SingleTickerProviderStateMixin {
  // Mantenuto per compatibilita' con il codice esistente che lo imposta.
  bool enabled = true;

  static const double _kMinScale = 0.1;
  static const double _kMaxScale = 10.0;
  static const double _kFreePanThreshold = 1.05;
  static const double _kDoubleTapScale = 2.5;

  TransformationController? _internalController;
  TransformationController get _controller =>
      widget.controller ?? (_internalController ??= TransformationController());

  int _touchPointers = 0;
  final CanvasTouchSession _touchSession = CanvasTouchSession();
  final Set<int> _touchIds = {};
  int _gesturePointers = 0;
  double _baseScale = 1, _gestureScale = 1;
  Offset _anchor = Offset.zero, _startFocal = Offset.zero;
  bool _gestureTouch = false, _gestureRejected = false;
  bool _wasPinch = false, _suppressPan = false, _startedAtEnd = false;
  double _upwardDrag = 0;
  DateTime? _lastStylusHover;
  Size _viewport = Size.zero;
  PanAxis _axis = PanAxis.vertical;

  late final AnimationController _zoomAnimController;
  Animation<Matrix4>? _zoomAnimation;

  // Badge percentuale zoom
  bool _badgeVisible = false;
  Timer? _badgeTimer;

  double get _scale => _controller.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _zoomAnimController.addListener(() {
      final anim = _zoomAnimation;
      if (anim != null) _controller.value = anim.value;
    });
    _controller.addListener(_onTransformChanged);
    _recomputeAxis();
  }

  @override
  void didUpdateWidget(covariant ZoomableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _internalController)?.removeListener(
        _onTransformChanged,
      );
      _controller.addListener(_onTransformChanged);
    }
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    _zoomAnimController.dispose();
    (widget.controller ?? _internalController)?.removeListener(
      _onTransformChanged,
    );
    _internalController?.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    _recomputeAxis();
    if (_badgeVisible && mounted) setState(() {});
  }

  void _recomputeAxis() {
    final PanAxis next = (_touchPointers >= 2 || _scale > _kFreePanThreshold)
        ? PanAxis.free
        : PanAxis.vertical;
    if (next != _axis && mounted) {
      setState(() => _axis = next);
    } else {
      _axis = next;
    }
  }

  bool _isPen(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;
  bool _allowPointer(PointerDownEvent event) {
    if (!widget.interactionsEnabled) return false;
    if (_isPen(event)) return widget.stylusPanEnabled;
    if (event.kind == PointerDeviceKind.touch) {
      return !_touchSession.rejects(event) &&
          (_lastStylusHover == null ||
              DateTime.now().difference(_lastStylusHover!).inMilliseconds >
                  300) &&
          (_touchIds.length < 2 || _touchIds.contains(event.pointer));
    }
    return true;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_isPen(event)) {
      _touchSession.stylusPointers.add(event.pointer);
      _touchSession.cancellationEpoch++;
      _suppressPan = true;
      _gestureRejected = true;
      return;
    }
    if (event.kind != PointerDeviceKind.touch) return;
    if (_touchSession.rejects(event) ||
        _touchIds.length >= 2 ||
        (_lastStylusHover != null &&
            DateTime.now().difference(_lastStylusHover!).inMilliseconds <=
                300)) {
      _touchSession.rejectedPointers.add(event.pointer);
      return;
    }
    if (_touchIds.isEmpty) {
      _wasPinch = false;
      _gestureRejected = false;
    }
    _touchIds.add(event.pointer);
    _touchPointers = _touchIds.length;
    _touchSession.pointers = _touchPointers;
    if (_touchPointers == 2) _touchSession.cancellationEpoch++;
    if (widget.touchDrawingEnabled) setState(() {});
    _recomputeAxis();
  }

  void _onPointerEnd(PointerEvent event) {
    _touchSession.stylusPointers.remove(event.pointer);
    _touchSession.rejectedPointers.remove(event.pointer);
    _touchIds.remove(event.pointer);
    _touchPointers = _touchIds.length;
    _touchSession.pointers = _touchPointers;
    if (_touchIds.isEmpty && _touchSession.stylusPointers.isEmpty)
      _suppressPan = false;
    if (widget.touchDrawingEnabled && mounted) setState(() {});
    _recomputeAxis();
  }

  void _rebase(Offset focal, double gestureScale) {
    _baseScale = _scale;
    _gestureScale = gestureScale;
    _anchor = _controller.toScene(focal);
  }

  void _startGesture(ScaleStartDetails details) {
    _zoomAnimController.stop();
    _gesturePointers = details.pointerCount;
    _gestureTouch = _touchIds.isNotEmpty;
    _gestureRejected =
        _touchSession.stylusPointers.isNotEmpty && !widget.stylusPanEnabled;
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
        (_suppressPan && !widget.stylusPanEnabled))
      return;
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
    final current = _controller.value;
    double x = details.localFocalPoint.dx - _anchor.dx * z;
    double y = details.localFocalPoint.dy - _anchor.dy * z;
    if (details.pointerCount < 2 && z <= _kFreePanThreshold)
      x = current.entry(0, 3);
    if (widget.sceneSize case final Size size) {
      x = x.clamp(
        (_viewport.width - size.width * z).clamp(-double.infinity, 0) - 120,
        120,
      );
      y = y.clamp(
        (_viewport.height - size.height * z).clamp(-double.infinity, 0) - 80,
        80,
      );
    }
    _controller.value = Matrix4.identity()
      ..translate(x, y)
      ..scale(z);
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

  void _animateTo(Matrix4 target) {
    _zoomAnimation = Matrix4Tween(begin: _controller.value, end: target)
        .animate(
          CurvedAnimation(
            parent: _zoomAnimController,
            curve: Curves.easeOutCubic,
          ),
        );
    _zoomAnimController
      ..reset()
      ..forward();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    if (_scale > 1.2) {
      _animateTo(Matrix4.identity());
    } else {
      const double z = _kDoubleTapScale;
      final Offset p = details.localPosition;
      final Matrix4 target = Matrix4.identity()
        ..translate(-p.dx * (z - 1), -p.dy * (z - 1))
        ..scale(z);
      _animateTo(target);
    }
    _showBadge();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerHover: (event) {
        if (_isPen(event)) _lastStylusHover = DateTime.now();
      },
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            widget.interactionsEnabled &&
            _touchSession.stylusPointers.isEmpty) {
          GestureBinding.instance.pointerSignalResolver.register(event, (_) {
            _zoomAnimController.stop();
            final anchor = _controller.toScene(event.localPosition);
            final z = (_scale * math.exp(-event.scrollDelta.dy / 500)).clamp(
              .1,
              10.0,
            );
            _controller.value = Matrix4.identity()
              ..translate(
                event.localPosition.dx - anchor.dx * z,
                event.localPosition.dy - anchor.dy * z,
              )
              ..scale(z);
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
                  instance.allow = _allowPointer;
                  instance.onStart = _startGesture;
                  instance.onUpdate = _updateGesture;
                  instance.onEnd = _endGesture;
                },
              ),
          _TouchOnlyDoubleTapRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _TouchOnlyDoubleTapRecognizer
              >(() => _TouchOnlyDoubleTapRecognizer(), (instance) {
                instance.allow = _allowPointer;
                instance.onDoubleTapDown =
                    widget.touchDrawingEnabled || !widget.interactionsEnabled
                    ? null
                    : _handleDoubleTapDown;
              }),
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
                        builder: (context, _) => Transform(
                          alignment: Alignment.topLeft,
                          transform: _controller.value,
                          child: CanvasTouchScope(
                            session: _touchSession,
                            child: widget.child!,
                          ),
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
                          Text(
                            '${(_scale * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              letterSpacing: 1,
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
    );
  }
}
