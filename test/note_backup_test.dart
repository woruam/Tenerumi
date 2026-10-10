import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/autosave_store.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/compat/internal_storage_generic.dart'
    as web_storage;
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/src/note_audio.dart';
import 'package:xournalpp/src/note_backup.dart';
import 'package:xournalpp/src/note_flashcards.dart';
import 'package:xournalpp/src/note_tags.dart';
import 'package:xournalpp/src/critical_data.dart';
import 'package:xournalpp/src/recent_documents.dart';

import 'document_storage_test.dart' show TestDocumentsProvider;

XppFile note(String title) => XppFile.empty(title: title, tag: 'Università')
  ..pages!.first.layers!.first.content!.add(
    XppText(
      text: title,
      offset: const Offset(10, 10),
      size: 16,
      color: Colors.black,
    ),
  );

Future<void> saveNote(XppFile file, String path) async {
  file.sourcePath = path;
  await File(path).writeAsBytes(await file.toUint8ListAsync());
  await RecentDocuments.save(file, path);
}

class _FailingProvider extends TestDocumentsProvider {
  int calls = 0;
  _FailingProvider(super.path);
  @override
  Future<String?> getApplicationDocumentsPath() async {
    if (++calls > 2) throw const FileSystemException('Disk unavailable');
    return super.getApplicationDocumentsPath();
  }
}

