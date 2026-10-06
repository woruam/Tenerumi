/// Keeps the same page and fractional page position at the viewport top
/// when fit-to-panel width changes. Inter-page gaps stay fixed in scene units.
double reflowSceneY(
    double y, double oldWidth, double newWidth, Iterable<double> pageRatios) {
  double oldTop = 24;
  double newTop = 24;
  if (y <= oldTop) return y;
  for (final ratio in pageRatios) {
    final oldHeight = oldWidth / ratio;
    final newHeight = newWidth / ratio;
    if (y <= oldTop + oldHeight) {
      return newTop + (y - oldTop) * newHeight / oldHeight;
    }
    if (y < oldTop + oldHeight + 24) {
      return newTop + newHeight + y - oldTop - oldHeight;
    }
    oldTop += oldHeight + 24;
    newTop += newHeight + 24;
  }
  return newTop + y - oldTop;
}
