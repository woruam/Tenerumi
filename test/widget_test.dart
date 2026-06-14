import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const XournalppMobile());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Xournal++'), findsWidgets);
  });
}
