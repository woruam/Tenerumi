/// Preserve a real zero pressure; unavailable pressure uses the midpoint.
double normalizedStylusPressure({
  required bool isStylus,
  required double pressure,
  required double minimum,
  required double maximum,
}) {
  if (!isStylus || !pressure.isFinite) return 0.5;
  if (minimum.isFinite &&
      maximum.isFinite &&
      maximum > minimum &&
      (maximum - minimum).isFinite) {
    return ((pressure - minimum) / (maximum - minimum)).clamp(0.0, 1.0);
  }
  // Some drivers omit a usable range but still supply normalized samples.
  return pressure.clamp(0.0, 1.0);
}

/// Actual pen diameter. The selected width is the diameter at half pressure.
/// The positive, proportional minimum keeps contact visible without a plateau.
double pressurePenDiameter(double baseWidth, double pressure) =>
    baseWidth * (0.1 + 3.6 * pressure * pressure);
