import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';

import 'XppFile.dart';
import 'XppLayer.dart';
import 'XppPage.dart';
import 'critical_data.dart';
import 'compat/file_picker_cross.dart';
import 'document_limits.dart';
import 'note_audio.dart';
import 'note_flashcards.dart';

class _StrokeFragment {
  _StrokeFragment(this.hash, this.bytes, XppStroke stroke)
    : color = stroke.color,
      tool = stroke.tool,
      shape = stroke.isShape,
      smooth = stroke.smooth,
      audio = stroke.audioLink,
      cuts = List.of(stroke.erasures);
  final String hash;
  final int bytes;
  final Object? color;
  final XppStrokeTool tool;
  final bool shape, smooth;
  final StrokeAudioLink? audio;
  final List<StrokeErasure> cuts;
  bool matches(XppStroke stroke) =>
      color == stroke.color &&
      tool == stroke.tool &&
      shape == stroke.isShape &&
      smooth == stroke.smooth &&
      identical(audio, stroke.audioLink) &&
      listEquals(cuts, stroke.erasures);
}

/// Content-addressed, complete recovery manifests. Unchanged immutable ink
/// reuses its previous fragment; media is stored once outside XML/base64/GZIP.
abstract final class RecoveryJournal {
  static final _strokes = Expando<Map<String, _StrokeFragment>>();
  static int writtenFragments = 0, reusedFragments = 0;
  static int _xmlBytes = 0;
  static Future<String> _fragment(XppContent content, String localId) async {
    if (content is XppStroke && content.points != null) {
      final cached = _strokes[content.points!]?[localId];
      if (cached != null &&
          cached.matches(content) &&
          await CriticalData.hasBlob(cached.hash)) {
        reusedFragments++;
        _xmlBytes += cached.bytes;
        if (_xmlBytes > 64 * 1024 * 1024)
          throw StateError('Recupero XML troppo grande');
        return cached.hash;
      }
    }
    XmlElement xml;
    if (content is XppImage) {
      if (content.data == null) throw StateError('Immagine senza dati');
      final blob = await CriticalData.putBlob(content.data!);
      xml = XppImage(
        data: Uint8List(0),
        topLeft: content.topLeft,
        bottomRight: content.bottomRight,
      ).toXmlElement();
      xml.setAttribute('osipp-blob', blob);
    } else {
      xml = content.toXmlElement();
    }
    final bytes = Uint8List.fromList(utf8.encode(xml.toXmlString()));
    if (bytes.length > 32 * 1024 * 1024)
      throw StateError('Frammento di recupero troppo grande');
    _xmlBytes += bytes.length;
    if (_xmlBytes > 64 * 1024 * 1024)
      throw StateError('Recupero XML troppo grande');
    final hash = await CriticalData.putBlob(bytes);
    writtenFragments++;
    if (content is XppStroke && content.points != null) {
      (_strokes[content.points!] ??= {})[localId] = _StrokeFragment(
        hash,
        bytes.length,
        content,
      );
    }
    return hash;
  }

