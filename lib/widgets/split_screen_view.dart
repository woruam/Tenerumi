import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'ZoomableWidget.dart';

import 'package:provider/provider.dart';

import 'package:xournalpp/controllers/workspace_controller.dart';

import 'split_resize_scope.dart';

/// Vista affiancata (split-screen) in stile "Nothing OS".
///
/// - Responsive: in landscape i due pannelli sono affiancati (Row), in portrait
///   impilati (Column).
/// - Il divisore e' trascinabile e tiene sincronizzato `WorkspaceController.dividerRatio`
///   (sync bidirezionale via Provider): la proporzione e' la fonte di verita' del workspace.
/// - Impugnatura a "matrice di punti" che si illumina con il colore d'accento.
class SplitScreenView extends StatefulWidget {
  final Widget primaryWidget;
  final Widget secondaryWidget;

  const SplitScreenView({
    Key? key,
    required this.primaryWidget,
    required this.secondaryWidget,
  }) : super(key: key);

  static const double _thickness = 14;

  @override
  State<SplitScreenView> createState() => _SplitScreenViewState();
}

class _SplitScreenViewState extends State<SplitScreenView> {
  bool _resizing = false;
  static const double _thickness = SplitScreenView._thickness;

  @override
  Widget build(BuildContext context) {
    final WorkspaceController ws = context.watch<WorkspaceController>();
    final double r =
        ws.dividerRatio; // gia' vincolato a 0.2..0.8 dal controller

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool horizontal = constraints.maxWidth >= constraints.maxHeight;
        final double total = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final double available = total - _thickness;
        final double primarySize = available <= 0 ? 0.0 : available * r;

        final Widget divider = _DragDivider(
          onResize: (value) {
            if (_resizing != value) setState(() => _resizing = value);
          },
          horizontal: horizontal,
          thickness: _thickness,
          onDelta: (delta) {
            if (available <= 0) return;
            // setDivider applica internamente il clamp 0.2..0.8
            context.read<WorkspaceController>().setDivider(
              ws.dividerRatio + delta / available,
            );
          },
          onDoubleTap: () =>
              context.read<WorkspaceController>().setDivider(0.5),
        );

        final Widget primary = _wrap(widget.primaryWidget);
        final Widget secondary = _wrap(widget.secondaryWidget);

        if (horizontal) {
          return SplitResizeScope(
            resizing: _resizing,
            child: Row(
              children: [
                SizedBox(width: primarySize, child: primary),
                divider,
                Expanded(child: secondary),
              ],
            ),
          );
        }
        return SplitResizeScope(
          resizing: _resizing,
          child: Column(
            children: [
              SizedBox(height: primarySize, child: primary),
              divider,
              Expanded(child: secondary),
            ],
          ),
        );
      },
    );
  }

  Widget _wrap(Widget child) =>
      ClipRRect(borderRadius: BorderRadius.circular(8), child: child);
}

/// Divisore trascinabile con impugnatura dot-matrix.
class _DragDivider extends StatefulWidget {
  final ValueChanged<bool> onResize;
  final bool horizontal;
  final double thickness;
  final ValueChanged<double> onDelta;
  final VoidCallback onDoubleTap;

  const _DragDivider({
    required this.onResize,
    required this.horizontal,
    required this.thickness,
    required this.onDelta,
    required this.onDoubleTap,
  });

  @override
  State<_DragDivider> createState() => _DragDividerState();
}

class _DragDividerState extends State<_DragDivider>
    with WidgetsBindingObserver {
  bool _active = false;
  bool _gestureAccepted = false;
  int? _pointer;
  PointerEvent? _lastEvent;
  final Set<int> _contacts = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _cancelResize() {
    _gestureAccepted = false;
    _pointer = null;
    if (_active) setState(() => _active = false);
    widget.onResize(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _contacts.clear();
      _cancelResize();
    }
  }

  void _down(PointerDownEvent event) {
    _lastEvent = event;
    _contacts.add(event.pointer);
    if (_contacts.length != 1 || CanvasTouchSession.rejectsNavigation(event)) {
      _cancelResize();
      return;
    }
    _pointer = event.pointer;
    _gestureAccepted = true;
    widget.onResize(true);
  }

  void _move(PointerMoveEvent event) {
    if (_pointer == event.pointer &&
        CanvasTouchSession.rejectsNavigation(event)) {
      _cancelResize();
    }
  }

  void _end(PointerEvent event) {
    _contacts.remove(event.pointer);
    if (_pointer == event.pointer) {
      _pointer = null;
      if (_active) setState(() => _active = false);
      widget.onResize(false);
    }
  }

  void _startDrag() {
    if (_gestureAccepted && _pointer != null) setState(() => _active = true);
  }

  void _delta(double delta) {
    if (_gestureAccepted && _pointer != null) widget.onDelta(delta);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color handleColor = _active
        ? cs.primary
        : Colors.grey.withOpacity(0.45);

    return MouseRegion(
      cursor: widget.horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: Listener(
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _end,
        onPointerCancel: (event) {
          _contacts.remove(event.pointer);
          _cancelResize();
        },
        child: GestureDetector(
          key: const ValueKey('split-divider'),
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () {
            if (_gestureAccepted &&
                _lastEvent != null &&
                !CanvasTouchSession.rejectsNavigation(_lastEvent!))
              widget.onDoubleTap();
          },
          onHorizontalDragStart: widget.horizontal ? (_) => _startDrag() : null,
          onHorizontalDragEnd: widget.horizontal
              ? (_) => setState(() => _active = false)
              : null,
          onHorizontalDragCancel: widget.horizontal
              ? () {
                  setState(() => _active = false);
                  widget.onResize(false);
                }
              : null,
          onHorizontalDragUpdate: widget.horizontal
              ? (d) => _delta(d.delta.dx)
              : null,
          onVerticalDragStart: widget.horizontal ? null : (_) => _startDrag(),
          onVerticalDragEnd: widget.horizontal
              ? null
              : (_) => setState(() => _active = false),
          onVerticalDragCancel: widget.horizontal
              ? null
              : () {
                  setState(() => _active = false);
                  widget.onResize(false);
                },
          onVerticalDragUpdate: widget.horizontal
              ? null
              : (d) => _delta(d.delta.dy),
          child: Container(
            width: widget.horizontal ? widget.thickness : double.infinity,
            height: widget.horizontal ? double.infinity : widget.thickness,
            color: Colors.black,
            alignment: Alignment.center,
            child: _DotMatrixHandle(
              horizontal: widget.horizontal,
              color: handleColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Impugnatura a matrice di punti (3 puntini).
class _DotMatrixHandle extends StatelessWidget {
  final bool horizontal;
  final Color color;
  const _DotMatrixHandle({required this.horizontal, required this.color});

  @override
  Widget build(BuildContext context) {
    final List<Widget> dots = List.generate(
      3,
      (_) => Container(
        width: 3,
        height: 3,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
    return horizontal
        ? Column(mainAxisSize: MainAxisSize.min, children: dots)
        : Row(mainAxisSize: MainAxisSize.min, children: dots);
  }
}
