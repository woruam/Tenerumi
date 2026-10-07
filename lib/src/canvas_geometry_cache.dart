import 'package:flutter/material.dart';

import 'XppLayer.dart';

/// Geometry is stable while only the viewport changes. Canvas revisions cover
/// ink, erasure, selection transformations, layer edits and undo/redo.
class CanvasGeometryCache {
  int? _revision;
  final _bounds = Map<XppContent, Rect?>.identity();
  final _offsets = Map<XppContent, Offset?>.identity();
  void updateRevision(int revision) {
    if (_revision == revision) return;
    _revision = revision;
    _bounds.clear();
    _offsets.clear();
  }

  Rect? bounds(XppContent content) =>
      _bounds.putIfAbsent(content, content.bounds);
  Offset? offset(XppContent content) =>
      _offsets.putIfAbsent(content, content.getOffset);
}
