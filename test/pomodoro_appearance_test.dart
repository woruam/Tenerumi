import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/app_appearance.dart';
import 'package:xournalpp/src/app_features.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/PomodoroTimer.dart';

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    const artifactPrefix = String.fromEnvironment(
      'OSI_TEST_ARTIFACT_PREFIX',
      defaultValue: 'experience-',
    );
    final filename = name.startsWith('experience-')
        ? '$artifactPrefix${name.substring('experience-'.length)}'
        : '$artifactPrefix$name';
    await File('docs/validation/$filename.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets(
    'Pomodoro theme fits phone library and settings without backdrop filtering',
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
      SharedPreferences.setMockInitialValues({
        'app_language': 'it',
        'osipp.builtin-plugins.v1': jsonEncode({'pomodoro': true}),
        PreferencesKeys.kRecentFiles: jsonEncode(
          List.generate(
            8,
            (i) => {
              'name': 'Appunti di lezione ${i + 1}',
              'path': '',
              'tag': 'Appunti',
              'modifiedAt': '2026-10-07T08:30:00Z',
            },
          ),
        ),
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: const XournalppMobile()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final theme = Theme.of(tester.element(find.byType(OpenPage)));
      expect(theme.colorScheme.primary, AppAppearance.accent);
      expect(theme.cardTheme.elevation, 0);
      await capture(tester, key, 'pomodoro-style-library');
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'pomodoro-style-settings');
      await tester.ensureVisible(find.text('Aspetto'));
      await tester.tap(find.text('Aspetto'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tonde'));
      await tester.tap(find.text('Tonde'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Linea'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appunti di lezione 1'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Pomodoro'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pomodoro'));
      await tester.pumpAndSettle();
      expect(find.byType(PomodoroTimer), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'pomodoro-style-workspace');
      await tester.tap(find.byIcon(Icons.play_arrow_outlined));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byIcon(Icons.pause_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.pause_outlined));
      await tester.pumpAndSettle();
      expect(find.text('25:00'), findsNothing);
      await tester.tap(find.byIcon(Icons.refresh_outlined));
      await tester.pumpAndSettle();
      expect(find.text('25:00'), findsOneWidget);
      // A second tap on the active pen opens its settings above the page.
      await tester.ensureVisible(find.byTooltip('Penna'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Penna'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'pomodoro-style-tool-menu');
      await tester.tapAt(const Offset(370, 700));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1100, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'pomodoro-style-desktop');
      await tester.pumpWidget(const SizedBox());
    },
    skip: !AppFeatures.plugins,
  );
}
