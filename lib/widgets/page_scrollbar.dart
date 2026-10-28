import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'ZoomableWidget.dart';

/// Screen-sized navigation rail over the transformed document.
class PageScrollbar extends StatefulWidget {
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
  State<PageScrollbar> createState() => _PageScrollbarState();
}

class _PageScrollbarState extends State<PageScrollbar>
    with WidgetsBindingObserver {
  final Set<int> _contacts = {};
  int? _dragPointer;
  double _lastY = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _contacts.clear();
      _dragPointer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(PageScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transform != widget.transform) {
      _contacts.clear();
      _dragPointer = null;
    }
  }

  void _end(PointerEvent event) {
    _contacts.remove(event.pointer);
    if (_dragPointer == event.pointer) _dragPointer = null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.transform,
    builder: (context, _) {
      final transform = widget.transform;
      final viewport = widget.viewport;
      final sceneHeight = widget.sceneHeight;
      final currentPage = widget.currentPage;
      final pageCount = widget.pageCount;
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
          child: Listener(
            key: const ValueKey('page-scrollbar'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              _contacts.add(event.pointer);
              if (_contacts.length != 1 ||
                  CanvasTouchSession.rejectsNavigation(event)) {
                _dragPointer = null;
                return;
              }
              _dragPointer = event.pointer;
              _lastY = event.localPosition.dy;
              if (travel > 0) seek((_lastY - thumbHeight / 2) / travel);
            },
            onPointerMove: (event) {
              if (_dragPointer != event.pointer) return;
              if (CanvasTouchSession.rejectsNavigation(event)) {
                _dragPointer = null;
                return;
              }
              if (travel > 0)
                seek(
                  -transform.value.entry(1, 3) / maxScroll +
                      (event.localPosition.dy - _lastY) / travel,
                );
              _lastY = event.localPosition.dy;
            },
            onPointerUp: _end,
            onPointerCancel: _end,
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
