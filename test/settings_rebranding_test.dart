import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/app_brand.dart';
import 'package:xournalpp/src/app_appearance.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/app_info_dialog.dart';

Future<void> mount(WidgetTester tester, ThemeController theme) =>
    tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: AppAppearance.buildTheme(theme, null),
          home: const OpenPage(restoreWorkspace: false),
        ),
      ),
    );

Future<void> settings(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
}

Future<void> section(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: AppBrand.name,
      packageName: 'online.xournal.mobile',
      version: '0.5.0',
      buildNumber: '31',
      buildSignature: '',
    );
  });

  for (final size in [const Size(380, 800), const Size(1000, 720)]) {
    testWidgets(
      'settings begin collapsed and retain changes after closing a section at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final theme = ThemeController();
        await mount(tester, theme);
        await tester.pumpAndSettle();
        expect(find.text(AppBrand.name), findsOneWidget);
        final image = tester
            .widgetList<Image>(find.byType(Image))
            .where((i) => i.image is ResizeImage);
        expect(image, isNotEmpty);
        await settings(tester);
        expect(find.text('Impostazioni'), findsOneWidget);
        for (final id in ['appearance', 'pen', 'pages', 'about']) {
          expect(find.byKey(ValueKey('settings-section-$id')), findsOneWidget);
        }
        expect(
          find.byKey(const ValueKey('stylus-profile-setting')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('page-scrollbar-setting')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('stylus-menu-settings')),
          findsNothing,
        );

        await section(tester, 'Penna e gesti');
        expect(
          find.byKey(const ValueKey('stylus-profile-setting')),
          findsOneWidget,
        );
        final touch = find.widgetWithText(
          SwitchListTile,
          'Disegna con le dita',
        );
        await tester.ensureVisible(touch);
        await tester.tap(touch);
        await tester.pumpAndSettle();
        expect(
          (await SharedPreferences.getInstance()).getBool(
            PreferencesKeys.kTouchDrawing,
          ),
          isTrue,
        );
        await section(tester, 'Penna e gesti');
        expect(
          find.byKey(const ValueKey('stylus-profile-setting')),
          findsNothing,
        );
        await section(tester, 'Penna e gesti');
        expect(tester.widget<SwitchListTile>(touch).value, isTrue);
        await section(tester, 'Penna e gesti');

        await section(tester, 'Pagine e navigazione');
        final scrollbar = find.byKey(const ValueKey('page-scrollbar-setting'));
        await tester.ensureVisible(scrollbar);
        await tester.tap(scrollbar);
        await tester.pumpAndSettle();
        expect(theme.showPageScrollbar, isFalse);
        await section(tester, 'Pagine e navigazione');
        await section(tester, 'Pagine e navigazione');
        expect(tester.widget<SwitchListTile>(scrollbar).value, isFalse);
        await tester.tap(find.text('Chiudi'));
        await tester.pumpAndSettle();
        await settings(tester);
        expect(
          find.byKey(const ValueKey('page-scrollbar-setting')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        theme.dispose();
      },
    );
  }

  testWidgets('theme and radial menu are reachable from their sections', (
    tester,
  ) async {
    final theme = ThemeController();
    await mount(tester, theme);
    await tester.pumpAndSettle();
    await settings(tester);
    await section(tester, 'Aspetto');
    final dynamic = find.widgetWithText(
      SwitchListTile,
      'Colori dinamici (Material You)',
    );
    await tester.ensureVisible(dynamic);
    await tester.tap(dynamic);
    await tester.pumpAndSettle();
    expect(theme.useDynamicColor, isFalse);
    await section(tester, 'Aspetto');
    await section(tester, 'Penna e gesti');
    final menu = find.byKey(const ValueKey('stylus-menu-settings'));
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('stylus-menu-hold-delay')),
      findsOneWidget,
    );
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(find.text('Impostazioni'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    theme.dispose();
  });

  testWidgets(
    'Tenerumi information preserves version and upstream attribution',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showTenerumiAppInfo(context),
                child: const Text('Info'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Info'));
      await tester.pumpAndSettle();
      expect(find.text(AppBrand.name), findsOneWidget);
      expect(find.text('Versione 0.5'), findsOneWidget);
      expect(find.textContaining('Basata su Xournal++ Mobile'), findsOneWidget);
      expect(find.textContaining('EUPL-1.2'), findsOneWidget);
      expect(find.text('OSI'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
