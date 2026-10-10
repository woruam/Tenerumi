import 'dart:convert';

import 'note_audio.dart';
import 'note_flashcards.dart';

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:archive/archive.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:flutter/material.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppTexImage.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/pages/WorkspacePage.dart';
import 'package:xournalpp/src/HexColor.dart';
import 'package:xournalpp/src/PdfImage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/content_snapshot.dart';

import 'XppLayer.dart';
import 'XppPage.dart';

// Callback fittizio necessario per attraversare l'Isolate in sicurezza
Future<FilePickerCross> _dummyOnUnavailable(String? p) async =>
    throw Exception('Dummy');

class XppFile {
  XppFile({
    this.title,
    this.pages,
    this.previewImage,
    this.sourcePath,
    this.modifiedAt,
    this.tag,
    this.autoGeneratePages = false,
    String? documentId,
    Map<String, Uint8List>? pdfAttachments,
    Map<String, NoteRecording>? recordings,
    Map<String, NoteFlashcard>? flashcards,
  }) : documentId =
           (documentId != null &&
                   RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(documentId)
               ? documentId
               : null) ??
           '${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}',
       pdfAttachments = pdfAttachments ?? {},
       recordings = recordings ?? {},
       flashcards = flashcards ?? {};
  final String documentId;
  bool recovered = false;
  DateTime? modifiedAt;
  String? tag;
  bool autoGeneratePages;

  static XppFile empty({
    String? title,
    String? tag,
    XppPageSize? pageSize,
    Color? background,
    XppBackground Function(XppPageSize size)? template,
  }) {
    XppPageSize defaultSize =
        pageSize ?? XppPageSize(width: 595.28, height: 841.89);
    XppPage newPage = XppPage.empty(
      background: background,
      template: template?.call(defaultSize),
    );
    newPage.pageSize = defaultSize;
    if (newPage.background != null) {
      newPage.background!.size = defaultSize;
    }
    return XppFile(
      title: title,
      tag: tag,
      autoGeneratePages: true,
      pages: [newPage],
      modifiedAt: DateTime.now().toUtc(),
    );
  }

  static Future<XppFile> importPdf({required FilePickerCross pdf}) async {
    final pageCount = await pdfPageCount(pdf);
    final pdfName = pdf.path ?? 'background.pdf';
    XppFile file = XppFile.empty(title: titleFromPath(pdf.fileName))
      ..autoGeneratePages = false
      ..pages!.clear();
    file.pdfAttachments[pdfName] = pdf.toUint8List();
    Future<FilePickerCross> onUnavailable(String? p) async => pdf;

    for (int i = 0; i < pageCount; i++) {
      final size = await pdfPageSize(pdf, i);
      file.pages!.add(
        XppPage.empty()
          ..pageSize = size
          ..background = XppBackgroundPdf(
            onUnavailable: onUnavailable,
            page: i,
            filename: pdfName,
          ),
      );
    }
    return file;
  }

