import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/src/note_tags.dart';
import 'package:xournalpp/src/critical_data.dart';
import 'package:xournalpp/src/recent_documents.dart';
import 'package:xournalpp/widgets/note_tag_picker.dart';

import 'pomodoro_appearance_test.dart' show capture;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'custom tags persist, include legacy categories and avoid duplicates',
    () async {
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode([
          {'name': 'Vecchio', 'path': '/old.xopp', 'tag': 'Università'},
        ]),
      });
      expect(await NoteTags.load(), [...NoteTags.defaults, 'Università']);
      expect(await NoteTags.create('  Esami   2026  '), 'Esami 2026');
      expect(await NoteTags.create('esami 2026'), 'Esami 2026');
      expect(await NoteTags.create('SCUOLA'), 'Scuola');
      expect(
        (await NoteTags.load()).where((tag) => tag == 'Esami 2026'),
        hasLength(1),
      );
      expect(
        await CriticalData.read(PreferencesKeys.kNoteTags),
        contains('Esami 2026'),
      );
      for (final invalid in ['', ' ', 'Tutti', 'tutti', 'x' * 41]) {
        await expectLater(NoteTags.create(invalid), throwsFormatException);
      }
    },
  );

  test('chosen tags cross snapshots, isolates and subsequent saves', () async {
    final file = XppFile.empty(title: 'Fisica', tag: 'Università & ricerca');
    final snapshot = file.snapshot();
    file.tag = 'Lavoro';
    expect(snapshot.tag, 'Università & ricerca');
    final parsed = await XppFile.fromFilePickerCross(
      FilePickerCross(
        await snapshot.serializeSnapshotAsync(),
        path: '/Fisica.xopp',
      ),
      null,
      (_) async => throw StateError('Unavailable'),
    );
    expect(parsed.tag, 'Università & ricerca');
    await RecentDocuments.save(parsed, '/Fisica.xopp');
    await RecentDocuments.setTag(
      (await RecentDocuments.list()).single,
      'Scuola',
    );
    final edited = (await RecentDocuments.list()).single;
    expect(edited['tag'], 'Scuola');
    parsed.tag = edited['tag'] as String;
    await RecentDocuments.save(parsed.snapshot(), '/Fisica.xopp');
    expect((await RecentDocuments.list()).single['tag'], 'Scuola');
  });

  testWidgets('phone creates and selects custom tags and opens OSI app info', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PackageInfo.setMockInitialValues(
      appName: 'OSI',
      packageName: 'online.xournal.mobile',
      version: '0.5.0',
      buildNumber: '31',
      buildSignature: '',
    );
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
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const XournalppMobile()),
    );
    await tester.pumpAndSettle();
    expect(find.text('OSI'), findsOneWidget);
    await tester.tap(find.text('Nuovo Appunto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crea tag'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Università');
    await tester.tap(find.text('Crea'));
    await tester.pumpAndSettle();
    final picker = tester.widget<NoteTagPicker>(find.byType(NoteTagPicker));
    expect(picker.value, 'Università');
    expect(picker.tags, contains('Università'));
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'osi-new-note-tags');
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    // Canceling the note does not lose the newly created catalog entry.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const XournalppMobile()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Università'), findsOneWidget);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Info App'));
    await tester.pumpAndSettle();
    expect(find.text('Versione 0.5'), findsOneWidget);
    expect(find.text('Build 31'), findsOneWidget);
    expect(find.text('OSI'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'osi-app-info');
    await tester.pumpWidget(const SizedBox());
  });
}
