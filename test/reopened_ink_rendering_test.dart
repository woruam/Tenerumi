import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

void repaint(List<XppStroke> strokes) {
  final recorder = ui.PictureRecorder();
  XppMasterPainter(layerContents: strokes)
      .paint(Canvas(recorder), const Size(600, 850));
  recorder.endRecording().dispose();
}

Future<Uint8List> pixels(List<XppStroke> strokes) async {
  final recorder = ui.PictureRecorder();
  XppMasterPainter(layerContents: strokes)
      .paint(Canvas(recorder), const Size(240, 180));
  final picture = recorder.endRecording();
  final image = await picture.toImage(240, 180);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '200 original and reopened strokes reuse geometry across repaints',
    () async {
      final document = XppFile.empty();
      final strokes = List.generate(
        200,
        (stroke) => XppStrokePen(
          color: Colors.black,
          points: List.generate(
            150,
            (point) => XppStrokePoint(
              x: 20 + point / 2,
              y: 20 + stroke * 3 + (point % 7) / 3,
              width: 2 + (point % 4) / 10,
            ),
          ),
        ),
      );
      document.pages!.first.layers!.first.content!.addAll(strokes);
      final reopened = await XppFile.fromFilePickerCross(
        FilePickerCross(await document.toUint8ListAsync()),
        null,
        (_) async => throw StateError('No background'),
      );
      for (final contents in [
        strokes,
        reopened.pages!.first.layers!.first.content!
            .whereType<XppStroke>()
            .toList(),
      ]) {
        final before = XppStrokePainter.debugPathBuilds;
        final beforeBounds = XppStrokePainter.debugBoundsBuilds;
        repaint(contents);
        final cold = XppStrokePainter.debugPathBuilds - before;
        final coldBounds = XppStrokePainter.debugBoundsBuilds - beforeBounds;
        for (var frame = 0; frame < 3; frame++) {
          repaint(contents);
        }
        final warm = XppStrokePainter.debugPathBuilds - before - cold;
        // More than both old limits (64 strokes / 25000 samples) are visible.
        expect(cold, 200);
        expect(coldBounds, 200);
        expect(
          XppStrokePainter.debugBoundsBuilds - beforeBounds,
          coldBounds,
          reason: 'Immutable bounds must never be rescanned in warm frames',
        );
        expect(XppStrokePainter.debugRetainedSamples, lessThanOrEqualTo(25000));
        expect(XppStrokePainter.debugRetainedPaths, lessThanOrEqualTo(64));
        // Weak targets can be reclaimed by GC. Report this count rather than
        // encoding a timing- or GC-dependent performance threshold in CI.
        debugPrint(
          'ink geometry: cold=$cold, 3 warm frames=$warm '
          '(previous 64-stroke cache: 600 warm builds), '
          'warm bounds scans=0',
        );
        final protected = contents.sublist(168);
        repaint(protected);
        final protectedBuilds = XppStrokePainter.debugPathBuilds;
        repaint(protected);
        expect(
          XppStrokePainter.debugPathBuilds,
          protectedBuilds,
          reason: 'The bounded strong working set survives GC',
        );
      }
    },
  );

  testWidgets('reopened ink, transforms and shared undo keep identical raster', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final document = XppFile.empty();
      final stroke = XppStrokePen(
        color: Colors.blue,
        points: [
          XppStrokePoint(x: 30, y: 30, width: 2),
          XppStrokePoint(x: 70, y: 50, width: 4),
          XppStrokePoint(x: 110, y: 20, width: 3),
        ],
      )..erasures = [const StrokeErasure(Offset(62, 45), Offset(75, 48), 4)];
      document.pages!.first.layers!.first.content!.add(stroke);
      final original = await pixels([stroke]);
      final reopened = await XppFile.fromFilePickerCross(
        FilePickerCross(await document.toUint8ListAsync()),
        null,
        (_) async => throw StateError('No background'),
      );
      final loaded =
          reopened.pages!.first.layers!.first.content!.single as XppStroke;
      expect(await pixels([loaded]), original);
      final history = loaded.copyWithSharedPoints();
      final builds = XppStrokePainter.debugPathBuilds;
      expect(await pixels([history]), original);
      expect(XppStrokePainter.debugPathBuilds, builds);
      loaded.translate(const Offset(20, 30));
      expect(loaded.getOffset(), history.getOffset() + const Offset(20, 30));
      expect(await pixels([loaded]), isNot(original));
      expect(await pixels([history]), original);
      loaded.scaleBy(1.5, Offset.zero);
      expect(loaded.getOffset(), const Offset(75, 75));
      expect(await pixels([history]), original);
      // A replaced buffer must never inherit its predecessor's cached geometry.
      loaded.points = [XppStrokePoint(x: 150, y: 140, width: 3)];
      expect(loaded.getOffset(), const Offset(150, 140));
      expect(await pixels([history]), original);
    });
  });

  test('public painter invalidates mutable samples and pressure mode', () {
    final samples = [XppStrokePoint(x: 20, y: 20, width: 2)];
    void draw(bool pressure) {
      final recorder = ui.PictureRecorder();
      XppStrokePainter(
        points: samples,
        smoothPressure: pressure,
      ).paint(Canvas(recorder), const Size(100, 100));
      recorder.endRecording().dispose();
    }

    final before = XppStrokePainter.debugPathBuilds;
    draw(true);
    draw(true);
    expect(XppStrokePainter.debugPathBuilds - before, 1);
    samples[0] = XppStrokePoint(x: 25, y: 20, width: 2);
    draw(true);
    samples.add(XppStrokePoint(x: 40, y: 40, width: 4));
    draw(true);
    draw(false);
    expect(XppStrokePainter.debugPathBuilds - before, 4);
  });
}