  static Future<String> write(XppFile snapshot) async {
    snapshot.validateSaveLimits();
    _xmlBytes = 0;
    var contentNodes = 0;
    FlashcardLimits.validate(snapshot.flashcards.values);
    final pages = <Map<String, dynamic>>[];
    var count = 0;
    for (final page in snapshot.pages ?? <XppPage>[]) {
      if (++count > DocumentLimits.standard.pages)
        throw StateError('Troppe pagine');
      final layers = <Map<String, dynamic>>[];
      for (final layer in page.layers ?? <XppLayer>[]) {
        final content = <String>[];
        for (final item
            in layer.content?.whereType<XppContent>() ?? <XppContent>[]) {
          if (++contentNodes > 200000)
            throw StateError('Troppi contenuti nel recupero');
          content.add(await _fragment(item, snapshot.localId));
        }
        layers.add({
          'name': layer.name,
          'visible': layer.visible,
          'locked': layer.locked,
          'content': content,
        });
      }
      pages.add({
        'shell': XppPage(
          pageSize: page.pageSize,
          background: page.background,
          layers: [],
          infinite: page.infinite,
        ).toXmlElement().toXmlString(),
        'layers': layers,
      });
    }
    final pdfs = <String, String>{},
        recordings = <Map<String, dynamic>>[],
        cards = <Map<String, dynamic>>[];
    for (final e in snapshot.pdfAttachments.entries) {
      pdfs[e.key] = await CriticalData.putBlob(e.value);
    }
    for (final rec in snapshot.recordings.values) {
      recordings.add({
        'id': rec.id,
        'duration': rec.durationMs,
        'blob': await CriticalData.putBlob(rec.bytes),
      });
    }
    for (final card in snapshot.flashcards.values) {
      Future<Map<String, dynamic>> side(FlashcardSide value) async => {
        'text': value.text,
        'page': value.page,
        if (value.image != null)
          'blob': await CriticalData.putBlob(value.image!),
      };
      cards.add({
        'id': card.id,
        'front': await side(card.front),
        'back': await side(card.back),
      });
    }
    final value = {
      'schema': 3,
      'id': snapshot.documentId,
      'localId': snapshot.localId,
      'title': snapshot.title,
      'tag': snapshot.tag,
      'source': snapshot.sourcePath,
      'baseHash': snapshot.originHash,
      'modifiedAt': snapshot.modifiedAt?.toIso8601String(),
      'auto': snapshot.autoGeneratePages,
      'warnings': snapshot.importWarnings,
      'pages': pages,
      'pdfs': pdfs,
      'audio': recordings,
      'cards': cards,
      if (snapshot.previewImage != null)
        'preview': await CriticalData.putBlob(snapshot.previewImage!),
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    if (bytes.length > 16 * 1024 * 1024)
      throw StateError('Manifesto del recupero troppo grande');
    return CriticalData.putBlob(bytes);
  }

  static Future<XppFile> read(String hash) async {
    final manifest = await CriticalData.getBlob(hash);
    if (manifest.length > 16 * 1024 * 1024)
      throw const FormatException('Manifesto troppo grande');
    final text = utf8.decode(manifest);
    validateDocumentJsonText(text);
    final v = jsonDecode(text) as Map;
    if (v['schema'] != 3 ||
        v['pages'] is! List ||
        (v['pages'] as List).isEmpty ||
        (v['pages'] as List).length > 10000)
      throw const FormatException('Schema di recupero non supportato');
    final pages = <XppPage>[];
    var xmlBudget = 64 * 1024 * 1024,
        mediaBudget = 128 * 1024 * 1024,
        points = 0,
        nodes = 0,
        layers = 0;
    Future<Uint8List> media(String hash) async {
      final bytes = await CriticalData.getBlob(hash);
      mediaBudget -= bytes.length;
      if (mediaBudget < 0) throw const FormatException('Troppi allegati');
      return bytes;
    }

    for (final page in v['pages'] as List) {
      final shell = XmlDocument.parse(page['shell'] as String).rootElement;
      for (final layer in page['layers'] as List) {
        final children = <XmlNode>[];
        for (final id in layer['content'] as List) {
          final bytes = await CriticalData.getBlob(id as String);
          xmlBudget -= bytes.length;
          if (xmlBudget < 0)
            throw const FormatException('Recupero XML troppo grande');
          children.add(
            XmlDocument.parse(utf8.decode(bytes)).rootElement.copy(),
          );
        }
        shell.children.add(
          XmlElement(XmlName('layer'), [
            XmlAttribute(XmlName('name'), layer['name'] as String),
            XmlAttribute(XmlName('osipp-visible'), '${layer['visible']}'),
            XmlAttribute(XmlName('osipp-locked'), '${layer['locked']}'),
          ], children),
        );
      }
      final images = shell
          .findAllElements('image')
          .map((e) => e.getAttribute('osipp-blob'))
          .toList();
      final xml = '<xournal fileversion="4">${shell.toXmlString()}</xournal>';
      final parsed = await XppFile.fromFilePickerCross(
        FilePickerCross(
          Uint8List.fromList(GZipEncoder().encodeBytes(utf8.encode(xml))),
        ),
        null,
        (_) async => throw StateError('Sfondo mancante'),
        limits: DocumentLimits(
          xmlBytes: 64 * 1024 * 1024,
          nodes: 250000 - nodes,
          points: 1000000 - points,
          layers: 50000 - layers,
        ),
      );
      points += parsed.importedPoints;
      nodes += parsed.importedNodes;
      layers += parsed.importedLayers;
      final result = parsed.pages!.single;
      var imageIndex = 0;
      for (final layer in result.layers!) {
        for (var i = 0; i < layer.content!.length; i++) {
          final item = layer.content![i];
          if (item is XppImage) {
            final id = images[imageIndex++];
            if (id == null)
              throw const FormatException('Immagine priva di blob');
            layer.content![i] = XppImage(
              data: await media(id),
              topLeft: item.topLeft,
              bottomRight: item.bottomRight,
            );
          }
        }
      }
      pages.add(result);
    }
    final attachments = <String, Uint8List>{};
    for (final e in (v['pdfs'] as Map).entries) {
      attachments[e.key as String] = await media(e.value as String);
    }
    final audio = <String, NoteRecording>{};
    for (final r in v['audio'] as List) {
      final id = r['id'] as String, duration = r['duration'] as int;
      final bytes = await media(r['blob'] as String);
      if (!validAudioId(id) ||
          duration <= 0 ||
          duration > maxRecordingMs + 5000 ||
          bytes.length > maxRecordingBytes)
        throw const FormatException('Audio di recupero invalido');
      audio[id] = NoteRecording(id, duration, bytes);
    }
    final cards = <String, NoteFlashcard>{};
    for (final c in v['cards'] as List) {
      Future<FlashcardSide> side(Map s) async => FlashcardSide(
        text: s['text'] as String,
        page: s['page'] as int,
        image: s['blob'] == null ? null : await media(s['blob'] as String),
      );
      final card = NoteFlashcard(
        id: c['id'] as String,
        front: await side(c['front'] as Map),
        back: await side(c['back'] as Map),
      );
      if (cards.containsKey(card.id))
        throw const FormatException('Scheda duplicata');
      cards[card.id] = card;
    }
    FlashcardLimits.validate(cards.values);
    return XppFile(
      documentId: v['id'] as String,
      localId: v['localId'] as String,
      title: v['title'] as String?,
      tag: v['tag'] as String?,
      sourcePath: v['source'] as String?,
      originHash: v['baseHash'] as String?,
      modifiedAt: DateTime.tryParse(v['modifiedAt'] as String? ?? ''),
      autoGeneratePages: v['auto'] == true,
      importWarnings: (v['warnings'] as List).cast<String>(),
      pages: pages,
      pdfAttachments: attachments,
      recordings: audio,
      flashcards: cards,
      previewImage: v['preview'] == null
          ? null
          : await media(v['preview'] as String),
    );
  }
}
