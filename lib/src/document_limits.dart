import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

/// Shared import contract; configurable only by trusted callers, never by files.
class DocumentLimits {
  final int compressedBytes, xmlBytes, mediaBytes, nodes, pages, layers, points;
  const DocumentLimits({
    this.compressedBytes = 128 * 1024 * 1024,
    this.xmlBytes = 256 * 1024 * 1024,
    this.mediaBytes = 128 * 1024 * 1024,
    this.nodes = 250000,
    this.pages = 10000,
    this.layers = 50000,
    this.points = 1000000,
  });
  static const standard = DocumentLimits();
  static const maxPageDimension = 20000.0;
  static const maxCoordinate = 100000.0;
  static const maxWidth = 1000.0;
}

double documentNumber(
  String? value, {
  double min = -DocumentLimits.maxCoordinate,
  double max = DocumentLimits.maxCoordinate,
}) {
  final number = double.tryParse(value ?? '');
  if (number == null || !number.isFinite || number < min || number > max) {
    throw const FormatException(
      'Dimensione o coordinata del documento non valida',
    );
  }
  return number;
}

class DocumentImportBudget {
  final DocumentLimits limits;
  final Stopwatch _clock = Stopwatch()..start();
  int _media = 0, pointCount = 0, _nodes = 0, _pages = 0, _layers = 0;
  int get mediaBytes => _media;
  int get nodeCount => _nodes;
  int get pageCount => _pages;
  int get layerCount => _layers;
  DocumentImportBudget(this.limits);
  void checkTime() {
    if (_clock.elapsed > const Duration(seconds: 30)) {
      throw const FormatException('Importazione troppo complessa');
    }
  }

  Uint8List media(String text, {Uint8List? invalidFallback}) {
    checkTime();
    final remaining = limits.mediaBytes - _media;
    if (_estimatedMediaBytes(text) > remaining) {
      throw const FormatException('Allegati del documento troppo grandi');
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(text);
    } on FormatException {
      if (invalidFallback != null) return invalidFallback;
      rethrow;
    }
    _media += bytes.length;
    if (_media > limits.mediaBytes) {
      throw const FormatException('Allegati troppo grandi');
    }
    return bytes;
  }

  void reserveOptionalMedia(String text) {
    // Conservative preflight, without allocating a decoded copy. Optional
    // field decoders keep their own corruption handling after this quota.
    _media += _estimatedMediaBytes(text);
    if (_media > limits.mediaBytes) {
      throw const FormatException('Allegati troppo grandi');
    }
  }

  int _estimatedMediaBytes(String text) {
    var estimated = ((text.length + 3) ~/ 4) * 3;
    if (text.endsWith('==')) {
      estimated -= 2;
    } else if (text.endsWith('=')) {
      estimated--;
    }
    return estimated.clamp(0, limits.mediaBytes + 1);
  }

  void points(int count) {
    pointCount += count;
    if (pointCount > limits.points) {
      throw const FormatException('Troppi punti nel documento');
    }
  }

  /// Pull parser: only one root child (e.g. page) is materialized at a time.
  /// The first yielded element carries root attributes; it has no children.
  Iterable<XmlElement> elements(String text) sync* {
    var depth = 0;
    var events = <XmlEvent>[];
    final stack = <String>[];
    for (final event in parseEvents(
      text,
      validateNesting: true,
      validateDocument: true,
    )) {
      checkTime();
      if (++_nodes > limits.nodes) {
        throw const FormatException('Troppi nodi XML');
      }
      if (event is XmlDoctypeEvent) {
        throw const FormatException('DOCTYPE non consentito');
      }
      if (event is XmlStartElementEvent) {
        if (++depth > 16 || event.attributes.length > 32) {
          throw const FormatException('Struttura XML troppo complessa');
        }
        for (final a in event.attributes) {
          if (a.name.length > 128 || a.value.length > 1024 * 1024) {
            throw const FormatException('Attributo XML troppo grande');
          }
        }
        if (depth == 1) {
          if (event.name != 'xournal' || event.isSelfClosing) {
            throw const FormatException('Documento senza pagine');
          }
          yield XmlElement(XmlName('xournal'), [
            for (final a in event.attributes)
              XmlAttribute(XmlName(a.name), a.value),
          ]);
        } else {
          if (event.name == 'page' && ++_pages > limits.pages ||
              event.name == 'layer' && ++_layers > limits.layers) {
            throw const FormatException('Troppe pagine o livelli');
          }
          events.add(event);
        }
        if (event.isSelfClosing) {
          depth--;
        } else {
          stack.add(event.name);
        }
      } else if (event is XmlEndElementEvent) {
        if (depth > 1) events.add(event);
        depth--;
        stack.removeLast();
      } else if (depth > 1) {
        final value = event is XmlTextEvent
            ? event.value
            : event is XmlCDATAEvent
            ? event.value
            : '';
        if (value.length > 16 * 1024 * 1024 &&
            ![
              'pdf-attachment',
              'osipp-audio',
              'osipp-flashcard',
              'image',
            ].contains(stack.last)) {
          throw const FormatException('Testo XML troppo grande');
        }
        events.add(event);
      }
      if (depth == 1 && events.isNotEmpty) {
        final nodes = const XmlNodeDecoder().convert(events);
        events = [];
        for (final node in nodes.whereType<XmlElement>()) {
          yield node;
        }
      }
    }
    if (_pages == 0) throw const FormatException('Documento senza pagine');
  }
}

void validateDocumentJsonText(String text) {
  var depth = 0;
  var quoted = false, escaped = false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (c == 92) {
        escaped = true;
      } else if (c == 34) {
        quoted = false;
      }
    } else if (c == 34) {
      quoted = true;
    } else if (c == 91 || c == 123) {
      if (++depth > 32) throw const FormatException('JSON troppo profondo');
    } else if (c == 93 || c == 125) {
      depth--;
    }
  }
}
