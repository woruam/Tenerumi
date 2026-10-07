import 'dart:ui';

import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/content_snapshot.dart';

/// An in-app clipboard shared by the documents of one workspace.
/// Geometry is copied both on copy and on paste; immutable image bytes are shared.
class SelectionClipboard {
  List<XppContent> _content = [];
  Offset _origin = Offset.zero;

  bool get hasContent => _content.isNotEmpty;

  bool copy(Iterable<XppContent> selection) {
    final copies = selection.map(cloneContent).toList();
    Rect? bounds;
    for (final content in copies) {
      final rect = content.bounds();
      if (rect == null || !rect.isFinite) continue;
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    if (copies.isEmpty || bounds == null) return false;
    _content = copies;
    _origin = bounds.topLeft;
    return true;
  }

  List<XppContent> pasteAt(Offset position) {
    if (!position.dx.isFinite || !position.dy.isFinite) return [];
    return _content.map((content) {
      final copy = cloneContent(content);
      copy.translate(position - _origin);
      return copy;
    }).toList();
  }
}
