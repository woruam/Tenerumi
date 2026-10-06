import 'package:flutter/material.dart';

class XppPageSize {
  final double width;
  final double height;

  XppPageSize({required this.width, required this.height});

  double get ratio => width / height;

  static XppPageSize get a4 => XppPageSize(width: 595.28, height: 841.89);

  Size toSize() => Size(width, height);

  static double pt2mm(double pt) => pt * 0.352778;
}
