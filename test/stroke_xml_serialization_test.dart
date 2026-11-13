import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/note_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('XppStroke XML serialization equivalence', () {
    test('writeXml and toXmlElement produce semantically equivalent XML for all stroke features', () {
      final strokes = [
        // Full feature stroke: pen, audioLink with special XML chars, erasures, isShape, smooth, widthIsDiameter
        XppStroke.byTool(
          tool: XppStrokeTool.PEN,
          color: const Color(0xFF1E88E5),
          isShape: true,
          smooth: true,
          widthIsDiameter: true,
          points: [
            XppStrokePoint(x: 12.3456, y: 78.9101, width: 2.1234),
            XppStrokePoint(x: 45.6789, y: 101.1121, width: 3.4567),
            XppStrokePoint(x: 99.0012, y: 200.3456, width: 1.9876),
          ],
        )
          ..audioLink = StrokeAudioLink('rec_<1>&"special"', 100, 500, [100, 250, 500])
          ..erasures = [
            StrokeErasure(const Offset(10.5, 20.25), const Offset(30.75, 40.125), 4.5),
          ],

        // Highlighter stroke
        XppStroke.byTool(
          tool: XppStrokeTool.HIGHLIGHTER,
          color: const Color(0xFFFFEB3B),
          isShape: false,
          smooth: false,
          widthIsDiameter: false,
          points: [
            XppStrokePoint(x: 0.0, y: 0.0, width: 14.14),
            XppStrokePoint(x: 100.5, y: 50.25, width: 14.14),
          ],
        ),

        // Eraser stroke
        XppStroke.byTool(
          tool: XppStrokeTool.ERASER,
          color: Colors.white,
          points: [
            XppStrokePoint(x: 5.12, y: 10.34, width: 8.0),
          ],
        ),
      ];

      for (var i = 0; i < strokes.length; i++) {
        final stroke = strokes[i];

        // 1. DOM serialization via toXmlElement
        final domXml = stroke.toXmlElement().toXmlString();

        // 2. Direct StringBuffer serialization via writeXml
        final buffer = StringBuffer();
        stroke.writeXml(buffer);
        final directXml = buffer.toString();

        final domDoc = XmlDocument.parse(domXml).rootElement;
        final directDoc = XmlDocument.parse(directXml).rootElement;

        // Verify XML tag name
        expect(directDoc.name.local, equals('stroke'));
        expect(domDoc.name.local, equals('stroke'));

        // Verify tool
        expect(directDoc.getAttribute('tool'), equals(domDoc.getAttribute('tool')));

        // Verify color
        expect(directDoc.getAttribute('color'), equals(domDoc.getAttribute('color')));

        // Verify flags
        expect(directDoc.getAttribute('osipp-shape'), equals(domDoc.getAttribute('osipp-shape')));
        expect(directDoc.getAttribute('osipp-smooth'), equals(domDoc.getAttribute('osipp-smooth')));
        expect(directDoc.getAttribute('osipp-width'), equals(domDoc.getAttribute('osipp-width')));

        // Verify erasures
        expect(directDoc.getAttribute('osipp-erasures'), equals(domDoc.getAttribute('osipp-erasures')));

        // Verify audio link (including XML attribute unescaping)
        expect(directDoc.getAttribute('osipp-audio-id'), equals(domDoc.getAttribute('osipp-audio-id')));
        expect(directDoc.getAttribute('osipp-audio-start'), equals(domDoc.getAttribute('osipp-audio-start')));
        expect(directDoc.getAttribute('osipp-audio-end'), equals(domDoc.getAttribute('osipp-audio-end')));
        expect(directDoc.getAttribute('osipp-audio-times'), equals(domDoc.getAttribute('osipp-audio-times')));

        // Verify widths within 3-decimal fixed point precision (0.001)
        final domWidths = (domDoc.getAttribute('width') ?? '')
            .split(' ')
            .where((s) => s.isNotEmpty)
            .map(double.parse)
            .toList();
        final directWidths = (directDoc.getAttribute('width') ?? '')
            .split(' ')
            .where((s) => s.isNotEmpty)
            .map(double.parse)
            .toList();
        expect(directWidths.length, equals(domWidths.length));
        for (var j = 0; j < domWidths.length; j++) {
          expect(directWidths[j], closeTo(domWidths[j], 0.001));
        }

        // Verify coordinates within 3-decimal fixed point precision (0.001)
        final domCoords = domDoc.innerText
            .split(' ')
            .where((s) => s.isNotEmpty)
            .map(double.parse)
            .toList();
        final directCoords = directDoc.innerText
            .split(' ')
            .where((s) => s.isNotEmpty)
            .map(double.parse)
            .toList();
        expect(directCoords.length, equals(domCoords.length));
        for (var j = 0; j < domCoords.length; j++) {
          expect(directCoords[j], closeTo(domCoords[j], 0.001));
        }
      }
    });

    test('XppFile serialization with writeXml round-trips correctly through parser', () async {
      final file = XppFile.empty(title: 'RoundTrip');
      final stroke = XppStroke.byTool(
        tool: XppStrokeTool.PEN,
        color: const Color(0xFF00AA55),
        isShape: true,
        smooth: true,
        widthIsDiameter: true,
        points: [
          XppStrokePoint(x: 10.123, y: 20.456, width: 1.5),
          XppStrokePoint(x: 30.789, y: 40.012, width: 2.5),
        ],
      )
        ..audioLink = StrokeAudioLink('sample_id', 50, 200, [50, 200])
        ..erasures = [
          StrokeErasure(const Offset(5, 5), const Offset(15, 15), 3.0),
        ];

      file.pages!.first.layers!.first.content!.add(stroke);

      final bytes = await file.toUint8ListAsync();
      final roundTrip = await XppFile.fromFilePickerCross(
        FilePickerCross(bytes),
        null,
        (_) async => FilePickerCross(Uint8List(0)),
      );

      final restoredPage = roundTrip.pages!.first;
      final restoredStroke = restoredPage.layers!.first.content!.first as XppStroke;

      expect(restoredStroke.tool, equals(XppStrokeTool.PEN));
      expect(restoredStroke.isShape, isTrue);
      expect(restoredStroke.smooth, isTrue);
      expect(restoredStroke.widthIsDiameter, isTrue);
      expect(restoredStroke.audioLink?.recordingId, equals('sample_id'));
      expect(restoredStroke.audioLink?.startMs, equals(50));
      expect(restoredStroke.audioLink?.endMs, equals(200));
      expect(restoredStroke.erasures.length, equals(1));
      expect(restoredStroke.points!.length, equals(2));
      expect(restoredStroke.points![0].x, closeTo(10.123, 0.001));
      expect(restoredStroke.points![0].y, closeTo(20.456, 0.001));
      expect(restoredStroke.points![0].width, closeTo(1.5, 0.001));
    });
  });
}

