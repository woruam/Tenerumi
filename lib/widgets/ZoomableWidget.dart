import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Shared across page listeners so a pinch spanning two pages never adds ink.
class CanvasTouchSession {
  int pointers = 0;
  int cancellationEpoch = 0;
}

class CanvasTouchScope extends InheritedWidget {
  final CanvasTouchSession session;
  const CanvasTouchScope(
      {super.key, required this.session, required super.child});
  static CanvasTouchSession? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CanvasTouchScope>()?.session;
  @override
  bool updateShouldNotify(CanvasTouchScope oldWidget) =>
      session != oldWidget.session;
}

/// Riconoscitore di doppio tocco limitato al SOLO dito: il doppio tap con la
/// penna non deve mai zoomare (con lo stilo si disegnano i puntini!).
class _TouchOnlyDoubleTapRecognizer extends DoubleTapGestureRecognizer {
  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      event.kind == PointerDeviceKind.touch && super.isPointerAllowed(event);
}

/// Contenitore zoomabile della tela.
///
/// FIX PINCH-ZOOM: prima l'InteractiveViewer aveva `panAxis: PanAxis.vertical`
/// fisso. Con l'asse bloccato, durante il pinch anche il punto focale del
/// gesto veniva vincolato in verticale: lo zoom "scattava", non si riusciva a
/// zoomare verso un punto preciso e, una volta ingranditi, era impossibile
/// spostarsi in orizzontale.
///
/// Ora l'asse di pan e' DINAMICO:
/// - 1 dito a zoom 100%  -> pan solo verticale (scorrimento naturale del foglio);
/// - 2 dita (pinch)      -> asse libero: zoom fluido verso il punto desiderato;
/// - zoom > 105%         -> asse libero anche con 1 dito, per muoversi ovunque
///                          nella pagina ingrandita.
///
/// Extra: doppio TOCCO (solo dito) per ingrandire al 250% sul punto toccato /
/// tornare al 100% con animazione, e badge temporaneo con la percentuale.
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

  const ZoomableWidget(
      {Key? key,
      this.child,
      this.controller,
      this.onInteractionUpdate,
      this.touchDrawingEnabled = false,
      this.interactionsEnabled = true,
      this.onInteractionStart})
      : super(key: key);

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
        vsync: this, duration: const Duration(milliseconds: 260));
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
      (oldWidget.controller ?? _internalController)
          ?.removeListener(_onTransformChanged);
      _controller.addListener(_onTransformChanged);
    }
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    _zoomAnimController.dispose();
    (widget.controller ?? _internalController)
        ?.removeListener(_onTransformChanged);
    _internalController?.dispose();
    super.dispose();
  }

  void _onTransformChanged() => _recomputeAxis();

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

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _touchPointers++;
    _touchSession.pointers = _touchPointers;
    if (_touchPointers == 2) _touchSession.cancellationEpoch++;
    if (widget.touchDrawingEnabled) setState(() {});
    _recomputeAxis();
  }

  void _onPointerEnd(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _touchPointers = (_touchPointers - 1).clamp(0, 20);
    _touchSession.pointers = _touchPointers;
    if (widget.touchDrawingEnabled) setState(() {});
    _recomputeAxis();
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
        .animate(CurvedAnimation(
            parent: _zoomAnimController, curve: Curves.easeOutCubic));
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
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: RawGestureDetector(
        gestures: <Type, GestureRecognizerFactory>{
          _TouchOnlyDoubleTapRecognizer: GestureRecognizerFactoryWithHandlers<
              _TouchOnlyDoubleTapRecognizer>(
            () => _TouchOnlyDoubleTapRecognizer(),
            (instance) => instance.onDoubleTapDown =
                widget.touchDrawingEnabled || !widget.interactionsEnabled
                    ? null
                    : _handleDoubleTapDown,
          ),
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                key: ValueKey(widget.interactionsEnabled),
                boundaryMargin: const EdgeInsets.all(200),
                onInteractionStart: (details) {
                  widget.onInteractionStart?.call(details);
                  if (details.pointerCount >= 2) _showBadge();
                },
                onInteractionUpdate: (details) {
                  widget.onInteractionUpdate?.call(details);
                  if (details.pointerCount >= 2) _showBadge();
                },
                panEnabled: widget.interactionsEnabled &&
                    (!widget.touchDrawingEnabled || _touchPointers >= 2),
                scaleEnabled: widget.interactionsEnabled,
                constrained:
                    false, // la tela puo' essere piu' grande della finestra
                panAxis: _axis,
                minScale: _kMinScale,
                maxScale: _kMaxScale,
                transformationController: _controller,
                child: CanvasTouchScope(
                    session: _touchSession, child: widget.child!),
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
                          horizontal: 12, vertical: 5),
                      decoration: ShapeDecoration(
                        color: const Color(0xE0101010),
                        shape: StadiumBorder(
                          side: BorderSide(
                              color: Colors.white.withOpacity(0.12), width: 1),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle, color: accent),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(_scale * 100).round()}%',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                letterSpacing: 1),
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
