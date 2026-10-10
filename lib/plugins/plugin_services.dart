import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/document_export.dart';

import 'plugin_controller.dart';
import 'plugin_runtime.dart';
import 'plugin_http.dart';
import 'plugin_script.dart';

class PluginOutput {
  final String name;
  final Uint8List bytes;
  PluginOutput(this.name, this.bytes);
}

/// UI capabilities are supplied by the command's owner, never a global context.
class PluginHost {
  final void Function()? close;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic>)? form;
  final Future<Object?> Function(Map<String, dynamic>)? preview;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic>)? openFile;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? latex;
  final Future<Map<String, dynamic>> Function(Uint8List)? ocr;
  PluginHost({
    this.form,
    this.preview,
    this.openFile,
    this.latex,
    this.ocr,
    this.close,
  });
}

Uint8List pluginBytes(Map<String, dynamic> args) {
  if ((args['base64'] is String &&
          (args['base64'] as String).length > 11200000) ||
      (args['text'] is String &&
          (args['text'] as String).length > 8 * 1024 * 1024)) {
    throw StateError('File: massimo 8 MiB');
  }
  final bytes = args['base64'] is String
      ? base64Decode(args['base64'] as String)
      : Uint8List.fromList(utf8.encode(args['text'] as String? ?? ''));
  if (bytes.length > 8 * 1024 * 1024) throw StateError('File: massimo 8 MiB');
  return bytes;
}

