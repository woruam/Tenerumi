import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppTexImage.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppLayer.dart';

/// Copies mutable geometry while sharing immutable pixel data.
XppContent cloneContent(XppContent content) {
  if (content is XppStroke) {
    return content.copyWithSharedPoints();
  }
  if (content is XppText) {
    return XppText(
      size: content.size,
      offset: content.offset,
      fontFamily: content.fontFamily,
      color: content.color,
      text: content.text,
    );
  }
  if (content is XppImage) {
    return XppImage(
      data: content.data,
      topLeft: content.topLeft,
      bottomRight: content.bottomRight,
    );
  }
  if (content is XppTexImage) {
    return XppTexImage(
      text: content.text,
      topLeft: content.topLeft,
      bottomRight: content.bottomRight,
      color: content.color,
    );
  }
  throw UnsupportedError('Snapshot not supported for ${content.runtimeType}');
}

List<XppContent?> cloneContents(Iterable<XppContent?> contents) => contents
    .map((content) => content == null ? null : cloneContent(content))
    .toList();
