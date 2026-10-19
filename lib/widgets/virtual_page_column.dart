import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Viewport movement changes only a transform until a page enters/leaves view.
/// Geometry is computed once per document layout, with binary range searches.
class VirtualPageColumn extends StatefulWidget {
  final TransformationController transform;
  final Size viewport;
  final double width;
  final List<double> heights;
  final Widget Function(int) pageBuilder;
  final ValueChanged<Set<int>>? onVisiblePages;
  final ValueChanged<int>? onCurrentPage;
  final Color? currentPageBorderColor;
  const VirtualPageColumn({
    super.key,
    required this.transform,
    required this.viewport,
    required this.width,
    required this.heights,
    required this.pageBuilder,
    this.onVisiblePages,
    this.onCurrentPage,
    this.currentPageBorderColor,
  });
  @override
  State<VirtualPageColumn> createState() => _VirtualPageColumnState();
}

class _VirtualPageColumnState extends State<VirtualPageColumn> {
  List<double> _tops = [];
  List<double> _centers = [];
  List<int> _visible = [];
  int _current = 0;
  double _height = 24;
  bool _callbackPending = false;
  @override
  void initState() {
    super.initState();
    _layout();
    widget.transform.addListener(_viewportChanged);
    _viewportChanged();
  }

  void _layout() {
    double top = 24;
    _tops = [];
    _centers = [];
    for (final height in widget.heights) {
      _tops.add(top);
      _centers.add(top + height / 2);
      top += height + 24;
    }
    _height = top;
  }

  int _lowerBound(List<double> values, double target) {
    int lo = 0, hi = values.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (values[mid] < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  void didUpdateWidget(VirtualPageColumn old) {
    super.didUpdateWidget(old);
    if (old.transform != widget.transform) {
      old.transform.removeListener(_viewportChanged);
      widget.transform.addListener(_viewportChanged);
    }
    if (!listEquals(old.heights, widget.heights)) _layout();
    _viewportChanged();
    _scheduleCallbacks(); // PDF epochs can change while the range stays the same.
  }

  void _viewportChanged() {
    final sceneViewport = MatrixUtils.inverseTransformRect(
      widget.transform.value,
      Offset.zero & widget.viewport,
    );
    final visible = sceneViewport.inflate(300);
    final next = <int>[];
    final start = (_lowerBound(_tops, visible.top) - 1).clamp(0, _tops.length);
    final end = _lowerBound(_tops, visible.bottom);
    for (var i = start; i < end; i++) {
      if (Rect.fromLTWH(
        16,
        _tops[i],
        widget.width,
        widget.heights[i],
      ).overlaps(visible))
        next.add(i);
    }
    final center = sceneViewport.center.dy;
    int current = _lowerBound(
      _centers,
      center,
    ).clamp(0, (_centers.length - 1).clamp(0, _centers.length));
    if (current > 0 &&
        (center - _centers[current - 1]).abs() <=
            (center - _centers[current]).abs())
      current--;
    final changed = !listEquals(_visible, next);
    final currentChanged = current != _current;
    _current = current;
    if (changed || currentChanged) {
      _visible = next;
      if (mounted) setState(() {});
    }
    if (changed || currentChanged) _scheduleCallbacks();
  }

  void _scheduleCallbacks() {
    if (_callbackPending) return;
    _callbackPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _callbackPending = false;
      if (!mounted) return;
      widget.onVisiblePages?.call(_visible.toSet());
      if (_tops.isNotEmpty) widget.onCurrentPage?.call(_current);
    });
  }

  @override
  void dispose() {
    widget.transform.removeListener(_viewportChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width + 32,
    height: _height,
    child: Stack(
      children: [
        for (final i in _visible)
          Positioned(
            key: ValueKey(i),
            top: _tops[i],
            left: 16,
            width: widget.width,
            height: widget.heights[i],
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.pageBuilder(i),
                if (i == _current && widget.currentPageBorderColor != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ListenableBuilder(
                        listenable: widget.transform,
                        builder: (context, _) => DecoratedBox(
                          key: const ValueKey('current-page-border'),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: widget.currentPageBorderColor!,
                              width:
                                  1 /
                                  widget.transform.value.getMaxScaleOnAxis(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
