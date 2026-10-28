import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/src/stylus_shortcut.dart';

/// Physical-screen geometry shared by painting and the held pen's hit testing.
class StylusRadialLayout {
  final Rect bounds;
  final double scale;
  StylusRadialLayout(Size viewport, EdgeInsets padding, Offset position)
    : scale = math.min(
        1.0,
        math.max(
              1.0,
              math.min(
                viewport.width - padding.horizontal - 16,
                viewport.height - padding.vertical - 16,
              ),
            ) /
            264,
      ),
      bounds = _bounds(viewport, padding, position);

  static Rect _bounds(Size viewport, EdgeInsets padding, Offset position) {
    final diameter = math.min(
      264.0,
      math.max(
        1.0,
        math.min(
          viewport.width - padding.horizontal - 16,
          viewport.height - padding.vertical - 16,
        ),
      ),
    );
    final left = (position.dx - diameter / 2).clamp(
      padding.left + 8,
      math.max(padding.left + 8, viewport.width - padding.right - diameter - 8),
    );
    final top = (position.dy - diameter / 2).clamp(
      padding.top + 8,
      math.max(
        padding.top + 8,
        viewport.height - padding.bottom - diameter - 8,
      ),
    );
    return Rect.fromLTWH(left.toDouble(), top.toDouble(), diameter, diameter);
  }

  Offset buttonCenter(int index) =>
      bounds.center +
      Offset(
        88 * scale * math.cos(-math.pi / 2 + index * math.pi / 3),
        88 * scale * math.sin(-math.pi / 2 + index * math.pi / 3),
      );

  int? hitTest(Offset position) {
    for (var i = 0; i < 6; i++) {
      if ((buttonCenter(i) - position).distance <= 32 * scale) return i;
    }
    return null;
  }
}

/// An input-transparent overlay: the DOWN hit test stays with the original
/// page until UP/CANCEL, even when the pen travels outside that page or pane.
class StylusRadialMenuController {
  final List<StylusShortcut> shortcuts;
  final VoidCallback? onPaste;
  final ValueChanged<StylusShortcut> onSelect;
  final Offset _openingPosition;
  final RenderBox _overlayBox;
  final StylusRadialLayout layout;
  final ValueNotifier<int?> _selected = ValueNotifier(null);
  OverlayEntry? _entry;
  bool _hasMoved = false;

  StylusRadialMenuController._(
    this.shortcuts,
    this.onPaste,
    this.onSelect,
    this._openingPosition,
    this._overlayBox,
    this.layout,
  );

  static StylusRadialMenuController open(
    BuildContext context, {
    required Offset position,
    required List<StylusShortcut> shortcuts,
    required VoidCallback? onPaste,
    required ValueChanged<StylusShortcut> onSelect,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final box = overlay.context.findRenderObject() as RenderBox;
    final menu = StylusRadialMenuController._(
      List.unmodifiable(shortcuts),
      onPaste,
      onSelect,
      position,
      box,
      StylusRadialLayout(
        box.size,
        MediaQuery.paddingOf(overlay.context),
        box.globalToLocal(position),
      ),
    );
    menu._entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: ValueListenableBuilder<int?>(
            valueListenable: menu._selected,
            builder: (context, selected, _) => Stack(
              key: const ValueKey('stylus-radial-menu'),
              children: [
                for (var i = 0; i < 6; i++)
                  Positioned(
                    left:
                        menu.layout.buttonCenter(i).dx - 28 * menu.layout.scale,
                    top:
                        menu.layout.buttonCenter(i).dy - 28 * menu.layout.scale,
                    width: 56 * menu.layout.scale,
                    height: 56 * menu.layout.scale,
                    child: FittedBox(
                      child: Semantics(
                        label: i == 0 ? 'Incolla' : shortcuts[i - 1].label,
                        selected: selected == i,
                        enabled: i != 0 || onPaste != null,
                        child: Material(
                          key: ValueKey(
                            i == 0 ? 'selection-paste' : 'radial-slot-$i',
                          ),
                          color: selected == i
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFF666666),
                          elevation: selected == i ? 6 : 2,
                          shape: CircleBorder(
                            side: BorderSide(
                              color: selected == i
                                  ? Colors.white
                                  : Colors.white24,
                              width: selected == i ? 2 : 1,
                            ),
                          ),
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: Center(
                              child: IconTheme(
                                data: IconThemeData(
                                  size: 24,
                                  color: i == 0 && onPaste == null
                                      ? Colors.white30
                                      : Colors.white,
                                ),
                                child: i == 0
                                    ? const Icon(Icons.content_paste)
                                    : Stack(
                                        alignment: Alignment.bottomRight,
                                        children: [
                                          Icon(shortcuts[i - 1].icon),
                                          if (shortcuts[i - 1].tool !=
                                                  EditingTool.ERASER &&
                                              shortcuts[i - 1].tool !=
                                                  EditingTool.MOVE &&
                                              shortcuts[i - 1].tool !=
                                                  EditingTool.SELECT)
                                            Container(
                                              width: 9,
                                              height: 9,
                                              decoration: BoxDecoration(
                                                color: shortcuts[i - 1].color,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
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
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(menu._entry!);
    return menu;
  }

  void update(Offset position) {
    if (_entry == null) return;
    _hasMoved |= (position - _openingPosition).distance > kTouchSlop;
    final hit = _hasMoved
        ? layout.hitTest(_overlayBox.globalToLocal(position))
        : null;
    _selected.value = hit == 0 && onPaste == null ? null : hit;
  }

  void finish(Offset position) {
    if (_entry == null) return;
    update(position);
    final index = _selected.value;
    dismiss();
    if (index == 0) {
      onPaste?.call();
    } else if (index != null) {
      onSelect(shortcuts[index - 1]);
    }
  }

  void dismiss() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    entry.remove();
    entry.dispose();
    _selected.dispose();
  }
}
