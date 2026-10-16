import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Screen-sized navigation rail over the transformed document.
class PageScrollbar extends StatelessWidget {
  final TransformationController transform;
  final Size viewport;
  final double sceneHeight;
  final int currentPage;
  final int pageCount;
  const PageScrollbar({
    super.key,
    required this.transform,
    required this.viewport,
    required this.sceneHeight,
    required this.currentPage,
    required this.pageCount,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: transform,
    builder: (context, _) {
      final scale = transform.value.getMaxScaleOnAxis();
      final contentHeight = sceneHeight * scale;
      final maxScroll = math.max(0.0, contentHeight - viewport.height);
      final trackHeight = math.max(0.0, viewport.height - 24);
      if (maxScroll == 0 || trackHeight < 48 || pageCount == 0) {
        return const SizedBox.shrink();
      }
      final thumbHeight = (trackHeight * viewport.height / contentHeight)
          .clamp(math.min(48.0, trackHeight), trackHeight)
          .toDouble();
      final travel = trackHeight - thumbHeight;
      final offset = -transform.value.entry(1, 3);
      final progress = (offset / maxScroll).clamp(0.0, 1.0);
      void seek(double progress) {
        final matrix = transform.value.clone();
        matrix.setEntry(1, 3, -progress.clamp(0.0, 1.0) * maxScroll);
        transform.value = matrix;
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Semantics(
          label: 'Scorrimento pagine',
          value: '${currentPage + 1} di $pageCount',
          increasedValue:
              '${(currentPage + 2).clamp(1, pageCount)} di $pageCount',
          decreasedValue: '${currentPage.clamp(1, pageCount)} di $pageCount',
          onIncrease: () => seek(progress + viewport.height / maxScroll),
          onDecrease: () => seek(progress - viewport.height / maxScroll),
          child: GestureDetector(
            key: const ValueKey('page-scrollbar'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              if (travel > 0)
                seek((details.localPosition.dy - thumbHeight / 2) / travel);
            },
            onVerticalDragUpdate: (details) {
              if (travel > 0)
                seek(
                  -transform.value.entry(1, 3) / maxScroll +
                      details.delta.dy / travel,
                );
            },
            child: SizedBox(
              width: 36,
              height: trackHeight,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    width: 4,
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Positioned(
                    top: progress * travel,
                    child: Tooltip(
                      message: 'Pagina ${currentPage + 1} / $pageCount',
                      child: Container(
                        width: 8,
                        height: thumbHeight,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
