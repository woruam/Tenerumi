import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as material_ui;
import 'package:xournalpp/src/dynamic_color_adapter.dart';

void main() {
  test('dynamic palette preserves Flutter theme roles and fallback', () {
    expect(flutterColorScheme(null), isNull);
    for (final brightness in Brightness.values) {
      final palette = material_ui.ColorScheme.fromSeed(
          seedColor: Colors.cyan, brightness: brightness);
      final converted = flutterColorScheme(palette)!;
      expect(converted.brightness, brightness);
      expect(converted.primary, palette.primary);
      expect(converted.onPrimary, palette.onPrimary);
      expect(
          converted.surfaceContainerHighest, palette.surfaceContainerHighest);
      expect(converted.onSurface, palette.onSurface);
      expect(converted.error, palette.error);
      expect(converted.tertiaryFixed, palette.tertiaryFixed);
    }
  });
}
