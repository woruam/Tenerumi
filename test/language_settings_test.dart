import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/l10n/app_localizations.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/app_brand.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('ThemeController language state and persistence', () {
    test('defaults to English when uninitialized', () {
      final theme = ThemeController();
      expect(theme.languageCode, 'en');
      expect(theme.locale, const Locale('en'));
      expect(theme.isItalian, isFalse);
    });

    test('loads default English when SharedPreferences is empty', () async {
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeController();
      await theme.load();
      expect(theme.languageCode, 'en');
      expect(theme.locale, const Locale('en'));
      expect(theme.isItalian, isFalse);
    });

    test('restores Italian preference from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        ThemeController.kLanguageKey: 'it',
      });
      final theme = ThemeController();
      await theme.load();
      expect(theme.languageCode, 'it');
      expect(theme.locale, const Locale('it'));
      expect(theme.isItalian, isTrue);
    });

    test('setLanguage changes state, notifies listeners and saves to prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeController();
      var notifyCount = 0;
      theme.addListener(() => notifyCount++);

      await theme.setLanguage('it');
      expect(theme.languageCode, 'it');
      expect(theme.locale, const Locale('it'));
      expect(theme.isItalian, isTrue);
      expect(notifyCount, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ThemeController.kLanguageKey), 'it');

      // Invalid code does nothing
      await theme.setLanguage('fr');
      expect(theme.languageCode, 'it');
      expect(notifyCount, 1);

      // Switching back to English
      await theme.setLanguage('en');
      expect(theme.languageCode, 'en');
      expect(theme.locale, const Locale('en'));
      expect(theme.isItalian, isFalse);
      expect(notifyCount, 2);
      expect(prefs.getString(ThemeController.kLanguageKey), 'en');
    });
  });

  group('AppLocalizations unit tests', () {
    test('supports en and it locales', () {
      expect(
        AppLocalizations.supportedLocales.map((l) => l.languageCode),
        containsAll(['en', 'it']),
      );
    });

    test('provides English and Italian translations for common and settings terms', () {
      const en = AppLocalizations(Locale('en'));
      const it = AppLocalizations(Locale('it'));

      expect(en.settings, 'Settings');
      expect(it.settings, 'Impostazioni');

      expect(en.languageSectionTitle, 'Language');
      expect(it.languageSectionTitle, 'Lingua');

      expect(en.languageEnglish, 'English');
      expect(it.languageItalian, 'Italiano');

      expect(en.newNote, 'New Note');
      expect(it.newNote, 'Nuovo Appunto');

      expect(en.noDocumentsHere, 'No documents here');
      expect(it.noDocumentsHere, 'Nessun documento qui');

      expect(en.appearance, 'Appearance');
      expect(it.appearance, 'Aspetto');

      expect(en.penAndGestures, 'Pen and gestures');
      expect(it.penAndGestures, 'Penna e gesti');

      expect(en.pagesAndNavigation, 'Pages and navigation');
      expect(it.pagesAndNavigation, 'Pagine e navigazione');

      expect(en.aboutTenerumi, 'About Tenerumi');
      expect(it.aboutTenerumi, 'Informazioni su Tenerumi');
    });
  });

  group('Settings UI Language Switcher', () {
    testWidgets('defaults to English and allows switching dynamically to Italian and back', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final theme = ThemeController();
      await theme.load();

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: const XournalppMobile(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Check default English UI on OpenPage / Library
      expect(find.text('No documents here'), findsOneWidget);
      expect(find.text('New Note'), findsOneWidget);
      expect(find.text('Open file'), findsOneWidget);

      // 2. Open Settings
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);

      // Expand the Language section
      await tester.ensureVisible(find.text('Language'));
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();

      expect(find.text('English'), findsOneWidget);
      expect(find.text('Italiano'), findsOneWidget);

      // 3. Switch to Italian
      await tester.tap(find.byKey(const ValueKey('language-option-it')));
      await tester.pumpAndSettle();

      // Immediately reflected in settings dialog
      expect(find.text('Impostazioni'), findsOneWidget);
      expect(find.text('Lingua'), findsOneWidget);
      final activeTheme = Provider.of<ThemeController>(
        tester.element(find.byType(OpenPage)),
        listen: false,
      );
      expect(activeTheme.languageCode, 'it');

      // Preference persisted
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ThemeController.kLanguageKey), 'it');

      // 4. Close settings dialog
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();

      // Library now displays Italian
      expect(find.text('Nessun documento qui'), findsOneWidget);
      expect(find.text('Nuovo Appunto'), findsOneWidget);
      expect(find.text('Apri file'), findsOneWidget);

      // 5. Open settings again and switch back to English
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Impostazioni'), findsOneWidget);
      // Expand the Lingua section
      await tester.ensureVisible(find.text('Lingua'));
      await tester.tap(find.text('Lingua'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('language-option-en')));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(activeTheme.languageCode, 'en');
      expect(prefs.getString(ThemeController.kLanguageKey), 'en');

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('No documents here'), findsOneWidget);
      expect(find.text('New Note'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      theme.dispose();
    });
  });
}
