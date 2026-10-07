import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/OpenPage.dart';

void main() {
  testWidgets('App opens the document hub with an empty library', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const XournalppMobile());
    await tester.pumpAndSettle();
    expect(find.byType(OpenPage), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Nessun documento qui'), findsOneWidget);
    final textTheme = Theme.of(tester.element(find.byType(OpenPage))).textTheme;
    final defaultTheme = ThemeData.dark();
    final baseTextTheme = defaultTheme.typography.englishLike.merge(
      defaultTheme.textTheme,
    );
    for (final style in [
      textTheme.titleSmall,
      textTheme.bodyLarge,
      textTheme.bodyMedium,
      textTheme.bodySmall,
      textTheme.labelLarge,
      textTheme.labelMedium,
      textTheme.labelSmall,
    ]) {
      expect(style!.fontFamily, startsWith('Inter'));
    }
    for (final style in [
      textTheme.displayLarge,
      textTheme.displayMedium,
      textTheme.displaySmall,
      textTheme.headlineLarge,
      textTheme.headlineMedium,
      textTheme.headlineSmall,
      textTheme.titleLarge,
      textTheme.titleMedium,
    ]) {
      expect(style!.fontFamily, startsWith('VT323'));
    }
    expect(textTheme.bodyMedium!.fontSize, baseTextTheme.bodyMedium!.fontSize);
    expect(
      textTheme.titleLarge!.fontWeight,
      baseTextTheme.titleLarge!.fontWeight,
    );
    expect(tester.takeException(), isNull);
  });
}
