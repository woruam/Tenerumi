import 'dart:convert';
import 'dart:io' show gzip, zlib;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/content_snapshot.dart';
import 'package:xournalpp/src/critical_data.dart';
import 'package:xournalpp/src/document_export.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/src/ink_geometry.dart';
import 'package:xournalpp/src/recovery_journal.dart';
import 'package:xournalpp/src/selection_clipboard.dart';
import 'package:xournalpp/src/stylus_pressure.dart';
import 'package:xournalpp/widgets/PointerListener.dart';

XppStroke stroke(double width, {bool diameter = false}) => XppStroke.byTool(
  tool: XppStrokeTool.PEN,
  color: Colors.black,
  widthIsDiameter: diameter,
  points: [
    XppStrokePoint(x: 30, y: 40, width: width),
    XppStrokePoint(x: 80, y: 40, width: width),
  ],
);

XppFile note(XppStroke value) =>
    XppFile.empty()..pages!.first.layers!.first.content!.add(value);

Future<FilePickerCross> unavailable(String? path) async =>
    throw StateError('Missing $path');

Future<XppStroke> reopen(XppFile file) async {
  final restored = await XppFile.fromFilePickerCross(
    FilePickerCross(file.toUint8List()!),
    null,
    unavailable,
  );
  expect(restored.importWarnings, isEmpty);
  return restored.pages!.first.layers!.first.content!.single as XppStroke;
}

