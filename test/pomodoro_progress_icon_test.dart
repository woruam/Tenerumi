import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/widgets/PomodoroTimer.dart';
import 'package:xournalpp/widgets/pomodoro_progress_icon.dart';

void main() {
  testWidgets(
    'running minimized timer fills icon and retains natural completion',
    (tester) async {
      SharedPreferences.setMockInitialValues({'pomodoro_work_min': 1});
      var now = DateTime(2026, 10, 16);
      final progress = ValueNotifier<double>(0);
      final minimized = ValueNotifier<bool>(false);
      final theme = ThemeController();
      var completions = 0;
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  PomodoroProgressIcon(progress: progress),
                  ValueListenableBuilder<bool>(
                    valueListenable: minimized,
                    builder: (_, hidden, _) => Offstage(
                      offstage: hidden,
                      child: PomodoroTimer(
                        progress: progress,
                        now: () => now,
                        onPhaseComplete: (_, _) => completions++,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(theme.icons.play));
      minimized.value = true;
      await tester.pump();
      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(milliseconds: 250));
      expect(progress.value, .5);
      expect(find.bySemanticsLabel('Pomodoro 50%'), findsOneWidget);
      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(milliseconds: 250));
      expect(completions, 1);
      expect(progress.value, 1);
      expect(find.bySemanticsLabel('Pomodoro 100%'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(progress.value, 1);
      await tester.pumpWidget(const SizedBox());
      progress.dispose();
      minimized.dispose();
      theme.dispose();
    },
  );

  testWidgets('Minimized tomato follows elapsed time and holds completion', (
    tester,
  ) async {
    final progress = ValueNotifier<double>(0);
    addTearDown(progress.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PomodoroProgressIcon(progress: progress)),
      ),
    );
    expect(find.bySemanticsLabel('Pomodoro 0%'), findsOneWidget);
    progress.value = .5;
    await tester.pump();
    expect(find.bySemanticsLabel('Pomodoro 50%'), findsOneWidget);
    progress.value = 1;
    await tester.pump();
    expect(find.bySemanticsLabel('Pomodoro 100%'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.bySemanticsLabel('Pomodoro 100%'), findsOneWidget);
  });
}