Uint8List zip(List<ArchiveFile> files) {
  final a = Archive();
  for (final f in files) {
    a.add(f);
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(a));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('complete backup transfers portable notes, latest recovery and metadata to another device', () async {
    final originalProvider = PathProviderPlatform.instance;
    final deviceA = await Directory.systemTemp.createTemp('osi-backup-source-');
    final deviceB = await Directory.systemTemp.createTemp('osi-backup-target-');
    addTearDown(() async {
      PathProviderPlatform.instance = originalProvider;
      if (await deviceA.exists()) await deviceA.delete(recursive: true);
      await deviceB.delete(recursive: true);
    });
    PathProviderPlatform.instance = TestDocumentsProvider(deviceA.path);
    final a = note('Lezione');
    a.pages!.first.background = XppBackgroundPdf(
      filename: 'paper.pdf',
      page: 0,
      onUnavailable: (_) async => throw StateError('Missing PDF'),
    );
    final pdf = Uint8List.fromList([37, 80, 68, 70, 45, 49]);
    await File('${deviceA.path}/paper.pdf').writeAsBytes(pdf);
    a.attachSelectedBackground('paper.pdf', FilePickerCross(pdf));
    a.recordings['audio-1'] = NoteRecording(
      'audio-1',
      1000,
      Uint8List.fromList([1, 2, 3]),
    );
    a.flashcards['card-1'] = NoteFlashcard(
      id: 'card-1',
      front: FlashcardSide(text: 'Titolo'),
      back: FlashcardSide(text: 'Risposta'),
    );
    await saveNote(a, '${deviceA.path}/a.xopp');
    final b = note('Lezione');
    b.pages!.first.layers!.first.content!.add(
      XppImage(
        data: Uint8List.fromList(kTransparentImage),
        topLeft: const Offset(20, 40),
        bottomRight: const Offset(50, 70),
      ),
    );
    await saveNote(b, '${deviceA.path}/b.xopp');
    a.modifiedAt = a.modifiedAt!.add(const Duration(minutes: 1));
    (a.pages!.first.layers!.first.content!.single as XppText).text =
        'Ultima modifica';
    await AutosaveStore.save(a, await a.toUint8ListAsync());
    final unsaved = note('Non ancora salvato');
    await AutosaveStore.save(unsaved, await unsaved.toUint8ListAsync());

    final entries = await RecentDocuments.list();
    entries.first['favorite'] = true;
    await CriticalData.write(PreferencesKeys.kRecentFiles, entries);
    await NoteTags.create('Esami');
    final prepared = await NoteBackup.create();
    expect(prepared.count, 4);
    expect(prepared.unavailable, isEmpty);
    await deviceA.delete(recursive: true);

    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = TestDocumentsProvider(deviceB.path);
    final existing = note('Appunto presente');
    await saveNote(existing, '${deviceB.path}/existing.xopp');
    final existingBytes = await File(existing.sourcePath!).readAsBytes();
    final backup = await NoteBackup.inspect(prepared.bytes);
    expect(backup.notes, hasLength(4));
    expect(backup.tags, contains('Esami'));
    expect(await NoteBackup.restore(backup), 4);
    final restoredEntries = await RecentDocuments.list();
    expect(restoredEntries, hasLength(5));
    final restoredA = restoredEntries
        .where((e) => e['favorite'] == true)
        .single;
    expect(restoredA['tag'], 'Università');
    expect(restoredA['id'], isNot(a.documentId));
    final reopened = await XppFile.fromFilePickerCross(
      await FilePickerCross.fromInternalPath(path: restoredA['path'] as String),
      null,
      (_) async => throw StateError('Missing PDF'),
    );
    expect(reopened.pdfAttachments['paper.pdf'], pdf);
    expect(reopened.recordings['audio-1']!.bytes, [1, 2, 3]);
    expect(reopened.flashcards['card-1']!.back.text, 'Risposta');
    final restoredB = restoredEntries
        .where((e) => e['name'] == 'Lezione' && e['favorite'] == false)
        .single;
    final reopenedB = await XppFile.fromFilePickerCross(
      await FilePickerCross.fromInternalPath(path: restoredB['path'] as String),
      null,
      (_) async => throw StateError('Missing'),
    );
    expect(
      reopenedB.pages!.first.layers!.first.content!
          .whereType<XppImage>()
          .single
          .data,
      kTransparentImage,
    );
    expect(
      (reopened.pages!.first.layers!.first.content!.single as XppText).text,
      'Lezione',
    );
    final recoveryEntry = restoredEntries
        .where((e) => e['name'] == 'Lezione (recupero)')
        .single;
    final recoveryFile = await XppFile.fromFilePickerCross(
      await FilePickerCross.fromInternalPath(
        path: recoveryEntry['path'] as String,
      ),
      null,
      (_) async => throw StateError('Missing'),
    );
    expect(
      (recoveryFile.pages!.first.layers!.first.content!.single as XppText).text,
      'Ultima modifica',
    );
    expect(await File(existing.sourcePath!).readAsBytes(), existingBytes);
    expect(await NoteTags.load(), contains('Esami'));
    // Repeated restoration creates independent copies rather than overwriting.
    await NoteBackup.restore(backup);
    final all = await RecentDocuments.list();
    expect(all, hasLength(9));
    expect(all.map((e) => e['path']).toSet(), hasLength(9));
    expect(all.map((e) => e['id']).toSet(), hasLength(9));
  });

  test(
    'missing documents and missing backgrounds are explicitly reported',
    () async {
      final originalProvider = PathProviderPlatform.instance;
      final dir = await Directory.systemTemp.createTemp('osi-partial-backup-');
      PathProviderPlatform.instance = TestDocumentsProvider(dir.path);
      addTearDown(() async {
        PathProviderPlatform.instance = originalProvider;
        await dir.delete(recursive: true);
      });
      final valid = note('Disponibile');
      await saveNote(valid, '${dir.path}/valid.xopp');
      final broken = note('PDF mancante');
      broken.pages!.first.background = XppBackgroundPdf(
        filename: 'missing.pdf',
        page: 0,
        onUnavailable: (_) async => throw StateError('Missing'),
      );
      await saveNote(broken, '${dir.path}/broken.xopp');
      await RecentDocuments.save(
        note('File mancante'),
        '${dir.path}/missing.xopp',
      );
      final backup = await NoteBackup.create();
      expect(backup.count, 1);
      expect(backup.unavailable, hasLength(2));
      expect(backup.unavailable.join(' '), contains('PDF mancante'));
      expect(backup.unavailable.join(' '), contains('File mancante'));
    },
  );

  test(
    'invalid archives and path traversal are rejected before any import',
    () async {
      await expectLater(
        NoteBackup.inspect(Uint8List.fromList([1, 2, 3])),
        throwsA(anything),
      );
      final bytes = utf8.encode('{}');
      final malicious = zip([
        ArchiveFile('../outside.xopp', bytes.length, bytes),
      ]);
      await expectLater(NoteBackup.inspect(malicious), throwsFormatException);
      final wrong = zip([ArchiveFile('manifest.json', bytes.length, bytes)]);
      await expectLater(NoteBackup.inspect(wrong), throwsFormatException);
      expect(await RecentDocuments.list(), isEmpty);
    },
  );

  test(
    'CRC verification rejects a damaged payload without importing anything',
    () async {
      final bytes = await NoteBackup.encode([BackupNote(note('Appunto'))]);
      final damaged = Uint8List.fromList(bytes);
      var changed = false;
      for (var i = 0; i < damaged.length - 3; i++) {
        if (damaged[i] == 31 && damaged[i + 1] == 139 && damaged[i + 2] == 8) {
          damaged[i + 2] = 7;
          changed = true;
          break;
        }
      }
      expect(changed, isTrue);
      await expectLater(NoteBackup.inspect(damaged), throwsFormatException);
      expect(await RecentDocuments.list(), isEmpty);
    },
  );

  test('a malformed note makes the entire archive fail validation', () async {
    final valid = await NoteBackup.encode([
      BackupNote(note('Valido')),
      BackupNote(note('Guasto')),
    ]);
    final archive = ZipDecoder().decodeBytes(valid);
    final files = [
      for (final f in archive)
        if (f.name != 'notes/1.xopp')
          ArchiveFile(f.name, f.size, f.readBytes()!)
        else
          ArchiveFile(f.name, 3, [1, 2, 3]),
    ];
    await expectLater(NoteBackup.inspect(zip(files)), throwsA(anything));
    expect(await RecentDocuments.list(), isEmpty);
  });

  test('failure during restoration removes staged files and preserves existing library', () async {
    final originalProvider = PathProviderPlatform.instance;
    final dir = await Directory.systemTemp.createTemp('osi-backup-rollback-');
    addTearDown(() async {
      PathProviderPlatform.instance = originalProvider;
      await dir.delete(recursive: true);
    });
    PathProviderPlatform.instance = TestDocumentsProvider(dir.path);
    final existing = note('Esistente');
    await saveNote(existing, '${dir.path}/existing.xopp');
    final before = await RecentDocuments.list();
    final backup = BackupContents(
      [BackupNote(note('Uno')), BackupNote(note('Due'))],
      [],
      null,
    );
    PathProviderPlatform.instance = _FailingProvider(dir.path);
    await expectLater(NoteBackup.restore(backup), throwsA(anything));
    PathProviderPlatform.instance = TestDocumentsProvider(dir.path);
    expect(await RecentDocuments.list(), before);
    expect(await File(existing.sourcePath!).exists(), isTrue);
    final staged = await Directory('${dir.path}/xournalpp').list().toList();
    expect(staged, isEmpty);
  });

  test(
    'browser storage persists restored notes and deletion removes them',
    () async {
      const path = 'backup-browser-test.xopp';
      final bytes = Uint8List.fromList([1, 2, 3]);
      await web_storage.writeFile(path, bytes);
      expect(await web_storage.exists(path), isTrue);
      expect(
        await CriticalData.read('osipp.web-restored.$path'),
        isA<String>(),
      );
      expect(await web_storage.readFile(path), bytes);
      await web_storage.deleteFile(path);
      expect(await web_storage.exists(path), isFalse);
    },
  );

  testWidgets(
    'app settings expose Ripristina Backup and Crea Backup on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const XournalppMobile());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Crea Backup'), findsOneWidget);
      expect(find.text('Ripristina Backup'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('restore-backup')));
      await tester.pumpAndSettle();
      expect(find.text('Scegli backup'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crea Backup'));
      await tester.pumpAndSettle();
      expect(find.text('Prepara backup'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
