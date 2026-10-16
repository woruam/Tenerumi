import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/widgets/page_scrollbar.dart';
import 'package:xournalpp/widgets/virtual_page_column.dart';

import 'pomodoro_appearance_test.dart' show capture;

void main() {
  test('page navigation preferences survive controller recreation', () async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController();
    await theme.load();
    expect(theme.showPageScrollbar, isTrue);
    await theme.setPageScrollbar(false);
    await theme.setCurrentPageBorderColor(Colors.blue);
    final restored = ThemeController();
    await restored.load();
    expect(restored.showPageScrollbar, isFalse);
    expect(restored.currentPageBorderColor.toARGB32(), Colors.blue.toARGB32());
    theme.dispose();
    restored.dispose();
  });

  testWidgets(
    'rail drag reaches both ends without changing zoom or horizontal pan',
    (tester) async {
      final transform = TransformationController()
        ..value = (Matrix4.identity()
          ..translateByDouble(-40, 0, 0, 1)
          ..scaleByDouble(2, 2, 1, 1));
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topRight,
            child: PageScrollbar(
              transform: transform,
              viewport: const Size(400, 600),
              sceneHeight: 5000,
              currentPage: 0,
              pageCount: 10,
            ),
          ),
        ),
      );
      final rail = find.byKey(const ValueKey('page-scrollbar'));
      await tester.drag(rail, const Offset(0, 550));
      await tester.pump();
      expect(transform.value.entry(1, 3), closeTo(-9400, .01));
      expect(transform.value.entry(0, 3), -40);
      expect(transform.value.getMaxScaleOnAxis(), 2);
      await tester.drag(rail, const Offset(0, -550));
      await tester.pump();
      expect(transform.value.entry(1, 3), closeTo(0, .01));
      await tester.pumpWidget(const SizedBox());
      transform.dispose();
    },
  );

  testWidgets(
    'current outline follows page within same mounted range and stays one screen pixel',
    (tester) async {
      final transform = TransformationController();
      final imageKey = GlobalKey();
      int current = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: imageKey,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topLeft,
                child: VirtualPageColumn(
                  transform: transform,
                  viewport: const Size(400, 400),
                  width: 368,
                  heights: const [400, 400],
                  currentPageBorderColor: Colors.red,
                  onCurrentPage: (page) => current = page,
                  pageBuilder: (index) => ColoredBox(
                    color: Colors.white,
                    child: Center(child: Text('Pagina ${index + 1}')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      Finder border = find.byKey(const ValueKey('current-page-border'));
      expect(
        find.ancestor(of: border, matching: find.byKey(const ValueKey(0))),
        findsOneWidget,
      );
      transform.value = Matrix4.translationValues(0, -350, 0);
      await tester.pump();
      expect(current, 1);
      expect(
        find.ancestor(of: border, matching: find.byKey(const ValueKey(1))),
        findsOneWidget,
      );
      transform.value = Matrix4.identity()..scaleByDouble(2.5, 2.5, 1, 1);
      await tester.pump();
      final decoration =
          tester.widget<DecoratedBox>(border).decoration as BoxDecoration;
      expect((decoration.border! as Border).top.width, closeTo(.4, .001));
      await capture(tester, imageKey, 'experience-page-outline');
      await tester.pumpWidget(const SizedBox());
      transform.dispose();
    },
  );
}
