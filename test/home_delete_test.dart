import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:ui' as ui;

import 'package:xournalpp/main.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/recent_documents.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/src/autosave_store.dart';

import 'pomodoro_appearance_test.dart' show capture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'delete removes only selected file/index/recovery; failure retains entry',
    () async {
      final dir = await Directory.systemTemp.createTemp('osi-delete-');
      addTearDown(() => dir.delete(recursive: true));
      final a = File('${dir.path}/a.xopp'),
          b = File('${dir.path}/b.xopp'),
          recovery = File('${dir.path}/recovery.xopp');
      await a.writeAsString('a');
      await b.writeAsString('b');
      await recovery.writeAsString('r');
      final selected = {
        'name': 'Stesso titolo',
        'path': a.path,
        'id': 'note-a',
      };
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode([
          selected,
          {'name': 'Stesso titolo', 'path': b.path},
        ]),
        AutosaveStore.indexKey: jsonEncode([
          {'id': 'note-a', 'path': recovery.path, 'time': 1},
        ]),
      });
      await expectLater(
        RecentDocuments.delete(
          selected,
          deleteFile: (_) async => throw FileSystemException('denied'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await a.exists(), true);
      expect(await RecentDocuments.list(), hasLength(2));
      await RecentDocuments.delete(selected);
      expect(await a.exists(), false);
      expect(await b.exists(), true);
      expect(await recovery.exists(), false);
      expect((await RecentDocuments.list()).single['path'], b.path);
      expect(await AutosaveStore.list(), isEmpty);
    },
  );
  test(
    'Android content URI deletion uses document provider and propagates denial',
    () async {
      const channel = MethodChannel('online.xournal.mobile/documents');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await FilePickerCross.delete(path: 'content://provider/document/1');
      expect(calls.single.method, 'delete');
      expect(calls.single.arguments, {'uri': 'content://provider/document/1'});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'document_access'),
          );
      await expectLater(
        FilePickerCross.delete(path: 'content://provider/document/1'),
        throwsA(isA<PlatformException>()),
      );
    },
  );
  testWidgets(
    'home long press shows actions; cancel preserves note; confirmation deletes it',
    (tester) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory dir;
      late File note;
      late String preview;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('osi-home-delete-');
        note = File('${dir.path}/note.xopp');
        await note.writeAsString('saved note');
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 10, 10),
          Paint()..color = Colors.white,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(10, 10);
        try {
          preview = base64Encode(
            (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
                .asUint8List(),
          );
        } finally {
          image.dispose();
          picture.dispose();
        }
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
      addTearDown(() => dir.delete(recursive: true));
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode([
          {
            'name': 'Nota da eliminare',
            'path': note.path,
            'tag': 'Appunti',
            'modifiedAt': '2026-10-08T00:00:00Z',
            'preview': preview,
          },
        ]),
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: const XournalppMobile()),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Nota da eliminare'));
      await tester.pumpAndSettle();
      expect(find.text('Cambia tag'), findsOneWidget);
      expect(find.text('Elimina'), findsOneWidget);
      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();
      expect(find.text('Eliminare l’appunto?'), findsOneWidget);
      await capture(tester, key, 'home-delete-confirmation');
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(note.exists), true);
      expect(find.text('Nota da eliminare'), findsOneWidget);
      await tester.longPress(find.text('Nota da eliminare'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Elimina'));
      for (
        var i = 0;
        i < 40 && find.text('Nota da eliminare').evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      expect(await tester.runAsync(note.exists), false);
      expect(find.text('Nota da eliminare'), findsNothing);
      expect(find.text('Nessun documento qui'), findsOneWidget);
      expect(await RecentDocuments.list(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
