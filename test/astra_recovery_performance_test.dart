import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/controllers/note_audio_controller.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/autosave_store.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/compat/internal_storage_io.dart' as storage;
import 'package:xournalpp/src/content_snapshot.dart';
import 'package:xournalpp/src/critical_data.dart';
import 'package:xournalpp/src/decoded_image_cache.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/src/note_audio.dart';
import 'package:xournalpp/src/note_backup.dart';
import 'package:xournalpp/src/note_flashcards.dart';
import 'package:xournalpp/src/recent_documents.dart';
import 'package:xournalpp/src/recovery_journal.dart';

XppStroke ink([int samples = 100]) => XppStrokePen(
  color: Colors.black,
  points: List.generate(
    samples,
    (i) => XppStrokePoint(x: i.toDouble(), y: 40, width: 2),
  ),
);
Future<Uint8List> png() async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 256, 256), Paint()..color = Colors.blue);
  final picture = recorder.endRecording(),
      image = await picture.toImage(256, 256);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class AudioStaging implements NoteAudioBackend {
  final calls = <({String method, Map<String, Object?>? args})>[];
  bool rejectAck = false;
  @override
  Future<Object?> invoke(String method, [Map<String, Object?>? args]) async {
    calls.add((method: method, args: args));
    if (method == 'stop')
      return {
        'bytes': Uint8List.fromList([1, 2, 3]),
        'duration': 1000,
      };
    if (method == 'ack' && rejectAck) throw StateError('storage unavailable');
    if (method == 'recover')
      return [
        {
          'id': 'ready',
          'state': 'ready',
          'bytes': Uint8List.fromList([4]),
          'duration': 500,
        },
        {'id': 'unfinished', 'state': 'partial'},
      ];
    return null;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CriticalData.inMemoryForTests = false;
  });
  test(
    'A06 simultaneous instances of the same origin remain independent',
    () async {
      final a = XppFile.empty()..sourcePath = 'same.xopp';
      final b = a.snapshot()..localId = 'another-instance';
      await AutosaveStore.save(a, a.toUint8List()!);
      await AutosaveStore.save(b, b.toUint8List()!);
      expect(await AutosaveStore.list(), hasLength(2));
      await AutosaveStore.remove(a.recoveryKey);
      expect(
        (await AutosaveStore.list()).single['localId'],
        'another-instance',
      );
    },
  );
  test(
    'incremental journal round trip retains ink, masks, media, audio and cards',
    () async {
      final f = XppFile.empty(title: 'Journal');
      final stroke = ink()
        ..erasures = [const StrokeErasure(Offset(4, 40), Offset(9, 40), 2)]
        ..audioLink = StrokeAudioLink('rec', 0, 500, []);
      final bytes = Uint8List.fromList([1, 2, 3]);
      f.pages!.first.layers!.first.content!.addAll([
        stroke,
        XppImage(
          data: bytes,
          topLeft: Offset.zero,
          bottomRight: const Offset(20, 20),
        ),
      ]);
      f.recordings['rec'] = NoteRecording('rec', 1000, bytes);
      f.flashcards['card'] = NoteFlashcard(
        id: 'card',
        front: FlashcardSide(text: 'D', page: 0, image: bytes),
        back: FlashcardSide(text: 'R', page: 0),
      );
      f.pdfAttachments['embedded.pdf'] = bytes;
      f.previewImage = bytes;
      await AutosaveStore.saveIncremental(f.snapshot());
      final first = (await AutosaveStore.list()).single;
      final restored = await AutosaveStore.restore(first);
      expect(
        (restored.pages!.first.layers!.first.content!.first as XppStroke)
            .toXmlElement()
            .toXmlString(),
        stroke.toXmlElement().toXmlString(),
      );
      expect(restored.recordings['rec']!.bytes, bytes);
      expect(restored.flashcards['card']!.front.image, bytes);
      expect(restored.pdfAttachments['embedded.pdf'], bytes);
      final writes = RecoveryJournal.writtenFragments,
          reuses = RecoveryJournal.reusedFragments;
      await AutosaveStore.saveIncremental(f.snapshot());
      expect(
        RecoveryJournal.writtenFragments,
        writes + 1,
      ); // Image wrapper is cheap; geometry is reused.
      expect(RecoveryJournal.reusedFragments, reuses + 1);
      stroke.color = Colors.red;
      await AutosaveStore.saveIncremental(f.snapshot());
      expect(RecoveryJournal.writtenFragments, writes + 3);
      final latest = (await AutosaveStore.list()).single;
      expect(latest['hash'], isNot(first['hash']));
    },
  );
  test('A07 garbage collection retains previous generation and journal dependencies', () async {
    final f = XppFile.empty(title: 'prima');
    final stroke = ink();
    f.pages!.first.layers!.first.content!.add(stroke);
    for (var i = 0; i < 5; i++) {
      f.title = 'versione-$i';
      stroke.color = Color(0xff000000 + i);
      await AutosaveStore.saveIncremental(f.snapshot());
    }
    final root = Directory(await storage.resolve('state-v2'));
    final orphan = await CriticalData.putBlob(Uint8List.fromList([99]));
    for (final file in root.listSync().whereType<File>()) {
      await file.setLastModified(DateTime(2000));
    }
    await CriticalData.collectGarbage(force: true);
    expect(await CriticalData.hasBlob(orphan), isFalse);
    final latest = (await AutosaveStore.list()).single;
    await File('${root.path}/${latest['hash']}.blob')
        .writeAsBytes([0], flush: true);
    final recovered = await AutosaveStore.restore(latest);
    expect(recovered.title, 'versione-3');
    expect(recovered.importWarnings.join(), contains('precedente'));
    final recoveredInk =
        recovered.pages!.first.layers!.first.content!.single as XppStroke;
    expect(recoveredInk.color!.toARGB32(), 0xff000003);
  });
  test('A07 library sidecar reconstructs an index after all metadata commits are lost', () async {
    final f = XppFile.empty(title: 'Indice recuperato');
    f.sourcePath = await FilePickerCross(f.toUint8List()!)
        .saveToPath(path: 'owned.xopp');
    await RecentDocuments.save(f, f.sourcePath!);
    final root = Directory(await storage.resolve('state-v2'));
    for (final file in root.listSync().whereType<File>().where(
      (e) => e.path.endsWith('.commit'),
    )) {
      await file.writeAsString('{broken', flush: true);
    }
    final entries = await RecentDocuments.list();
    expect(entries.single['name'], f.title);
    expect(CriticalData.warnings, isNotEmpty);
  });
  testWidgets('A08 pinned images obey byte and entry limits across owners', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final cache = DecodedImageCache(
      maxBytes: 4096,
      maxEntries: 2,
      maxDimension: 256,
    );
    final images = (await tester.runAsync(
      () async => [await png(), await png(), await png()],
    ))!;
    final left = Object(), right = Object();
    cache.retain(left, images.take(2));
    cache.retain(right, images.skip(2));
    for (final bytes in images) {
      cache.lookup(bytes);
    }
    for (var i = 0; i < 30 && cache.byteCount == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(cache.entryCount, 2);
    expect(cache.byteCount, inInclusiveRange(4, 4096));
    expect(cache.lookup(images.last), isNull);
    var releasedNotifications = 0;
    cache.addListener(() => releasedNotifications++);
    cache.release(left);
    await tester.pump();
    expect(releasedNotifications, greaterThan(0));
    cache.lookup(images.last);
    for (var i = 0; i < 30 && cache.byteCount == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(cache.lookup(images.last), isNotNull);
    expect(cache.byteCount, lessThanOrEqualTo(4096));
    cache.release(right);
    expect(cache.byteCount, 0);
    cache.dispose();
  });
  test(
    'A09 segments survive rotation and acknowledgement happens explicitly',
    () async {
      final backend = AudioStaging(), f = XppFile.empty();
      var changes = 0;
      final audio = NoteAudioController(
        f,
        onDocumentChanged: () => changes++,
        onModeChanged: () {},
        backend: backend,
        elapsedClock: () => 1000,
      );
      await audio.start();
      final first = audio.recordingId;
      await audio.rotateSegment();
      expect(audio.recordingId, isNot(first));
      await audio.stop();
      expect(f.recordings, hasLength(2));
      expect(changes, 2);
      expect(backend.calls.where((c) => c.method == 'ack'), isEmpty);
      expect(backend.calls.first.args!['noteId'], f.localId);
      backend.rejectAck = true;
      await audio.acknowledge(f.recordings.keys);
      expect(f.recordings, hasLength(2));
      await audio.recoverStaged();
      expect(f.recordings.containsKey('ready'), true);
      expect(f.recordings.containsKey('unfinished'), false);
      await audio.close();
    },
  );
  test('A18 staged backup preserves conflicting originals, validates lazily and cleans on cancel', () async {
    final f = XppFile.empty(title: 'Originale');
    f.sourcePath = await FilePickerCross(f.toUint8List()!)
        .saveToPath(path: 'source.xopp');
    await RecentDocuments.save(f, f.sourcePath!);
    f.title = 'Recupero';
    await AutosaveStore.saveIncremental(f);
    final prepared = await NoteBackup.create(staged: true);
    expect(prepared.count, 2);
    final contents = await NoteBackup.inspectStaged(prepared.stagedPath!);
    expect(contents.notes, hasLength(2));
    expect(contents.notes.every((n) => n.payloadPath != null), true);
    expect((await contents.notes.first.load()).title, 'Originale');
    final cancellation = BackupCancellation()..cancel();
    await expectLater(
      NoteBackup.restore(contents, cancellation: cancellation),
      throwsStateError,
    );
    expect(
      (await CriticalData.read(PreferencesKeys.kRecentFiles) as List),
      hasLength(1),
    );
    final path = prepared.stagingRoot!, extracted = contents.stagingRoot!;
    await contents.dispose();
    await prepared.dispose();
    expect(Directory(path).existsSync(), false);
    expect(Directory(extracted).existsSync(), false);
  });
  test('dense undo shares immutable geometry and transformed snapshots stay independent', () async {
    final stroke = ink(100000), watch = Stopwatch()..start();
    final rss = ProcessInfo.currentRss;
    final history = List.generate(50, (_) => cloneContent(stroke) as XppStroke);
    watch.stop();
    expect(history.every((s) => identical(s.points, stroke.points)), true);
    expect(() => history.first.points!.removeLast(), throwsUnsupportedError);
    stroke.translate(const Offset(30, 5));
    expect(history.last.points!.first.x, 0);
    expect(stroke.points!.first.x, 30);
    await File('docs/validation/astra-next-undo-measurement.json')
        .writeAsString(
          jsonEncode({
            'points': 100000,
            'snapshots': 50,
            'uniqueGeometryBuffers': 1,
            'elapsedMicroseconds': watch.elapsedMicroseconds,
            'rssBefore': rss,
            'rssAfter': ProcessInfo.currentRss,
            'scope': 'Flutter host test, structural sharing; not device GPU/latency profiling',
          }),
        );
  });
}
