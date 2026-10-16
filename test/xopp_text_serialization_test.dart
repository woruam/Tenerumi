import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/layer_contents/XppTexImage.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const samples = <String>[
    '<a>&b > c "quotes" \'apostrophes\'',
    'Caffè — 中文 🖊️\nseconda riga\tcolonna',
    '&lt; &gt; &amp; &quot; &#60; &#x3C; &unknown;',
    'fine ]]> inizio',
    '',
  ];

  for (var index = 0; index < samples.length; index++) {
    final text = samples[index];
    test('XOPP text sample $index survives DOM and streamed saves', () async {
      final file = XppFile.empty(title: 'Testo');
      file.pages!.single.layers!.single.content!.addAll([
        XppText(
          text: text,
          color: Colors.black,
          size: 12,
          offset: const Offset(1, 2),
        ),
        XppTexImage(
          text: text,
          color: Colors.black,
          topLeft: const Offset(1, 2),
          bottomRight: const Offset(101, 26),
        ),
      ]);

      final domXml = file.toXmlDocument().toXmlString();
      final streamedBytes = await file.toUint8ListAsync();
      final streamedXml = utf8.decode(GZipDecoder().decodeBytes(streamedBytes));
      for (final xml in [domXml, streamedXml]) {
        final document = XmlDocument.parse(xml);
        expect(document.findAllElements('text').single.innerText, text);
        final formula = document.findAllElements('teximage').single;
        expect(formula.innerText, text);
        expect(formula.getAttribute('text'), text);
      }

      for (final bytes in [
        Uint8List.fromList(GZipEncoder().encode(utf8.encode(domXml))),
        streamedBytes,
      ]) {
        var current = bytes;
        // A second save must not progressively escape already literal entities.
        for (var cycle = 0; cycle < 2; cycle++) {
          final reopened = await XppFile.fromFilePickerCross(
            FilePickerCross(current),
            null,
            (_) async => throw StateError('No external attachments'),
          );
          final content = reopened.pages!.single.layers!.single.content!;
          expect((content[0] as XppText).text, text);
          expect((content[1] as XppTexImage).text, text);
          current = await reopened.toUint8ListAsync();
        }
      }
    });
  }
}