Future<void> validatePluginImage(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width * descriptor.height > 4000000) {
        throw StateError('Immagine: massimo 4 milioni di pixel');
      }
      final codec = await descriptor.instantiateCodec();
      try {
        (await codec.getNextFrame()).image.dispose();
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

String ankiTsv(List cards, {String deck = 'OSIpp'}) {
  if (cards.isEmpty || cards.length > 10000) {
    throw StateError('Servono da 1 a 10000 flashcard');
  }
  String clean(String text) => text.replaceAll(RegExp(r'[\r\n\t]'), ' ');
  String html(Object? value) => '${value ?? ''}'
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', '<br>')
      .replaceAll('\t', '&#9;');
  final out = StringBuffer(
    '#separator:Tab\n#html:true\n#notetype:Basic\n#deck:${clean(deck)}\n#columns:Front\tBack\tTags\n#tags column:3\n',
  );
  for (final card in cards) {
    if (card is! Map ||
        card['front'] is! String ||
        card['back'] is! String ||
        (card['front'] as String).trim().isEmpty) {
      throw StateError('Ogni flashcard richiede front e back testuali');
    }
    out.writeln(
      '${html(card['front'])}\t${html(card['back'])}\t${clean('${card['tags'] ?? ''}')}',
    );
    if (out.length > 8 * 1024 * 1024) {
      throw StateError('Flashcard troppo grandi');
    }
  }
  return out.toString();
}

void registerPluginServices(PluginApi api, PluginSession? session) {
  PluginSession current() {
    if (session == null || !session.active) {
      throw StateError('Sessione terminata');
    }
    return session;
  }

  PluginHost host() =>
      current().host ??
      (throw StateError('Questo comando richiede l’interfaccia dell’app'));
  void output(String name, Uint8List bytes) {
    final s = current();
    if (name.isEmpty ||
        name.length > 120 ||
        RegExp(r'[/\\\x00-\x1f]').hasMatch(name) ||
        name == '.' ||
        name == '..') {
      throw StateError('Nome file non valido');
    }
    if (s.files.length >= 8 ||
        s.files.fold<int>(bytes.length, (n, f) => n + f.bytes.length) >
            16 * 1024 * 1024) {
      throw StateError('Troppi file da esportare');
    }
    s.files.add(PluginOutput(name, bytes));
  }

  api.register('files.export', {'export'}, (a) {
    output(a['name'] as String, pluginBytes(a));
    return null;
  });
  api.register('anki.export', {'export'}, (a) {
    final text = ankiTsv(
      a['cards'] as List,
      deck: a['deck'] as String? ?? 'OSIpp',
    );
    output(
      a['name'] as String? ?? 'flashcard.tsv',
      Uint8List.fromList(utf8.encode(text)),
    );
    return {'count': (a['cards'] as List).length};
  });
  api.register('files.open', {'files.read'}, (a) async {
    final callback =
        host().openFile ?? (throw StateError('Selettore file non disponibile'));
    final result = await callback(a);
    current();
    if (result != null) pluginBytes(result);
    return result;
  });
  api.register('ui.form', {'ui'}, (a) async {
    final callback =
        host().form ?? (throw StateError('Moduli non disponibili'));
    final result = await callback(a);
    current();
    return result;
  });
  api.register('ui.preview', {'ui'}, (a) async {
    final callback =
        host().preview ?? (throw StateError('Anteprime non disponibili'));
    final result = await callback(a);
    current();
    return result;
  });
  api.register('content.image', {'document.read'}, (a) {
    final s = current();
    final id = a['id'];
    if (id is! int ||
        id < 0 ||
        id >= s.content.length ||
        s.content[id] is! XppImage) {
      throw StateError('id deve indicare un’immagine');
    }
    final data = (s.content[id] as XppImage).data;
    if (data == null || data.length > 8 * 1024 * 1024) {
      throw StateError('Immagine assente o troppo grande');
    }
    return {'base64': base64Encode(data)};
  });
  api.register('page.render', {'document.read'}, (a) async {
    final s = current();
    final index = a['index'] ?? s.pageIndex;
    if (index is! int || index < 0 || index >= s.canvas.file!.pages!.length) {
      throw StateError('Indice pagina non valido');
    }
    final source = s.canvas.file!.pages![index];
    final page = XppPage(
      infinite: source.infinite,
      pageSize: source.pageSize,
      background: source.background,
      layers: index == s.pageIndex
          ? [
              for (var i = 0; i < source.layers!.length; i++)
                i == s.layerIndex
                    ? XppLayer(
                        content: s.content,
                        name: source.layers![i].name,
                        visible: source.layers![i].visible,
                        locked: source.layers![i].locked,
                      )
                    : source.layers![i],
            ]
          : source.layers,
    );
    final rendered = exportPageSnapshot(page);
    final background = await s.canvas.pluginPageBackground(index);
    current();
    if (background == null &&
        (source.background is XppBackgroundPdf ||
            source.background is XppBackgroundImage)) {
      throw StateError('Sfondo della pagina non disponibile');
    }
    final png = await rasterizeExportPage(
      rendered,
      backgroundBytes: background,
    );
    current();
    return {
      'base64': base64Encode(png),
      'width': rendered.pageSize!.width,
      'height': rendered.pageSize!.height,
    };
  });
  api.register(
    'document.pages',
    {'document.read'},
    (_) => [
      for (final (index, page) in current().canvas.file!.pages!.indexed)
        {
          'index': index,
          'width': page.pageSize!.width,
          'height': page.pageSize!.height,
          'layers': page.layers!.length,
          'infinite': page.infinite,
        },
    ],
  );
  api.register('latex.render', {}, (a) async {
    final callback =
        host().latex ?? (throw StateError('Rendering LaTeX non disponibile'));
    final result = await callback(a);
    current();
    return result;
  });
  api.register('ocr.recognize', {'ocr'}, (a) async {
    final bytes = pluginBytes(a);
    await validatePluginImage(bytes);
    current();
    final callback = current().host?.ocr ?? recognizePluginText;
    final result = await callback(bytes).timeout(const Duration(seconds: 45));
    current();
    return result;
  });
  api.register(
    'capabilities',
    {},
    (_) => {
      'actions': api.actions,
      'javascript': pluginJavaScriptAvailable && !kIsWeb,
      'ocr':
          current().host?.ocr != null ||
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
    },
  );
  api.register('http.request', {'network'}, (a) async {
    final s = current();
    final uri = Uri.parse(a['url'] as String);
    final hosts = s.plugin?.manifest['networkHosts'] as List? ?? [];
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        !hosts.contains(uri.host)) {
      throw StateError('Server HTTPS non dichiarato in networkHosts');
    }
    final method = a['method'] as String? ?? 'GET';
    if (!['GET', 'POST', 'PUT', 'PATCH', 'DELETE'].contains(method)) {
      throw StateError('Metodo HTTP non valido');
    }
    validatePluginHttpUri(uri, hosts.cast<String>());
    final client = createPluginHttpClient();
    s.cleanup.add(client.close);
    try {
      final request = http.Request(method, uri)..followRedirects = false;
      if (a['headers'] is Map) {
        validatePluginHttpHeaders(a['headers'] as Map);
        request.headers.addAll(Map<String, String>.from(a['headers'] as Map));
      }
      if (a['body'] is String) request.body = a['body'] as String;
      if (request.bodyBytes.length > 8 * 1024 * 1024) {
        throw StateError('Richiesta troppo grande');
      }
      Future<Map<String, dynamic>> receive() async {
        final response = await client.send(request);
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          current();
          if (bytes.length + chunk.length > 8 * 1024 * 1024) {
            throw StateError('Risposta troppo grande');
          }
          bytes.add(chunk);
        }
        current();
        final data = bytes.takeBytes();
        return {
          'status': response.statusCode,
          'headers': response.headers,
          'text': utf8.decode(data, allowMalformed: true),
          'base64': base64Encode(data),
        };
      }

      return await receive().timeout(const Duration(seconds: 20));
    } finally {
      s.cleanup.remove(client.close);
      client.close();
    }
  });
}

Future<Map<String, dynamic>> recognizePluginText(Uint8List bytes) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    throw UnsupportedError(
      'OCR locale disponibile su Android. Su altre piattaforme usare un provider tramite http.request o l’SDK.',
    );
  }
  final result = await const MethodChannel('online.xournal.mobile/ocr')
      .invokeMapMethod<String, dynamic>('recognize', {'bytes': bytes});
  if (result == null) throw StateError('OCR senza risultato');
  return result;
}
