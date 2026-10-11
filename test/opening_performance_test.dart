import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/bounded_archive.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'point scanner preserves whitespace and partial pressure lists',
    () async {
      const xml =
          '<xournal fileversion="4"><page width="100" height="100">'
          '<background type="solid" color="#ffffffff" style="plain"/><layer>'
          '<stroke tool="pen" color="#000000ff" width="2  3">1\t2\n3 4  5 6</stroke>'
          '</layer></page></xournal>';
      final file = await XppFile.fromFilePickerCross(
        FilePickerCross(
          Uint8List.fromList(GZipEncoder().encode(utf8.encode(xml))),
        ),
        null,
        (_) async => throw StateError('Unavailable'),
      );
      final stroke =
          file.pages!.first.layers!.first.content!.single as XppStroke;
      expect(stroke.points!.map((p) => p.width), [2, 3, 2]);
      expect(stroke.points!.map((p) => (p.x, p.y)), [(1, 2), (3, 4), (5, 6)]);
    },
  );
  test(
    'native gzip rejects every truncated trailer including empty members',
    () {
      for (final text in ['', 'hello']) {
        final bytes = Uint8List.fromList(
          GZipEncoder().encode(utf8.encode(text)),
        );
        for (var missing = 1; missing <= 8; missing++) {
          expect(
            () => decodeBoundedGzip(
              Uint8List.sublistView(bytes, 0, bytes.length - missing),
              maxInput: 128,
              maxOutput: 10,
            ),
            throwsA(anything),
            reason: 'Missing $missing trailer bytes for "$text"',
          );
        }
      }
      final good = GZipEncoder().encode(utf8.encode('hello'));
      expect(
        utf8.decode(
          decodeBoundedGzip(
            Uint8List.fromList([...good, ...good]),
            maxInput: 128,
            maxOutput: 10,
          ),
        ),
        'hellohello',
      );
    },
  );
  test(
    'measure XOPP opening and preserve large attachments and pressure ink',
    () async {
      final file = XppFile.empty(title: 'Opening benchmark');
      final attachment = Uint8List.fromList(
        List.generate(8 * 1024 * 1024, (i) => i % 251),
      );
      file.pdfAttachments['opaque-benchmark.pdf'] = attachment;
      file.pages!.first.layers!.first.content!.add(
        XppStrokePen(
          color: Colors.blue,
          points: List.generate(
            20000,
            (i) => XppStrokePoint(
              x: (i % 500).toDouble(),
              y: (i % 800).toDouble(),
              width: 1 + (i % 10) / 10,
            ),
          ),
        ),
      );
      final bytes = await file.toUint8ListAsync();
      final inflateTimes = <int>[], openingTimes = <int>[];
      var expandedBytes = 0;
      for (var i = 0; i < 4; i++) {
        final watch = Stopwatch()..start();
        final xml = decodeBoundedGzip(
          bytes,
          maxInput: 128 * 1024 * 1024,
          maxOutput: 256 * 1024 * 1024,
        );
        watch.stop();
        expandedBytes = xml.length;
        if (i > 0) inflateTimes.add(watch.elapsedMicroseconds);
        watch.reset();
        watch.start();
        final reopened = await XppFile.fromFilePickerCross(
          FilePickerCross(bytes),
          null,
          (_) async => throw StateError('Unavailable'),
        );
        watch.stop();
        if (i > 0) openingTimes.add(watch.elapsedMicroseconds);
        expect(reopened.pdfAttachments.values.single, attachment);
        final stroke =
            reopened.pages!.first.layers!.first.content!.single as XppStroke;
        expect(stroke.points, hasLength(20000));
        expect(stroke.color!.toARGB32(), Colors.blue.toARGB32());
        expect(stroke.points!.last.width, closeTo(1.9, .000001));
      }
      int median(List<int> values) => (values..sort())[values.length ~/ 2];
      const tag = String.fromEnvironment(
        'OPEN_BENCH_TAG',
        defaultValue: 'after',
      );
      await File('docs/validation/opening-$tag-2026-10-11.json').writeAsString(
        jsonEncode({
          'environment': 'Windows desktop Flutter test/JIT; synthetic XOPP, not Android device latency',
          'fixture': '8 MiB opaque attachment and 20000 pressure points; no PDF rasterization',
          'compressedBytes': bytes.length,
          'xmlBytes': expandedBytes,
          'warmupRuns': 1,
          'measuredRuns': 3,
          'inflateMedianMicros': median(inflateTimes),
          'openMedianMicros': median(openingTimes),
        }),
      );
    },
  );
}