  static void openAndEdit({required BuildContext context}) async {
    ScaffoldFeatureController snackBarController = ScaffoldMessenger.of(context)
        .showSnackBar(
          SnackBar(
            duration: Duration(days: 999),
            content: Text(S.of(context).loadingFile),
          ),
        );
    XppFile file;
    try {
      file = await open(
        (percentage) => null,
        (_) async => throw Exception('File mancante'),
      );

      snackBarController.close();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => WorkspacePage(initialFile: file),
        ),
      );
    } catch (e) {
      snackBarController.close();
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(S.of(context).noFileSelected),
          content: Text(S.of(context).youDidNotSelectAnyFile),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).close),
            ),
          ],
        ),
      );
    }
  }

  static Future<XppFile> open(
    Function(double) percentageCallback,
    FileNotAvailableCallback onUnavailable,
  ) async {
    FilePickerCross rawFile = await FilePickerCross.importFromStorage(
      type: FileTypeCross.custom,
      fileExtension: 'xopp',
    );
    XppFile file = await fromFilePickerCross(
      rawFile,
      percentageCallback,
      onUnavailable,
    );
    return file;
  }

  /// -------------------------------------------------------------------------
  /// IL CUORE DELL'OTTIMIZZAZIONE: DECODIFICA E PARSING IN UN ISOLATE
  /// -------------------------------------------------------------------------
  static Future<XppFile> fromFilePickerCross(
    FilePickerCross rawFile,
    Function(double)? percentageCallback,
    FileNotAvailableCallback onUnavailable,
  ) async {
    if (percentageCallback != null) percentageCallback(0.0);

    // 1. Estraiamo il titolo e i byte puri SUL MAIN THREAD prima di inviarli
    final title = titleFromPath(rawFile.path);
    Uint8List fileBytes = rawFile.toUint8List();

    // 2. LANCIO DELL'ISOLATE: Tutto il codice qui dentro non blocca l'interfaccia
    // e pulirà la memoria RAM immediatamente appena finito!
    XppFile parsedFile = await compute(_parseFile, <String, Object?>{
      'title': title,
      'path': rawFile.path,
      'bytes': fileBytes,
    });

    for (final page in parsedFile.pages ?? <XppPage>[]) {
      final background = page.background;
      if (background is XppBackgroundPdf) {
        page.background = XppBackgroundPdf(
          onUnavailable: onUnavailable,
          filename: background.filename,
          page: background.page,
        );
      }
    }
    percentageCallback?.call(1.0);
    return parsedFile;
  }

  static XppFile _parseFile(Map<String, Object?> input) {
    List<int> bytes = GZipDecoder().decodeBytes(input['bytes'] as Uint8List);
    String fileText = utf8.decode(bytes);

    final documentTree = XmlDocument.parse(fileText)
        .findElements('xournal')
        .firstOrNull;
    if (documentTree == null) {
      throw const FormatException('Missing xournal root element');
    }

    Uint8List previewImage;
    try {
      final preview = documentTree.findElements('preview').firstOrNull;
      previewImage = preview == null
          ? kTransparentImage
          : base64Decode(preview.innerText);
    } catch (e) {
      previewImage = kTransparentImage;
    }

    final attachments = <String, Uint8List>{};
    for (final attachment in documentTree.findElements('pdf-attachment')) {
      final name = attachment.getAttribute('name');
      if (name != null)
        attachments[name] = base64Decode(attachment.innerText.trim());
    }
    String? previousPdfFilename;
    List<XppPage> pages = [];
    Iterable<XmlElement> pageElements = documentTree.findElements('page');

    for (XmlElement pageElement in pageElements) {
      XppPageSize pageSize = XppPageSize(
        width: double.parse(pageElement.getAttribute('width')!),
        height: double.parse(pageElement.getAttribute('height')!),
      );

      XppBackground? background;
      final backgroundElement = pageElement
          .findElements('background')
          .firstOrNull;
      if (backgroundElement != null) {
        switch (backgroundElement.getAttribute('type')) {
          case "pixmap":
            background = XppBackgroundImage(
              filename: backgroundElement.getAttribute('filename'),
            );
            break;
          case "pdf":
            previousPdfFilename =
                backgroundElement.getAttribute('filename') ??
                previousPdfFilename;
            background = XppBackgroundPdf(
              onUnavailable:
                  _dummyOnUnavailable, // <--- Funzione fittizia per sicurezza
              filename: previousPdfFilename,
              page: (int.parse(backgroundElement.getAttribute('pageno')!) - 1)
                  .clamp(0, 2147483647),
            );
            break;
          case "solid":
            switch (backgroundElement.getAttribute('style')) {
              case 'lined':
                background = XppBackgroundSolidLined(
                  size: pageSize,
                  color: parseColor(backgroundElement.getAttribute('color')),
                );
                break;
              case 'ruled':
                background = XppBackgroundSolidRuled(
                  size: pageSize,
                  color: parseColor(backgroundElement.getAttribute('color')),
                );
                break;
              case 'graph':
                background = XppBackgroundSolidGraph(
                  size: pageSize,
                  color: parseColor(backgroundElement.getAttribute('color')),
                );
                break;
              case 'plain':
                background = XppBackgroundSolidPlain(
                  size: pageSize,
                  color: parseColor(backgroundElement.getAttribute('color')),
                );
                break;
              case 'dotted':
                background = XppBackgroundSolidDot(
                  size: pageSize,
                  color: parseColor(backgroundElement.getAttribute('color')),
                );
                break;
              default:
                background = XppBackground.none;
            }
            break;
          default:
            background = XppBackground.none;
            break;
        }
      }

      List<XppLayer> layers = [];
      Iterable<XmlElement> layerElements = pageElement.findElements('layer');

      for (XmlElement layer in layerElements) {
        Map<int, XppContent?> content = {};
        int index = 0;
        layer.children.forEach((XmlNode node) {
          if (node.nodeType == XmlNodeType.TEXT) return;
          if (node.nodeType != XmlNodeType.ELEMENT) return;
          node.setAttribute('counter', index.toString());
          index++;
        });

        layer.findElements('image').forEach((imageElement) {
          content[int.parse(imageElement.getAttribute('counter')!)] = XppImage(
            data: base64Decode(imageElement.innerText.trim()),
            topLeft: Offset(
              double.parse(imageElement.getAttribute('left')!),
              double.parse(imageElement.getAttribute('top')!),
            ),
            bottomRight: Offset(
              double.parse(imageElement.getAttribute('right')!),
              double.parse(imageElement.getAttribute('bottom')!),
            ),
          );
        });

        layer.findElements('text').forEach((textElement) {
          Color color = parseColor(textElement.getAttribute('color'));
          content[int.parse(textElement.getAttribute('counter')!)] = XppText(
            color: color,
            text: textElement.innerText,
            size: XppPageSize.pt2mm(
              double.parse(textElement.getAttribute('size')!),
            ),
            fontFamily: textElement.getAttribute('font'),
            offset: Offset(
              double.parse(textElement.getAttribute('x')!),
              double.parse(textElement.getAttribute('y')!),
            ),
          );
        });

        layer.findElements('teximage').forEach((texElement) {
          content[int.parse(texElement.getAttribute('counter')!)] = XppTexImage(
            text: texElement.getAttribute('text')!.trim(),
            color: parseColor(texElement.getAttribute('color')!.trim()),
            topLeft: Offset(
              double.parse(texElement.getAttribute('left')!),
              double.parse(texElement.getAttribute('top')!),
            ),
            bottomRight: Offset(
              double.parse(texElement.getAttribute('right')!),
              double.parse(texElement.getAttribute('bottom')!),
            ),
          );
        });

        layer.findElements('stroke').forEach((strokeElement) {
          late XppStrokeTool tool;
          switch (strokeElement.getAttribute('tool')) {
            case "pen":
              tool = XppStrokeTool.PEN;
              break;
            case "eraser":
              return; // TODO: implement whiteout eraser
            case "highlighter":
              tool = XppStrokeTool.HIGHLIGHTER;
              break;
            default:
              return;
          }
          Color color = parseColor(strokeElement.getAttribute('color'));
          List<XppStrokePoint> points = [];
          List<String> rawWidth = strokeElement
              .getAttribute('width')!
              .trim()
              .split(RegExp(r'\s+'));
          List<String> rawPoints = strokeElement.innerText.trim().split(
            RegExp(r'\s+'),
          );
          for (int i = 0; i < rawPoints.length / 2; i++) {
            points.add(
              XppStrokePoint(
                width: double.parse(
                  (rawWidth.length > i) ? rawWidth[i] : rawWidth[0],
                ),
                x: double.parse(rawPoints[i * 2]),
                y: double.parse(rawPoints[i * 2 + 1]),
              ),
            );
          }
          if (points.isEmpty) return;
          content[int.parse(strokeElement.getAttribute('counter')!)] =
              XppStroke.byTool(
                  tool: tool,
                  color: color,
                  points: points,
                  isShape: strokeElement.getAttribute('osipp-shape') == 'true',
                  smooth: strokeElement.getAttribute('osipp-smooth') == 'true',
                )
                ..audioLink = StrokeAudioLink.decode(
                  strokeElement,
                  points.length,
                )
                ..erasures = StrokeErasure.decode(
                  strokeElement.getAttribute('osipp-erasures'),
                );
        });

        final ordered = content.keys.toList()..sort();
        layers.add(
          XppLayer(
            content: ordered.map((idx) => content[idx]).toList(),
            name: layer.getAttribute('name') ?? 'Livello ${layers.length + 1}',
            visible: layer.getAttribute('osipp-visible') != 'false',
            locked: layer.getAttribute('osipp-locked') == 'true',
          ),
        );
      }
      pages.add(
        XppPage(
          background: background,
          layers: layers.isEmpty ? [XppLayer.empty()] : layers,
          pageSize: pageSize,
          infinite: pageElement.getAttribute('osipp-infinite') == 'true',
        ),
      );
    }

    return XppFile(
      documentId: documentTree.getAttribute('osipp-id'),
      tag: documentTree.getAttribute('osipp-tag'),
      autoGeneratePages:
          documentTree.getAttribute('osipp-auto-pages') == 'true' ||
          (documentTree.getAttribute('osipp-auto-pages') == null &&
              !pages.any((p) => p.background is XppBackgroundPdf)),
      modifiedAt: DateTime.tryParse(
        documentTree.getAttribute('osipp-modified-at') ?? '',
      ),
      title: input['title'] as String,
      previewImage: previewImage,
      pages: pages,
      sourcePath: input['path'] as String?,
      pdfAttachments: attachments,
      flashcards: NoteFlashcard.decode(
        documentTree.findElements('osipp-flashcard'),
      ),
      recordings: NoteRecording.decode(
        documentTree.findElements('osipp-audio'),
      ),
    );
  }

  Uint8List? previewImage;
  @required
  List<XppPage>? pages;
  String? title;
  String? sourcePath;
  final Map<String, Uint8List> pdfAttachments;
  final Map<String, NoteRecording> recordings;
  final Map<String, NoteFlashcard> flashcards;

  static String titleFromPath(String? path) {
    final normalized = (path ?? '').replaceAll('\\', '/');
    final name = normalized.substring(normalized.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    final title = dot > 0 ? name.substring(0, dot) : name;
    return title.isEmpty ? 'Documento' : title;
  }

  String get suggestedFileName {
    final safe = (title ?? 'Documento')
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim();
    return '${safe.isEmpty ? 'Documento' : safe}.xopp';
  }

  XmlDocument toXmlDocument() {
    return XmlDocument([
      XmlElement(
        XmlName('xournal'),
        [
          XmlAttribute(XmlName('creator'), 'OSI'),
          XmlAttribute(XmlName('fileversion'), '4'),
          XmlAttribute(XmlName('osipp-id'), documentId),
          XmlAttribute(XmlName('osipp-auto-pages'), '$autoGeneratePages'),
          if (tag != null) XmlAttribute(XmlName('osipp-tag'), tag!),
          if (modifiedAt != null)
            XmlAttribute(
              XmlName('osipp-modified-at'),
              modifiedAt!.toUtc().toIso8601String(),
            ),
        ],
        [
            XmlElement(XmlName('title'), const [], [
              XmlText(
                'Xournal document - see http://math.mit.edu/~auroux/software/xournal/',
              ),
            ]),
            XmlElement(XmlName('preview'), const [], [
              XmlText(base64Encode(previewImage ?? kTransparentImage)),
            ]),
          ]
          ..addAll(
            pdfAttachments.entries.map(
              (entry) => XmlElement(
                XmlName('pdf-attachment'),
                [XmlAttribute(XmlName('name'), entry.key)],
                [XmlText(base64Encode(entry.value))],
              ),
            ),
          )
          ..addAll(recordings.values.map((e) => e.toXml()))
          ..addAll(flashcards.values.map((e) => e.toXml()))
          ..addAll(pages!.map((e) => e.toXmlElement())),
      ),
    ]);
  }

  String toXmlString() {
    return '<?xml version="1.0" standalone="no"?>\n' +
        toXmlDocument().toXmlString();
  }

  Uint8List? toUint8List() {
    return GZipEncoder().encodeBytes(utf8.encode(toXmlString()), level: 1);
  }

  FilePickerCross toFilePickerCross({String? filePath}) {
    Uint8List bytes = toUint8List()!;
    return FilePickerCross(
      bytes,
      type: FileTypeCross.custom,
      fileExtension: 'xopp',
      path: filePath,
    );
  }

  /// Keep decoded images and UI callbacks out of the isolate message.
  XppFile snapshot() {
    return XppFile(
      documentId: documentId,
      modifiedAt: modifiedAt,
      tag: tag,
      autoGeneratePages: autoGeneratePages,
      sourcePath: sourcePath,
      title: title,
      previewImage: previewImage,
      pdfAttachments: Map.of(pdfAttachments),
      recordings: Map.of(recordings),
      flashcards: Map.of(flashcards),
      pages: pages?.map((page) {
        final background = page.background;
        return XppPage(
          infinite: page.infinite,
          pageSize: page.pageSize,
          background: background is XppBackgroundPdf
              ? XppBackgroundPdf(
                  onUnavailable: _dummyOnUnavailable,
                  page: background.page,
                  filename: background.filename,
                )
              : background,
          layers: page.layers
              ?.map(
                (layer) => XppLayer(
                  name: layer.name,
                  visible: layer.visible,
                  locked: layer.locked,
                  content: layer.content
                      ?.whereType<XppContent>()
                      .map(cloneContent)
                      .toList(),
                ),
              )
              .toList(),
        );
      }).toList(),
    );
  }

  Future<Uint8List> toUint8ListAsync() => snapshot().serializeSnapshotAsync();

  /// Call on a frozen snapshot; avoids cloning the whole document a second time
  /// when attaching a thumbnail before serialization.
  Future<Uint8List> serializeSnapshotAsync() => compute(_serializeFile, this);

  static Uint8List _serializeFile(XppFile file) => file.toUint8List()!;

  Future<FilePickerCross> toFilePickerCrossAsync({String? filePath}) async =>
      FilePickerCross(
        await toUint8ListAsync(),
        type: FileTypeCross.custom,
        fileExtension: 'xopp',
        path: filePath,
      );
}

Color parseColor(String? colorString) {
  Color color = Colors.black;
  if (colorString != null) {
    switch (colorString) {
      case "black":
        break;
      case "blue":
        color = Colors.blue;
        break;
      case "red":
        color = Colors.red;
        break;
      case "green":
        color = Colors.green;
        break;
      case "gray":
      case "grey":
        color = Colors.grey;
        break;
      case "lightblue":
        color = Colors.lightBlue;
        break;
      case "lightgreen":
        color = Colors.lightGreen;
        break;
      case "magenta":
        color = Colors.purpleAccent;
        break;
      case "orange":
        color = Colors.orange;
        break;
      case "yellow":
        color = Colors.yellow;
        break;
      case "white":
        color = Colors.white;
        break;
      default:
        color = HexColor(colorString);
        break;
    }
  }
  return color;
}