Future<Uint8List> paint(XppStroke value) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final origin = value.getOffset();
  canvas.translate(origin.dx, origin.dy);
  value.paintToCanvas(canvas, const Size(100, 80));
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 80);
  try {
    return (await image.toByteData())!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

List<String> pdfStreams(Uint8List bytes) {
  final text = latin1.decode(bytes);
  final streams = <String>[];
  for (final object in RegExp(
    r'\d+ \d+ obj([\s\S]*?)endobj',
  ).allMatches(text)) {
    final body = object.group(1)!;
    final match = RegExp(r'stream\r?\n([\s\S]*?)\r?\nendstream')
        .firstMatch(body);
    if (match == null) continue;
    final dictionary = body.substring(0, match.start);
    if (dictionary.contains('/Metadata')) continue;
    final payload = latin1.encode(match.group(1)!);
    streams.add(
      latin1.decode(
        dictionary.contains('/FlateDecode') ? zlib.decode(payload) : payload,
      ),
    );
  }
  return streams;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'zero pressure is real, driver ranges normalize, invalid samples fall back',
    () {
      double pressure(
        double value, {
        double min = 0,
        double max = 1,
        bool pen = true,
      }) => normalizedStylusPressure(
        isStylus: pen,
        pressure: value,
        minimum: min,
        maximum: max,
      );
      expect(pressure(0), 0);
      expect(pressure(0, min: 1, max: 1), 0);
      expect(pressure(.25, min: double.nan), .25);
      expect(pressure(1024, max: 4096), .25);
      expect(pressure(100, min: 100, max: 1100), 0);
      expect(pressure(-10), 0);
      expect(pressure(10), 1);
      expect(pressure(double.nan), .5);
      expect(pressure(double.infinity), .5);
      expect(pressure(0, pen: false), .5);
    },
  );

  test(
    'all 4096 pressure levels have distinct increasing physical diameters',
    () {
      for (final base in [.1, 2.5, 10.0]) {
        var previous = 0.0;
        for (var level = 0; level < 4096; level++) {
          final width = pressurePenDiameter(base, level / 4095);
          final radius = inkRadius(width, pressureSensitive: false);
          expect(
            radius,
            greaterThan(previous),
            reason: 'base=$base level=$level',
          );
          expect(radius, closeTo(width / 2, 1e-12));
          previous = radius;
        }
        expect(pressurePenDiameter(base, 0), closeTo(base * .1, 1e-12));
        expect(pressurePenDiameter(base, .5), closeTo(base, 1e-12));
        expect(pressurePenDiameter(base, 1), closeTo(base * 3.7, 1e-12));
      }
    },
  );

  testWidgets(
    'pointer zero and half pressure produce thin and nominal diameter ink',
    (tester) async {
      XppStroke? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: PointerListener(
            color: Colors.black,
            strokeWidth: 2.5,
            toolData: const {ui.PointerDeviceKind.stylus: EditingTool.STYLUS},
            onNewContent: (value) => saved = value as XppStroke,
            child: const SizedBox(width: 300, height: 200),
          ),
        ),
      );
      await tester.sendEventToBinding(
        const PointerDownEvent(
          pointer: 71,
          kind: ui.PointerDeviceKind.stylus,
          position: Offset(30, 40),
          pressure: 0,
        ),
      );
      await tester.sendEventToBinding(
        const PointerMoveEvent(
          pointer: 71,
          kind: ui.PointerDeviceKind.stylus,
          position: Offset(80, 40),
          pressure: .5,
        ),
      );
      await tester.sendEventToBinding(
        const PointerUpEvent(
          pointer: 71,
          kind: ui.PointerDeviceKind.stylus,
          position: Offset(80, 40),
        ),
      );
      expect(saved!.widthIsDiameter, isTrue);
      expect(saved!.points!.first.width, .25);
      expect(saved!.points!.last.width, 2.5);
      expect(saved!.bounds(), const Rect.fromLTRB(28.75, 38.75, 81.25, 41.25));
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final automaticRecognition in [false, true]) {
    testWidgets(
      'shape widths retain their previous meaning: automatic=$automaticRecognition',
      (tester) async {
        XppStroke? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: PointerListener(
              color: Colors.black,
              strokeWidth: 2.5,
              shapeRecognition: automaticRecognition,
              toolData: {
                ui.PointerDeviceKind.stylus: automaticRecognition
                    ? EditingTool.STYLUS
                    : EditingTool.SHAPE_LINE,
              },
              onNewContent: (value) => saved = value as XppStroke,
              child: const SizedBox(width: 300, height: 200),
            ),
          ),
        );
        await tester.sendEventToBinding(
          const PointerDownEvent(
            pointer: 72,
            kind: ui.PointerDeviceKind.stylus,
            position: Offset(30, 40),
            pressure: .5,
          ),
        );
        for (var i = 1; i < 10; i++) {
          await tester.sendEventToBinding(
            PointerMoveEvent(
              pointer: 72,
              kind: ui.PointerDeviceKind.stylus,
              position: Offset(30 + i * 10, 40),
              pressure: .5,
            ),
          );
        }
        await tester.sendEventToBinding(
          const PointerUpEvent(
            pointer: 72,
            kind: ui.PointerDeviceKind.stylus,
            position: Offset(120, 40),
          ),
        );
        expect(saved!.isShape, isTrue);
        expect(saved!.widthIsDiameter, isFalse);
        expect(saved!.points!.first.width, closeTo(2.4375, 1e-12));
        expect(saved!.bounds()!.height, closeTo(2.4375, 1e-12));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('XOPP keeps new diameters and leaves old or unknown markers on legacy geometry', () async {
    final original = stroke(9.25, diameter: true);
    final restored = await reopen(note(original));
    expect(restored.widthIsDiameter, isTrue);
    expect(restored.bounds(), original.bounds());
    expect(restored.inkPath.getBounds(), original.inkPath.getBounds());
    final legacy = stroke(9.25);
    expect((await reopen(note(legacy))).bounds(), legacy.bounds());
    final xml = note(original)
        .toXmlString()
        .replaceAll('osipp-width="diameter"', 'osipp-width="future-model"');
    final unknown = await XppFile.fromFilePickerCross(
      FilePickerCross(Uint8List.fromList(gzip.encode(utf8.encode(xml)))),
      null,
      unavailable,
    );
    final imported =
        unknown.pages!.first.layers!.first.content!.single as XppStroke;
    expect(imported.widthIsDiameter, isFalse);
    expect(imported.bounds(), legacy.bounds());
  });

  test(
    'snapshot, clipboard, scaling and pixel eraser preserve diameter semantics',
    () {
      final original = stroke(8, diameter: true);
      final snapshot = cloneContent(original) as XppStroke;
      expect(snapshot.widthIsDiameter, isTrue);
      expect(snapshot.points, same(original.points));
      final clipboard = SelectionClipboard()..copy([original]);
      final pasted =
          clipboard.pasteAt(const Offset(100, 100)).single as XppStroke;
      expect(pasted.widthIsDiameter, isTrue);
      expect(pasted.bounds()!.size, original.bounds()!.size);
      snapshot.scaleBy(2, Offset.zero);
      expect(snapshot.bounds()!.height, 16);
      expect(original.bounds()!.height, 8);
      final erased =
          original
                  .eraseWhere(coordinates: const Offset(50, 40), radius: 1)
                  .newContent
                  .single
              as XppStroke;
      expect(erased.widthIsDiameter, isTrue);
      expect(erased.containsVisibleInk(const Offset(50, 40)), isFalse);
      expect(erased.containsVisibleInk(const Offset(30, 43)), isTrue);
    },
  );

  testWidgets(
    'shared point buffers keep separate cached diameter and legacy paths',
    (tester) async {
      await tester.runAsync(() async {
        final diameter = stroke(8, diameter: true);
        final legacy = diameter.copyWithSharedPoints()..widthIsDiameter = false;
        expect(diameter.points, same(legacy.points));
        final modernPixels = await paint(diameter);
        final legacyPixels = await paint(legacy);
        expect(modernPixels, isNot(orderedEquals(legacyPixels)));
        expect(await paint(diameter), orderedEquals(modernPixels));
        expect(await paint(legacy), orderedEquals(legacyPixels));
        expect(diameter.bounds()!.height, 8);
        expect(legacy.bounds()!.height, 8.5);
      });
    },
  );

  test('recovery fragments distinguish identical samples with different width semantics', () async {
    CriticalData.inMemoryForTests = true;
    try {
      final original = stroke(8, diameter: true);
      final file = note(original);
      final diameterHash = await RecoveryJournal.write(file.snapshot());
      original.widthIsDiameter = false;
      final legacyHash = await RecoveryJournal.write(file.snapshot());
      final modern = await RecoveryJournal.read(diameterHash);
      final legacy = await RecoveryJournal.read(legacyHash);
      final modernInk =
          modern.pages!.first.layers!.first.content!.single as XppStroke;
      final legacyInk =
          legacy.pages!.first.layers!.first.content!.single as XppStroke;
      expect(modernInk.widthIsDiameter, isTrue);
      expect(legacyInk.widthIsDiameter, isFalse);
      expect(modernInk.bounds()!.height, 8);
      expect(legacyInk.bounds()!.height, 8.5);
    } finally {
      CriticalData.inMemoryForTests = false;
    }
  });

  testWidgets('PDF vector ink uses the same physical radius as the editor', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final modern = await buildNotesPdf(
        note(stroke(5, diameter: true)),
        loadBackground: (_, _, _) async => null,
      );
      // Legacy width 2.5 has radius 2.5; a new diameter of 5 must match it.
      final legacy = await buildNotesPdf(
        note(stroke(2.5)),
        loadBackground: (_, _, _) async => null,
      );
      final modernStreams = pdfStreams(modern);
      expect(modernStreams, isNotEmpty);
      expect(modernStreams, orderedEquals(pdfStreams(legacy)));
    });
  });
}
