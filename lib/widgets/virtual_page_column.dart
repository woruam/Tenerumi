import 'package:flutter/material.dart';

/// Keeps scene geometry stable while mounting only pages near the viewport.
class VirtualPageColumn extends StatefulWidget {
  final TransformationController transform;
  final Size viewport;
  final double width;
  final List<double> heights;
  final Widget Function(int) pageBuilder;
  final ValueChanged<Set<int>>? onVisiblePages;
  final ValueChanged<int>? onCurrentPage;

  const VirtualPageColumn({
    super.key,
    required this.transform,
    required this.viewport,
    required this.width,
    required this.heights,
    required this.pageBuilder,
    this.onVisiblePages,
    this.onCurrentPage,
  });

  @override
  State<VirtualPageColumn> createState() => _VirtualPageColumnState();
}

class _VirtualPageColumnState extends State<VirtualPageColumn> {
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.transform,
    builder: (context, _) {
      final a = widget.transform.toScene(Offset.zero);
      final b = widget.transform.toScene(
        Offset(widget.viewport.width, widget.viewport.height),
      );
      final visible = Rect.fromPoints(a, b).inflate(300);
      double top = 24;
      final children = <Widget>[];
      final indices = <int>{};
      int current = 0;
      double best = double.infinity;
      final centerY = (a.dy + b.dy) / 2;
      for (var i = 0; i < widget.heights.length; i++) {
        final height = widget.heights[i];
        final distance = (top + height / 2 - centerY).abs();
        if (distance < best) {
          best = distance;
          current = i;
        }
        if (Rect.fromLTWH(16, top, widget.width, height).overlaps(visible)) {
          indices.add(i);
          children.add(
            Positioned(
              key: ValueKey(i),
              top: top,
              left: 16,
              width: widget.width,
              height: height,
              child: widget.pageBuilder(i),
            ),
          );
        }
        top += height + 24;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onVisiblePages?.call(indices);
          widget.onCurrentPage?.call(current);
        }
      });
      return SizedBox(
        width: widget.width + 32,
        height: top,
        child: Stack(children: children),
      );
    },
  );
}
