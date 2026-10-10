import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

abstract final class FlashcardLimits {
  static const maxCards = 10000;
  static const maxEncodedBytes = 64 * 1024 * 1024;
  static const maxCropBytes = 8 * 1024 * 1024;
  static void validate(
    Iterable<NoteFlashcard> cards, {
    int byteLimit = maxEncodedBytes,
  }) {
    var count = 0, bytes = 0;
    final ids = <String>{};
    for (final card in cards) {
      if (++count > maxCards ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(card.id) ||
          !ids.add(card.id))
        throw const FormatException('Flashcard duplicate o troppo numerose');
      for (final side in [card.front, card.back]) {
        if (side.page < 0 ||
            side.page >= 10000 ||
            (side.image?.length ?? 0) > maxCropBytes)
          throw const FormatException(
            'Ritaglio o pagina della flashcard oltre il limite',
          );
        // Reject before base64/JSON allocation. Escaping may add another factor 6.
        if (side.text.length > byteLimit ||
            ((side.image?.length ?? 0) + 2) ~/ 3 * 4 > byteLimit)
          throw const FormatException('Flashcard troppo grande');
      }
      bytes += utf8.encode(jsonEncode(card.toJson())).length;
      if (bytes > byteLimit)
        throw const FormatException(
          'Le flashcard superano il limite di 64 MiB',
        );
    }
  }
}

/// A selected region retains both editable text and its original appearance.
class FlashcardSide {
  final String text;
  final Uint8List? image;
  final int page;
  FlashcardSide({this.text = '', Uint8List? image, this.page = 0})
    : image = image?.asUnmodifiableView();
  Map<String, dynamic> toJson() => {
    'text': text,
    'page': page,
    if (image != null) 'image': base64Encode(image!),
  };
  factory FlashcardSide.fromJson(Map value) {
    final image = value['image'];
    if (image != null &&
        (image is! String ||
            image.length > ((FlashcardLimits.maxCropBytes + 2) ~/ 3) * 4))
      throw const FormatException('Ritaglio troppo grande');
    return FlashcardSide(
      text: value['text'] as String? ?? '',
      page: value['page'] as int? ?? 0,
      image: value['image'] == null
          ? null
          : base64Decode(value['image'] as String),
    );
  }
}

class NoteFlashcard {
  final String id;
  final FlashcardSide front, back;
  NoteFlashcard({String? id, required this.front, required this.back})
    : id =
          id ??
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  Map<String, dynamic> toJson() => {
    'id': id,
    'front': front.toJson(),
    'back': back.toJson(),
  };
  XmlElement toXml() => XmlElement(XmlName('osipp-flashcard'), [], [
    XmlText(jsonEncode(toJson())),
  ]);
  static Map<String, NoteFlashcard> decode(
    Iterable<XmlElement> elements, {
    List<String>? warnings,
  }) {
    final cards = <String, NoteFlashcard>{};
    var total = 0;
    for (final e in elements) {
      try {
        if (cards.length >= FlashcardLimits.maxCards)
          throw const FormatException('Troppe schede');
        total += utf8.encode(e.innerText).length;
        if (total > FlashcardLimits.maxEncodedBytes)
          throw const FormatException('Schede troppo grandi');
        final v = jsonDecode(e.innerText) as Map;
        final id = v['id'] as String;
        if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id) ||
            cards.containsKey(id))
          throw const FormatException('ID invalido o duplicato');
        final card = NoteFlashcard(
          id: id,
          front: FlashcardSide.fromJson(v['front'] as Map),
          back: FlashcardSide.fromJson(v['back'] as Map),
        );
        FlashcardLimits.validate([card]);
        cards[id] = card;
      } catch (_) {
        warnings?.add(
          'Flashcard recuperate solo parzialmente: salvare una copia',
        );
      }
    }
    return cards;
  }
}

String flashcardsJson(Iterable<NoteFlashcard> cards, String deck) {
  FlashcardLimits.validate(cards);
  return const JsonEncoder.withIndent('  ').convert({
    'format': 'osipp.flashcards',
    'version': 1,
    'deck': deck,
    'cards': cards.map((c) => c.toJson()).toList(),
  });
}

/// Anki imports UTF-8 tab-separated text and media from collection.media.
/// JSON is an OSIpp backup, never presented as a native Anki import format.
Uint8List flashcardsAnkiBundle(Iterable<NoteFlashcard> cards, String deck) {
  FlashcardLimits.validate(cards);
  final archive = Archive();
  String clean(String v) => v.replaceAll(RegExp(r'[\r\n\t]'), ' ');
  String html(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', '<br>')
      .replaceAll('\t', '&#9;');
  String field(NoteFlashcard card, FlashcardSide side, String name) {
    // Typed corrections supersede the crop; blank text preserves handwriting/PDF.
    if (side.text.trim().isNotEmpty) return html(side.text);
    if (side.image == null) return '';
    final filename = 'osipp_${card.id}_$name.png';
    archive.addFile(
      ArchiveFile('media/$filename', side.image!.length, side.image!),
    );
    return '<img src="$filename">';
  }

  final out = StringBuffer(
    '#separator:Tab\n#html:true\n#notetype:Basic\n'
    '#deck:${clean(deck)}\n#columns:Front\tBack\n',
  );
  for (final card in cards) {
    out.writeln(
      '${field(card, card.front, 'front')}\t${field(card, card.back, 'back')}',
    );
  }
  void addText(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addText('flashcard.txt', out.toString());
  addText('flashcard.json', flashcardsJson(cards, deck));
  addText(
    'LEGGIMI.txt',
    'Importazione in Anki:\n'
        '1. Estrai questo archivio ZIP.\n'
        '2. Copia i file della cartella media nella cartella collection.media di Anki.\n'
        '3. Importa flashcard.txt in Anki: tipo Basic, campi Front e Back, HTML attivo.\n'
        'flashcard.json conserva il set e le immagini per OSIpp.\n'
        'Anki confronta il fronte per aggiornare le carte: se cambi il titolo, '
        'rimuovi la vecchia carta in Anki prima di reimportare.\n',
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}
