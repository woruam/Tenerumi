import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/OpenPage.dart';

void main() {
  testWidgets('App opens the document hub with an empty library',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const XournalppMobile());
    await tester.pumpAndSettle();
    expect(find.byType(OpenPage), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Nessun documento qui'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
