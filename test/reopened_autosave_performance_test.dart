import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/autosave_store.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/critical_data.dart';
import 'package:xournalpp/src/recovery_journal.dart';

Future<FilePickerCross> _unavailable(String? _) async =>
    throw StateError('Missing');

class _PreviewSpy extends CanvasController {
  int previews = 0;
  @override
  Future<Uint8List> buildPreviewBytes([XppFile? snapshot]) async {
    previews++;
    return Uint8List(0);
  }
}

Future<Map<String, int>> measure(Future<void> Function() action) async {
  final watch = Stopwatch()..start();
  var last = 0, maximumGap = 0, ticks = 0;
  final heartbeat = Timer.periodic(const Duration(milliseconds: 4), (_) {
    final now = watch.elapsedMicroseconds;
    final gap = now - last;
    if (gap > maximumGap) maximumGap = gap;
    last = now;
    ticks++;
  });
  try {
    await action();
    final finalGap = watch.elapsedMicroseconds - last;
    if (finalGap > maximumGap) maximumGap = finalGap;
    return {
      'elapsedUs': watch.elapsedMicroseconds,
      'maxEventGapUs': maximumGap,
      'ticks': ticks,
    };
  } finally {
    heartbeat.cancel();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CriticalData.inMemoryForTests = false;
  });
  for (final (strokes, points) in [(200, 1000), (1, 200000)]) {
    test(
      'cold reopened journal responsiveness $strokes strokes x $points points',
      () async {
        final file = XppFile.empty(title: 'Dense note');
        file.pages!.first.layers!.first.content!.addAll(
          List.generate(
            strokes,
            (stroke) => XppStrokePen(
              color: Colors.black,
              points: List.generate(
                points,
                (index) => XppStrokePoint(
                  x: (index % 500).toDouble(),
                  y: (stroke % 700).toDouble(),
                  width: 2,
                ),
              ),
            ),
          ),
        );
        final results = <String, Object>{
          'strokes': strokes,
          'pointsPerStroke': points,
        };
        final initialWrites = RecoveryJournal.writtenFragments;
        final initialReuses = RecoveryJournal.reusedFragments;
        final initialOffloads = RecoveryJournal.offloadedStrokeFragments;
        results['cold'] = await measure(
          () async => RecoveryJournal.write(file.snapshot()),
        );
        expect(RecoveryJournal.writtenFragments - initialWrites, strokes);
        results['warm'] = await measure(
          () async => RecoveryJournal.write(file.snapshot()),
        );
        expect(RecoveryJournal.reusedFragments - initialReuses, strokes);
        final bytes = await file.toUint8ListAsync();
        final reopened = await XppFile.fromFilePickerCross(
          FilePickerCross(bytes),
          null,
          _unavailable,
        );
        results['reopened'] = await measure(
          () async => RecoveryJournal.write(reopened.snapshot()),
        );
        expect(RecoveryJournal.writtenFragments - initialWrites, strokes * 2);
        expect(
          RecoveryJournal.offloadedStrokeFragments - initialOffloads,
          points >= 4096 ? strokes * 2 : 0,
        );
        results['snapshot'] = await measure(() async {
          reopened.snapshot();
        });
        results['serializeCompact'] = await measure(() async {
          await reopened.toUint8ListAsync();
        });
        // Host event-loop diagnostic, not an Android frame-time claim.
        print('AUTOSAVE_MEASUREMENT ${jsonEncode(results)}');
        expect(reopened.pages!.first.layers!.first.content, hasLength(strokes));
      },
    );
  }

  test(
    'scheduled compact waits for pointer idle; journal deadline remains',
    () async {
      CriticalData.inMemoryForTests = true;
      final ctrl = _PreviewSpy()..init(XppFile.empty());
      ctrl.hasUnsavedChanges = true;
      ctrl.beginInput(1);
      // Native serialization and the queue must share the real async zone.
      await Future<void>.delayed(const Duration(milliseconds: 10100));
      await ctrl.flushAutosave(compact: false);
      expect(ctrl.previews, 0);
      expect((await AutosaveStore.list()).single['format'], 'journal');
      ctrl.endInput(1);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      ctrl.beginInput(2);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(ctrl.previews, 0);
      ctrl.endInput(2);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await ctrl.flushAutosave(compact: false);
      expect(ctrl.previews, 1);
      ctrl.dispose();
    },
  );

  test(
    'queued scheduled compact rechecks input when prior journal finishes',
    () async {
      CriticalData.inMemoryForTests = true;
      final ctrl = _PreviewSpy()..init(XppFile.empty());
      final release = Completer<void>(), started = Completer<void>();
      final lease = CriticalData.blobTransaction(() {
        started.complete();
        return release.future;
      });
      await started.future;
      ctrl.hasUnsavedChanges = true;
      final pendingJournal = ctrl.flushAutosave(compact: false);
      // The deadline dispatches a compact request behind the blocked journal.
      await Future<void>.delayed(const Duration(milliseconds: 10100));
      ctrl.beginInput(1);
      release.complete();
      await lease;
      await pendingJournal;
      await ctrl.flushAutosave(compact: false);
      expect(ctrl.previews, 0);
      expect((await AutosaveStore.list()).single['format'], 'journal');
      ctrl.endInput(1);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await ctrl.flushAutosave(compact: false);
      expect(ctrl.previews, 1);
      expect((await AutosaveStore.list()).single['format'], isNot('journal'));
      ctrl.dispose();
    },
  );

  test('offloaded dense fragment remains byte-identical and cached after metadata edits', () async {
    final stroke = XppStrokePen(
      color: Colors.red,
      points: List.generate(
        8192,
        (i) => XppStrokePoint(
          x: (i % 500).toDouble(),
          y: 30,
          width: 1 + (i % 3).toDouble(),
        ),
      ),
    )..erasures = [const StrokeErasure(Offset(10, 30), Offset(20, 30), 2)];
    final file = XppFile.empty()
      ..pages!.first.layers!.first.content!.add(stroke);
    final expected = utf8.encode(stroke.toXmlElement().toXmlString());
    final manifestHash = await RecoveryJournal.write(file.snapshot());
    final manifest = jsonDecode(
      utf8.decode(await CriticalData.getBlob(manifestHash)),
    ) as Map;
    final fragmentHash =
        manifest['pages'][0]['layers'][0]['content'][0] as String;
    expect(await CriticalData.getBlob(fragmentHash), expected);
    final offloads = RecoveryJournal.offloadedStrokeFragments;
    file.title = 'Changed title';
    await RecoveryJournal.write(file.snapshot());
    expect(RecoveryJournal.offloadedStrokeFragments, offloads);
    final saved = await RecoveryJournal.read(manifestHash);
    final restored =
        saved.pages!.first.layers!.first.content!.single as XppStroke;
    expect(restored.points, hasLength(8192));
    expect(
      restored.erasures.map((cut) => cut.encode()),
      stroke.erasures.map((cut) => cut.encode()),
    );
    expect(restored.color!.toARGB32(), stroke.color!.toARGB32());
    expect(restored.points!.last.x, stroke.points!.last.x);
    expect(restored.points!.last.width, stroke.points!.last.width);
  });

  test('explicit compact flush during active input still secures complete document', () async {
    final ctrl = _PreviewSpy()..init(XppFile.empty(title: 'Active save'));
    ctrl.file!.pages!.first.layers!.first.content!.add(
      XppStrokePen(
        color: Colors.black,
        points: [XppStrokePoint(x: 10, y: 10, width: 2)],
      ),
    );
    ctrl.hasUnsavedChanges = true;
    ctrl.beginInput(1);
    await ctrl.flushAutosave();
    expect(ctrl.autosaveError, isNull);
    final entry = (await AutosaveStore.list()).single;
    expect(entry['format'], isNot('journal'));
    final saved = await XppFile.fromFilePickerCross(
      FilePickerCross(await AutosaveStore.readBytes(entry)),
      null,
      _unavailable,
    );
    expect(saved.pages!.first.layers!.first.content, hasLength(1));
    ctrl.endInput(1);
    ctrl.dispose();
  });
}
