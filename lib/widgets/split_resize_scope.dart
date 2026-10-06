import 'package:flutter/widgets.dart';

/// Separates divider manipulation from document gestures and reflow.
class SplitResizeScope extends InheritedWidget {
  final bool resizing;
  const SplitResizeScope({super.key, required this.resizing, required super.child});
  static bool isResizing(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SplitResizeScope>()?.resizing ?? false;
  @override
  bool updateShouldNotify(SplitResizeScope oldWidget) => resizing != oldWidget.resizing;
}
