import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/autosave_store.dart';
import 'package:xournalpp/src/critical_data.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/compat/internal_storage_io.dart' as storage;
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/src/note_flashcards.dart';
import 'package:xournalpp/src/recent_documents.dart';
import 'package:xournalpp/src/workspace_session.dart';

Future<FilePickerCross> unavailable(String? _) async =>
    throw StateError('Unavailable');
XppFile note(String title, String path) =>
    XppFile.empty(title: title)..sourcePath = path;
Future<XppFile> xml(String contents) => XppFile.fromFilePickerCross(
  FilePickerCross(
    Uint8List.fromList(GZipEncoder().encodeBytes(utf8.encode(contents))),
  ),
  null,
  unavailable,
);
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CriticalData.inMemoryForTests = false;
  });
  test(
    'A15 wrong preference types and damaged tag/recovery catalogs are isolated',
    () async {
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: true,
        WorkspaceSession.key: 42,
      });
      expect(await RecentDocuments.list(), isEmpty);
      expect(await WorkspaceSession.restore(), isNull);
      await CriticalData.write('dismissedRecoveries', {'invalid': true});
      expect(await AutosaveStore.list(), isEmpty);
      expect(await CriticalData.read('dismissedRecoveries'), isEmpty);
      expect(CriticalData.warnings, isNotEmpty);
    },
  );
  test('A06 duplicate portable IDs keep separate checkpoints and specific deletion', () async {
    final a = note('A', 'a.xopp');
    final b = XppFile(
      documentId: a.documentId,
      title: 'B',
      sourcePath: 'b.xopp',
      pages: a.snapshot().pages,
    );
    await AutosaveStore.save(a, a.toUint8List()!);
    await AutosaveStore.save(b, b.toUint8List()!);
    expect(await AutosaveStore.list(), hasLength(2));
    await AutosaveStore.remove(
      a.documentId,
    ); // Imported identity has no authority.
    expect(await AutosaveStore.list(), hasLength(2));
    await AutosaveStore.remove(a.recoveryKey);
    expect((await AutosaveStore.list()).single['source'], 'b.xopp');
  });
  test(
    'A07 complete orphan checkpoint reconstructs its missing index',
    () async {
      final file = note('Orfano', 'orphan.xopp');
      await AutosaveStore.save(file, file.toUint8List()!);
      await CriticalData.write(AutosaveStore.indexKey, []);
      final restored = await AutosaveStore.restore(
        (await AutosaveStore.list()).single,
      );
      expect(restored.title, 'Orfano');
      expect(restored.requiresSaveCopy, isTrue);
    },
  );
  test(
    'A07 corrupted latest commit falls back and preserves evidence',
    () async {
      await CriticalData.write('test', 'prima');
      await CriticalData.write('test', 'dopo');
      final dir = Directory(await storage.resolve('state-v2'));
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((e) => e.path.endsWith('.commit'))
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));
      await files.first.writeAsString('{truncated', flush: true);
      expect(await CriticalData.read('test'), 'prima');
      expect(
        dir.listSync().where((e) => e.path.endsWith('.quarantine')),
        isNotEmpty,
      );
    },
  );
  test(
    'A15 a damaged record does not hide good records and is quarantined',
    () async {
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode([
          {'name': 'Valido', 'path': 'note.xopp'},
          {'name': 'Bad', 'path': 7},
        ]),
      });
      final records = await RecentDocuments.list();
      expect(records.single['name'], 'Valido');
      expect(CriticalData.warnings, isNotEmpty);
      final dir = Directory(await storage.resolve('state-v2'));
      expect(
        dir.listSync().where((e) => e.path.endsWith('.quarantine')),
        isNotEmpty,
      );
    },
  );
  test('A15 truncated JSON stays intact in quarantine', () async {
    SharedPreferences.setMockInitialValues({AutosaveStore.indexKey: '[{"id":'});
    expect(await AutosaveStore.list(), isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString(AutosaveStore.indexKey),
      '[{"id":',
    );
    expect(CriticalData.warnings, isNotEmpty);
  });
  test('A10 unknown tool and future version require save as copy', () async {
    final file = await xml(
      '<xournal fileversion="9"><page width="100" height="100"><background type="solid" style="plain" color="white"/><layer><stroke tool="eraser" color="white" width="2">1 2 3 4</stroke><future/></layer></page></xournal>',
    );
    expect(file.requiresSaveCopy, isTrue);
    expect(file.importWarnings.length, greaterThanOrEqualTo(3));
    expect(file.snapshot().importWarnings, file.importWarnings);
  });
  test('A11 exact serialized byte boundary and edits are enforced', () {
    final card = NoteFlashcard(
      id: 'card',
      front: FlashcardSide(text: 'È & "'),
      back: FlashcardSide(text: 'Risposta'),
    );
    final bytes = utf8.encode(jsonEncode(card.toJson())).length;
    FlashcardLimits.validate([card], byteLimit: bytes);
    expect(
      () => FlashcardLimits.validate([card], byteLimit: bytes - 1),
      throwsFormatException,
    );
    expect(() => FlashcardLimits.validate([card, card]), throwsFormatException);
  });
  test('A11 optional corruption reports partial recovery', () async {
    final file = await xml(
      '<xournal><osipp-flashcard>{broken}</osipp-flashcard><page width="100" height="100"><layer/></page></xournal>',
    );
    expect(file.flashcards, isEmpty);
    expect(file.requiresSaveCopy, isTrue);
  });
  test(
    'A12 changed original and old recovery both survive workspace restore',
    () async {
      final path = await storage.resolve('source.xopp');
      final old = note('Nota', path)..modifiedAt = DateTime.utc(2020);
      await AutosaveStore.save(old, old.toUint8List()!);
      final original = note('Nota', path)..modifiedAt = DateTime.utc(2021);
      original.pages!.first.layers!.first.content!.add(
        XppText(
          text: 'Più recente',
          size: 12,
          color: Colors.black,
          offset: Offset.zero,
        ),
      );
      await File(path).writeAsBytes(original.toUint8List()!, flush: true);
      await WorkspaceSession.save({
        'tabs': [
          {
            'id': old.documentId,
            'key': old.recoveryKey,
            'path': path,
            'title': 'Nota',
          },
        ],
      });
      final restored = (await WorkspaceSession.restore())!;
      expect(restored.files, hasLength(2));
      expect(
        restored.files.first.pages!.first.layers!.first.content,
        hasLength(1),
      );
      expect(restored.files.last.requiresSaveCopy, isTrue);
      expect(restored.files.last.recovered, isTrue);
    },
  );
  test('A12 malformed tab does not abandon valid tabs', () async {
    await WorkspaceSession.save({
      'tabs': [
        7,
        {'blank': true, 'title': 'Valida'},
      ],
    });
    expect((await WorkspaceSession.restore())!.files.single.title, 'Valida');
  });
  test(
    'A10 protected import autosaves privately without rewriting origin',
    () async {
      final path = await storage.resolve('protected.xopp');
      final file = note('Protected', path)
        ..importWarnings.add('Unsupported node');
      await File(path).writeAsBytes([1, 2, 3]);
      final controller = CanvasController()
        ..init(file)
        ..hasUnsavedChanges = true;
      await controller.flushAutosave();
      expect(await File(path).readAsBytes(), [1, 2, 3]);
      expect(await AutosaveStore.list(), hasLength(1));
      await controller.discardRecovery();
      controller.dispose();
    },
  );
  testWidgets(
    'A05 manual save failure first secures a complete checkpoint even without autosave',
    (tester) async {
      final path = await tester.runAsync(() => storage.resolve('blocked'));
      await tester.runAsync(() => Directory(path!).create());
      final file = note('Latest', path!);
      file.pages!.first.layers!.first.content!.add(
        XppText(
          text: 'Ultimo contenuto',
          size: 12,
          color: Colors.black,
          offset: Offset.zero,
        ),
      );
      final controller = CanvasController(autosaveEnabled: false)
        ..init(file)
        ..hasUnsavedChanges = true;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final context = tester.element(find.byType(SizedBox).first);
      expect(
        await tester.runAsync(() => controller.saveFile(context)),
        isFalse,
      );
      final entries = await tester.runAsync(AutosaveStore.list);
      final restored = await tester.runAsync(
        () => AutosaveStore.restore(entries!.single),
      );
      expect(
        (restored!.pages!.first.layers!.first.content!.single as XppText).text,
        'Ultimo contenuto',
      );
      expect(controller.hasUnsavedChanges, isTrue);
      controller.dispose();
    },
  );
}
