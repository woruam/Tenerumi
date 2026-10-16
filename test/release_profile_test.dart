import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';
import 'package:xournalpp/src/app_features.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/PomodoroTimer.dart';

import 'pomodoro_appearance_test.dart' show capture;

void main() {
  test('unfinished features require an explicit compile-time opt in', () {
    expect(
      AppFeatures.plugins,
      const bool.fromEnvironment('OSI_ENABLE_PLUGINS', defaultValue: false),
    );
    expect(
      AppFeatures.manualBackup,
      const bool.fromEnvironment('OSI_ENABLE_BACKUP', defaultValue: false),
    );
  });

  testWidgets(
    'release profile gates plugin startup, settings and saved Pomodoro',
    (tester) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        for (final font in {
          'VT323': 'fonts/VT323/VT323-Regular.ttf',
          'Inter': 'fonts/Inter/Inter-Variable.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          await (FontLoader(
            font.key,
          )..addFont(rootBundle.load(font.value))).load();
        }
      });
      final legacyBuiltIns = jsonEncode({'pomodoro': true, 'anki': true});
      // Invalid stored plugins would produce a load error if a controller loaded
      // them; public startup must never create that controller in the first place.
      const legacyPlugins = 'invalid legacy plugin archive';
      SharedPreferences.setMockInitialValues({
        PluginController.builtInKey: legacyBuiltIns,
        PluginController.storageKey: legacyPlugins,
        PreferencesKeys.kRecentFiles: jsonEncode([
          {'name': 'Nota profilo', 'path': '', 'tag': 'Appunti'},
        ]),
      });
      final screenshotKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: screenshotKey, child: const XournalppMobile()),
      );
      await tester.pumpAndSettle();
      final library = tester.element(find.byType(OpenPage));
      final plugins = library.read<PluginController?>();
      if (AppFeatures.plugins) {
        expect(plugins, isNotNull);
        expect(plugins!.pomodoroEnabled, isTrue);
        expect(plugins.loadErrors, isNotEmpty);
        expect(find.byTooltip('Plugin'), findsOneWidget);
      } else {
        expect(plugins, isNull);
        expect(find.byTooltip('Plugin'), findsNothing);
        await capture(tester, screenshotKey, 'public-library');
      }

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      final backupMatcher = AppFeatures.manualBackup
          ? findsOneWidget
          : findsNothing;
      expect(find.text('Crea Backup'), backupMatcher);
      expect(find.text('Ripristina Backup'), backupMatcher);
      if (!AppFeatures.manualBackup) {
        await capture(tester, screenshotKey, 'public-settings');
      }
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nota profilo'));
      await tester.pumpAndSettle();
      final pomodoro = find.byTooltip('Pomodoro');
      if (AppFeatures.plugins) {
        expect(pomodoro, findsOneWidget);
        await tester.ensureVisible(pomodoro);
        await tester.tap(pomodoro);
        await tester.pumpAndSettle();
        expect(find.byType(PomodoroTimer), findsOneWidget);
      } else {
        expect(pomodoro, findsNothing);
        expect(find.byType(PomodoroTimer), findsNothing);
        expect(find.byTooltip('Flashcard: doppia selezione'), findsNothing);
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PluginController.builtInKey), legacyBuiltIns);
      expect(prefs.getString(PluginController.storageKey), legacyPlugins);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
