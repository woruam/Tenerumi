import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/backup_document.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/critical_data.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/src/note_audio.dart';
import 'package:xournalpp/src/note_backup.dart';
import 'package:xournalpp/src/note_tags.dart';
import 'package:xournalpp/src/recent_documents.dart';

import 'document_storage_test.dart' show TestDocumentsProvider;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('copy changes identity and escaped tag while preserving the XML body', () async {
    const body =
        '<future-data a="é">未知</future-data><page><layer /></page></xournal>';
    const prefix = '\uFEFF<?xml version="1.0"?><!-- <xournal fake="yes"> -->';
    final input = Uint8List.fromList(
      gzip.encode(
        utf8.encode(
          '$prefix<xournal osipp-id="old" osipp-tag="old" other="a&gt;b">$body',
        ),
      ),
    );
    final output = await copyBackupDocument(
      input,
      documentId: 'new',
      tag: 'Università & "Esami"',
    );
    final xml = utf8.decode(gzip.decode(output));
    expect(xml, startsWith(prefix.substring(1)));
    expect(gzip.decode(output).take(3), [239, 187, 191]);
    expect(xml, endsWith(body));
    final root = XmlDocument.parse(xml).rootElement;
    expect(root.getAttribute('osipp-id'), 'new');
    expect(root.getAttribute('osipp-tag'), 'Università & "Esami"');
    expect(root.getAttribute('other'), 'a>b');
    final withoutTag = utf8.decode(
      gzip.decode(
        await copyBackupDocument(output, documentId: 'third', tag: null),
      ),
    );
    expect(
      XmlDocument.parse(withoutTag).rootElement.getAttribute('osipp-tag'),
      isNull,
    );
    final damaged = Uint8List.fromList(input)..[input.length - 8] ^= 1;
    await expectLater(
      copyBackupDocument(damaged, documentId: 'x', tag: null),
      throwsFormatException,
    );
  });

  test('disk backup restores independent copies with tags, audio and stroke timing', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = PathProviderPlatform.instance;
    final directory = await Directory.systemTemp.createTemp(
      'tenerumi-backup-integrity-',
    );
    addTearDown(() async {
      PathProviderPlatform.instance = provider;
      final path = directory.absolute.path;
      expect(
        path.startsWith(
          '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
        ),
        isTrue,
      );
      await directory.delete(recursive: true);
    });
    PathProviderPlatform.instance = TestDocumentsProvider(directory.path);
    final file = XppFile.empty(title: 'Lezione', tag: 'Embedded tag');
    file.recordings['lecture'] = NoteRecording(
      'lecture',
      2000,
      Uint8List.fromList([1, 2, 3, 4]),
    );
    file.pages!.first.layers!.first.content!.add(
      XppStrokePen(
        color: Colors.black,
        points: [
          XppStrokePoint(x: 10, y: 20, width: 2),
          XppStrokePoint(x: 30, y: 40, width: 3),
        ],
      )..audioLink = StrokeAudioLink('lecture', 500, 1500, [500, 1500]),
    );
    final path = '${directory.path}/original.xopp';
    await File(path).writeAsBytes(await file.serializeSnapshotAsync());
    await RecentDocuments.save(file, path);
    final entries = await RecentDocuments.list();
    entries.single['tag'] = 'Tag libreria';
    entries.single['favorite'] = true;
    await CriticalData.write(PreferencesKeys.kRecentFiles, entries);
    await NoteTags.create('Categoria vuota');
    final prepared = await NoteBackup.create(staged: true);
    addTearDown(prepared.dispose);
    expect(prepared.unavailable, isEmpty);
    final contents = await NoteBackup.inspectStaged(prepared.stagedPath!);
    addTearDown(contents.dispose);
    expect(contents.tags, contains('Categoria vuota'));
    expect(await NoteBackup.restore(contents), 1);
    expect(await NoteBackup.restore(contents), 1);
    final restored = await RecentDocuments.list();
    expect(restored, hasLength(3));
    expect(restored.map((e) => e['id']).toSet(), hasLength(3));
    for (final entry in restored.where((e) => e['path'] != path)) {
      final reopened = await XppFile.fromFilePickerCross(
        await FilePickerCross.fromInternalPath(path: entry['path'] as String),
        null,
        (_) async => throw StateError('Missing background'),
      );
      expect(reopened.documentId, entry['id']);
      expect(reopened.tag, 'Tag libreria');
      expect(entry['favorite'], isTrue);
      expect(reopened.recordings['lecture']!.bytes, [1, 2, 3, 4]);
      final link = reopened.pages!.first.layers!.first.content!
          .whereType<XppStroke>()
          .single
          .audioLink!;
      expect(link.recordingId, 'lecture');
      expect(link.startMs, 500);
      expect(link.endMs, 1500);
      expect(link.samples, [500, 1500]);
    }
  });

  test(
    'disk backup preserves a lecture with more than 32 MiB of audio',
    () async {
      SharedPreferences.setMockInitialValues({});
      final provider = PathProviderPlatform.instance;
      final directory = await Directory.systemTemp.createTemp(
        'tenerumi-backup-lecture-',
      );
      PathProviderPlatform.instance = TestDocumentsProvider(directory.path);
      try {
        final file = XppFile.empty(title: 'Lezione lunga');
        file.recordings['lecture'] = NoteRecording(
          'lecture',
          3600000,
          Uint8List(33 * 1024 * 1024)..[0] = 123,
        );
        final path = '${directory.path}/lecture.xopp';
        await File(path).writeAsBytes(await file.serializeSnapshotAsync());
        await RecentDocuments.save(file, path);
        final prepared = await NoteBackup.create(staged: true);
        try {
          expect(prepared.count, 1);
          expect(prepared.unavailable, isEmpty);
          final contents = await NoteBackup.inspectStaged(prepared.stagedPath!);
          try {
            final restored = await contents.notes.single.load();
            expect(
              restored.recordings['lecture']!.bytes.length,
              33 * 1024 * 1024,
            );
            expect(restored.recordings['lecture']!.bytes.first, 123);
            expect(restored.recordings['lecture']!.durationMs, 3600000);
          } finally {
            await contents.dispose();
          }
        } finally {
          await prepared.dispose();
        }
      } finally {
        PathProviderPlatform.instance = provider;
        expect(
          directory.absolute.path.startsWith(
            '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
          ),
          isTrue,
        );
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'backup checkpoints the last edits when a note has just closed',
    () async {
      SharedPreferences.setMockInitialValues({});
      final provider = PathProviderPlatform.instance;
      final directory = await Directory.systemTemp.createTemp(
        'tenerumi-backup-closing-',
      );
      PathProviderPlatform.instance = TestDocumentsProvider(directory.path);
      try {
        final controller = CanvasController();
        controller.file = XppFile.empty(title: 'Ultima modifica');
        controller.hasUnsavedChanges = true;
        controller.dispose();
        final prepared = await NoteBackup.create(staged: true);
        try {
          expect(prepared.count, 1);
          expect(prepared.unavailable, isEmpty);
          final contents = await NoteBackup.inspectStaged(prepared.stagedPath!);
          try {
            expect(contents.notes.single.title, 'Ultima modifica');
          } finally {
            await contents.dispose();
          }
        } finally {
          await prepared.dispose();
        }
      } finally {
        PathProviderPlatform.instance = provider;
        expect(
          directory.absolute.path.startsWith(
            '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
          ),
          isTrue,
        );
        await directory.delete(recursive: true);
      }
    },
  );

  test('backup rejects a stroke whose recording is missing', () async {
    final file = XppFile.empty();
    file.pages!.first.layers!.first.content!.add(
      XppStrokePen(
        color: Colors.black,
        points: [XppStrokePoint(x: 1, y: 2, width: 1)],
      )..audioLink = StrokeAudioLink('missing', 0, 100),
    );
    final bytes = await NoteBackup.encode([BackupNote(file)]);
    await expectLater(NoteBackup.inspect(bytes), throwsFormatException);
  });
}
