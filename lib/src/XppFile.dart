import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'note_audio.dart';
import 'note_flashcards.dart';
import 'document_limits.dart';
import 'bounded_archive.dart';
import 'compat/xml_compression_web.dart'
    if (dart.library.io) 'compat/xml_compression_io.dart'
    as compression;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';

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
    String? localId,
    this.originHash,
    List<String>? importWarnings,
    Map<String, Uint8List>? pdfAttachments,
    Map<String, NoteRecording>? recordings,
    Map<String, NoteFlashcard>? flashcards,
  }) : documentId =
           (documentId != null &&
                   RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(documentId)
               ? documentId
               : null) ??
           '${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}',
       localId =
           localId ??
           '${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}',
       importWarnings = importWarnings ?? [],
       pdfAttachments = pdfAttachments ?? {},
       recordings = recordings ?? {},
       flashcards = flashcards ?? {};
  final String documentId;
  String localId;
  String? originHash;
  final List<String> importWarnings;
  bool get requiresSaveCopy => importWarnings.isNotEmpty;

  /// This identity is never read from XML and never grants access to a path.
  String get recoveryKey => recoveryKeyFor(sourcePath, localId);
  static String recoveryKeyFor(String? path, String localId) {
    if (path == null || path.isEmpty) return 'local-$localId';
    var normalized = path.replaceAll('\\', '/');
    if (RegExp(r'^[a-zA-Z]:/').hasMatch(normalized) ||
        normalized.startsWith('//'))
      normalized = normalized.toLowerCase();
    return 'origin-${sha256.convert(utf8.encode(normalized))}-local-$localId';
  }

  bool recovered = false;
  DateTime? modifiedAt;
  String? tag;
  bool autoGeneratePages;
  int importedXmlBytes = 0,
      importedMediaBytes = 0,
      importedNodes = 0,
      importedPoints = 0,
      importedPages = 0,
      importedLayers = 0;

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

  static Future<XppFile> importPdf({
    required FilePickerCross pdf,
    DocumentLimits limits = DocumentLimits.standard,
  }) async {
    final bytes = pdf.toUint8List();
    if (bytes.length > limits.compressedBytes ||
        bytes.length > limits.mediaBytes) {
      throw const FormatException('PDF troppo grande');
    }
    final sizes = await pdfPageSizes(pdf, limits: limits);
    final pdfName = pdf.path ?? 'background.pdf';
    XppFile file = XppFile.empty(title: titleFromPath(pdf.fileName))
      ..autoGeneratePages = false
      ..pages!.clear();
    file.pdfAttachments[pdfName] = bytes;
    Future<FilePickerCross> onUnavailable(String? p) async => pdf;

    for (int i = 0; i < sizes.length; i++) {
      final size = sizes[i];
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
      fileExtension: 'xopp,pdf',
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
    FileNotAvailableCallback onUnavailable, {
    DocumentLimits limits = DocumentLimits.standard,
  }) async {
    if (percentageCallback != null) percentageCallback(0.0);

    // 1. Estraiamo il titolo e i byte puri SUL MAIN THREAD prima di inviarli
    final title = titleFromPath(rawFile.path);
    Uint8List fileBytes = rawFile.toUint8List();
    if (fileBytes.length > limits.compressedBytes) {
      throw const FormatException('Appunto troppo grande');
    }

    // PDF exports from older versions are actual PDFs, not gzip archives.
    // Route by content so a renamed Xournal document still uses bounded gzip.
    if (_hasPdfHeader(fileBytes)) {
      final file = await importPdf(pdf: rawFile, limits: limits);
      percentageCallback?.call(1.0);
      return file;
    }

    // 2. LANCIO DELL'ISOLATE: Tutto il codice qui dentro non blocca l'interfaccia
    // e pulirà la memoria RAM immediatamente appena finito!
    XppFile parsedFile = await compute(_parseFile, <String, Object?>{
      'title': title,
      'path': rawFile.path,
      'bytes': fileBytes,
      'limits': limits,
    });

    for (final page in parsedFile.pages ?? <XppPage>[]) {
      final background = page.background;
      if (background is XppBackgroundPdf) {
        page.background = XppBackgroundPdf(
          // Document names are opaque attachment keys, never local grants.
          onUnavailable: (name) async {
            final bytes = parsedFile.pdfAttachments[name];
            if (bytes == null) {
              throw StateError('Seleziona l’allegato di sfondo');
            }
            return FilePickerCross(bytes);
          },
          filename: background.filename,
          page: background.page,
        );
      } else if (background is XppBackgroundImage) {
        page.background = XppBackgroundImage(
          filename: background.filename,
          data: parsedFile.pdfAttachments[background.filename],
        );
      }
    }
    percentageCallback?.call(1.0);
    return parsedFile;
  }

  static bool _hasPdfHeader(Uint8List bytes) =>
      bytes.length >= 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46 &&
      bytes[4] == 0x2d;

  static XppFile _parseFile(Map<String, Object?> input) {
    final limits = input['limits'] as DocumentLimits;
    final budget = DocumentImportBudget(limits);
    List<int> bytes = decodeBoundedGzip(
      input['bytes'] as Uint8List,
      maxInput: limits.compressedBytes,
      maxOutput: limits.xmlBytes,
    );
    String fileText = utf8.decode(bytes);
    final elements = budget.elements(fileText).iterator;
    if (!elements.moveNext()) {
      throw const FormatException('Missing xournal root element');
    }
    final documentTree = elements.current;
    final warnings = <String>[];
    void warn(String value) {
      if (warnings.contains(value)) return;
      if (warnings.length < 64)
        warnings.add(value);
      else if (!warnings.contains('Altri contenuti non supportati'))
        warnings.add('Altri contenuti non supportati');
    }

    void attributes(XmlElement element, Set<String> supported) {
      if (element.attributes.any((a) => !supported.contains(a.name.qualified)))
        warn('Attributi non supportati in ${element.name.local}');
    }

    attributes(documentTree, {
      'creator',
      'fileversion',
      'osipp-id',
      'osipp-tag',
      'osipp-auto-pages',
      'osipp-modified-at',
    });
    final version = documentTree.getAttribute('fileversion');
    if (version != null && version != '4')
      warn('Versione Xournal non supportata: $version');
    Uint8List previewImage = kTransparentImage;
    final attachments = <String, Uint8List>{};
    final audioElements = <XmlElement>[], cardElements = <XmlElement>[];
    String? previousPdfFilename;
    List<XppPage> pages = [];
    while (elements.moveNext()) {
      final pageElement = elements.current;
      switch (pageElement.name.local) {
        case 'preview':
          previewImage = budget.media(
            pageElement.innerText.trim(),
            invalidFallback: kTransparentImage,
          );
          continue;
        case 'pdf-attachment':
          final name = pageElement.getAttribute('name');
          if (name == null ||
              name.isEmpty ||
              name.length > 4096 ||
              attachments.containsKey(name)) {
            throw const FormatException('Allegato duplicato o senza nome');
          }
          attachments[name] = budget.media(pageElement.innerText.trim());
          continue;
        case 'osipp-audio':
          // Count before optional decoder allocates the media a second time.
          budget.reserveOptionalMedia(pageElement.innerText.trim());
          audioElements.add(pageElement);
          continue;
        case 'osipp-flashcard':
          validateDocumentJsonText(pageElement.innerText);
          Object? json;
          try {
            json = jsonDecode(pageElement.innerText);
          } on FormatException {
            /* Optional corruption remains recoverable. */
          }
          if (json is Map) {
            for (final side in ['front', 'back']) {
              final value = json[side];
              if (value is Map && value['image'] is String) {
                budget.reserveOptionalMedia(value['image'] as String);
              }
            }
          }
          cardElements.add(pageElement);
          continue;
        case 'page':
          break;
        default:
          if (pageElement.name.local != 'title')
            warn('Elemento non supportato: ${pageElement.name.local}');
          continue;
      }
      XppPageSize pageSize = XppPageSize(
        width: documentNumber(
          pageElement.getAttribute('width'),
          min: 0.01,
          max: DocumentLimits.maxPageDimension,
        ),
        height: documentNumber(
          pageElement.getAttribute('height'),
          min: 0.01,
          max: DocumentLimits.maxPageDimension,
        ),
      );
      attributes(pageElement, {'width', 'height', 'osipp-infinite'});

      XppBackground? background;
      final backgroundElement = pageElement
          .findElements('background')
          .firstOrNull;
      if (backgroundElement != null) {
        attributes(backgroundElement, {
          'type',
          'domain',
          'filename',
          'pageno',
          'style',
          'color',
        });
        switch (backgroundElement.getAttribute('type')) {
          case "pixmap":
            if (backgroundElement.getAttribute('filename')?.isNotEmpty !=
                true) {
              throw const FormatException('Sfondo senza riferimento');
            }
            background = XppBackgroundImage(
              filename: backgroundElement.getAttribute('filename'),
            );
            break;
          case "pdf":
            previousPdfFilename =
                backgroundElement.getAttribute('filename') ??
                previousPdfFilename;
            final pdfPage = int.tryParse(
              backgroundElement.getAttribute('pageno') ?? '',
            );
            if (pdfPage == null ||
                pdfPage < 1 ||
                pdfPage > limits.pages ||
                previousPdfFilename == null) {
              throw const FormatException(
                'Riferimento alla pagina PDF non valido',
              );
            }
            background = XppBackgroundPdf(
              onUnavailable:
                  _dummyOnUnavailable, // <--- Funzione fittizia per sicurezza
              filename: previousPdfFilename,
              page: pdfPage - 1,
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
                warn('Stile di sfondo non supportato');
                background = XppBackground.none;
            }
            break;
          default:
            warn('Tipo di sfondo non supportato');
            background = XppBackground.none;
            break;
        }
      }

      List<XppLayer> layers = [];
      for (final child in pageElement.childElements) {
        if (!['background', 'layer'].contains(child.name.local))
          warn('Elemento della pagina non supportato: ${child.name.local}');
      }
      Iterable<XmlElement> layerElements = pageElement.findElements('layer');

      for (XmlElement layer in layerElements) {
        attributes(layer, {'name', 'osipp-visible', 'osipp-locked'});
        final content = <XppContent>[];
        // Visit each element once; XML order is the painting order.
        for (final node in layer.childElements) {
          attributes(node, switch (node.name.local) {
            'stroke' => {
              'tool',
              'color',
              'width',
              'osipp-shape',
              'osipp-smooth',
              'osipp-erasures',
              'osipp-audio-id',
              'osipp-audio-start',
              'osipp-audio-end',
              'osipp-audio-times',
            },
            'text' => {'color', 'size', 'font', 'x', 'y'},
            'image' => {'left', 'top', 'right', 'bottom'},
            'teximage' => {'text', 'color', 'left', 'top', 'right', 'bottom'},
            _ => <String>{},
          });
          if (![
            'stroke',
            'text',
            'image',
            'teximage',
          ].contains(node.name.local))
            warn('Contenuto del livello non supportato: ${node.name.local}');
          if (node.name.qualified != node.name.local) continue;
          switch (node.name.local) {
            case 'image': {
              final imageElement = node;
              _validateImageRectangle(imageElement);
              content.add(XppImage(
                data: budget.media(imageElement.innerText.trim()),
                topLeft: Offset(
                  documentNumber(imageElement.getAttribute('left')),
                  documentNumber(imageElement.getAttribute('top')),
                ),
                bottomRight: Offset(
                  documentNumber(imageElement.getAttribute('right')),
                  documentNumber(imageElement.getAttribute('bottom')),
                ),
              ));
              break;
            }
            case 'text': {
              final textElement = node;
              Color color = parseColor(textElement.getAttribute('color'));
              content.add(XppText(
                color: color,
                text: textElement.innerText,
                size: XppPageSize.pt2mm(
                  documentNumber(
                    textElement.getAttribute('size'),
                    min: 0.01,
                    max: 1000,
                  ),
                ),
                fontFamily: textElement.getAttribute('font'),
                offset: Offset(
                  documentNumber(textElement.getAttribute('x')),
                  documentNumber(textElement.getAttribute('y')),
                ),
              ));
              break;
            }
            case 'teximage': {
              final texElement = node;
              // Older OSI formulas use right=bottom=0 for automatic text bounds.
              final left = documentNumber(texElement.getAttribute('left'));
              final top = documentNumber(texElement.getAttribute('top'));
              var right = documentNumber(texElement.getAttribute('right'));
              var bottom = documentNumber(texElement.getAttribute('bottom'));
              if (right == 0 && bottom == 0) {
                final length = (texElement.getAttribute('text') ?? '').length;
                right = documentNumber('${left + math.max(1, length) * 10}');
                bottom = documentNumber('${top + 24}');
              }
              if (right <= left || bottom <= top) {
                throw const FormatException('Rettangolo della formula non valido');
              }
              content.add(XppTexImage(
                text: texElement.getAttribute('text')!.trim(),
                color: parseColor(texElement.getAttribute('color')!.trim()),
                topLeft: Offset(left, top),
                bottomRight: Offset(right, bottom),
              ));
              break;
            }
            case 'stroke': {
              final strokeElement = node;
              late XppStrokeTool tool;
              switch (strokeElement.getAttribute('tool')) {
                case "pen":
                  tool = XppStrokeTool.PEN;
                  break;
                case "eraser":
                  warn('Cancellatura whiteout non supportata');
                  continue;
                case "highlighter":
                  tool = XppStrokeTool.HIGHLIGHTER;
                  break;
                default:
                  warn('Strumento del tratto non supportato');
                  continue;
              }
              Color color = parseColor(strokeElement.getAttribute('color'));
              List<XppStrokePoint> points = [];
              final tokens = RegExp(r'\S+');
              final widths = <double>[];
              for (final token in tokens.allMatches(
                strokeElement.getAttribute('width') ?? '',
              )) {
                if (widths.length >= limits.points - budget.pointCount + 1) {
                  throw const FormatException('Troppi spessori nel tratto');
                }
                widths.add(
                  documentNumber(
                    token.group(0),
                    min: 0,
                    max: DocumentLimits.maxWidth,
                  ),
                );
              }
              if (widths.isEmpty) {
                throw const FormatException('Spessore del tratto mancante');
              }
              final coordinates = tokens
                  .allMatches(strokeElement.innerText)
                  .iterator;
              while (coordinates.moveNext()) {
                final x = documentNumber(coordinates.current.group(0));
                if (!coordinates.moveNext()) {
                  throw const FormatException('Coordinate incomplete');
                }
                final y = documentNumber(coordinates.current.group(0));
                budget.points(1); // Check before allocating another point.
                final index = points.length;
                if (index % 1024 == 0) budget.checkTime();
                points.add(
                  XppStrokePoint(
                    width: index < widths.length ? widths[index] : widths.first,
                    x: x,
                    y: y,
                  ),
                );
              }
              if (points.isEmpty) {
                throw const FormatException('Coordinate incomplete');
              }
              if (widths.length > points.length + 1) {
                throw const FormatException('Troppi spessori nel tratto');
              }
              final stroke = XppStroke.byTool(
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
              budget.points(stroke.erasures.length);
              for (final erasure in stroke.erasures) {
                documentNumber('${erasure.start.dx}');
                documentNumber('${erasure.start.dy}');
                documentNumber('${erasure.end.dx}');
                documentNumber('${erasure.end.dy}');
                documentNumber(
                  '${erasure.radius}',
                  min: 0.001,
                  max: DocumentLimits.maxWidth,
                );
              }
              content.add(stroke);
              break;
            }
          }
        }

        layers.add(
          XppLayer(
            content: content,
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

    if (pages.isEmpty) throw const FormatException('Documento senza pagine');
    final cards = NoteFlashcard.decode(cardElements, warnings: warnings);
    final recordings = NoteRecording.decode(audioElements);
    if (recordings.length != audioElements.length)
      warn('Audio recuperato solo parzialmente');
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
        flashcards: cards,
        recordings: recordings,
        importWarnings: warnings.toSet().toList(),
        originHash: sha256.convert(input['bytes'] as Uint8List).toString(),
      )
      ..importedXmlBytes = bytes.length
      ..importedMediaBytes = budget.mediaBytes
      ..importedNodes = budget.nodeCount
      ..importedPoints = budget.pointCount
      ..importedPages = budget.pageCount
      ..importedLayers = budget.layerCount;
  }

  static void _validateImageRectangle(XmlElement e) {
    final left = documentNumber(e.getAttribute('left'));
    final top = documentNumber(e.getAttribute('top'));
    final right = documentNumber(e.getAttribute('right'));
    final bottom = documentNumber(e.getAttribute('bottom'));
    if (right <= left || bottom <= top) {
      throw const FormatException('Rettangolo non valido');
    }
  }

  Uint8List? previewImage;
  @required
  List<XppPage>? pages;
  String? title;
  String? sourcePath;
  final Map<String, Uint8List> pdfAttachments;
  final Map<String, NoteRecording> recordings;
  final Map<String, NoteFlashcard> flashcards;

  /// Only call with bytes returned by an explicit picker. No path is followed.
  void attachSelectedBackground(String reference, FilePickerCross selected) {
    final data = selected.toUint8List();
    final total = pdfAttachments.entries
        .where((e) => e.key != reference)
        .fold<int>(data.length, (sum, e) => sum + e.value.length);
    if (total > DocumentLimits.standard.mediaBytes) {
      throw StateError('Allegati troppo grandi');
    }
    pdfAttachments[reference] = data;
    for (final page in pages ?? <XppPage>[]) {
      if (page.background case XppBackgroundImage image
          when image.filename == reference) {
        page.background = XppBackgroundImage(filename: reference, data: data);
      }
    }
  }

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

  XmlElement _xmlSkeleton() => XmlElement(
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
    ],
  );

  XmlDocument toXmlDocument() {
    validateSaveLimits();
    FlashcardLimits.validate(flashcards.values);
    final root = _xmlSkeleton();
    root.children.addAll([
      ...pdfAttachments.entries.map(
        (entry) => XmlElement(
          XmlName('pdf-attachment'),
          [XmlAttribute(XmlName('name'), entry.key)],
          [XmlText(base64Encode(entry.value))],
        ),
      ),
      ...recordings.values.map((e) => e.toXml()),
      ...flashcards.values.map((e) => e.toXml()),
      ...pages!.map((e) => e.toXmlElement()),
    ]);
    return XmlDocument([root]);
  }

  Iterable<String> _xmlChunks() sync* {
    validateSaveLimits();
    FlashcardLimits.validate(flashcards.values);
    yield '<?xml version="1.0" standalone="no"?>\n';
    final header = _xmlSkeleton().toXmlString();
    yield header.substring(0, header.length - '</xournal>'.length);
    for (final entry in pdfAttachments.entries) {
      final tag = XmlElement(XmlName('pdf-attachment'), [
        XmlAttribute(XmlName('name'), entry.key),
      ]).toXmlString();
      yield '${tag.substring(0, tag.length - 2)}>';
      // A multiple of three ensures concatenated base64 chunks are identical
      // to encoding the entire attachment, without a giant temporary string.
      for (var offset = 0; offset < entry.value.length; offset += 48 * 1024) {
        final end = (offset + 48 * 1024).clamp(0, entry.value.length);
        yield base64Encode(Uint8List.sublistView(entry.value, offset, end));
      }
      yield '</pdf-attachment>';
    }
    for (final recording in recordings.values) {
      yield recording.toXml().toXmlString();
    }
    for (final card in flashcards.values) {
      yield card.toXml().toXmlString();
    }
    for (final page in pages!) {
      final pageTag = page.toXmlElement(includeChildren: false).toXmlString();
      if ((page.background == null || page.background == XppBackground.none) &&
          page.layers!.isEmpty) {
        yield pageTag;
        continue;
      }
      yield '${pageTag.substring(0, pageTag.length - 2)}>';
      if (page.background != null && page.background != XppBackground.none) {
        yield page.background!.toXmlElement().toXmlString();
      }
      for (final layer in page.layers!) {
        final layerTag = layer.toXmlElement(includeChildren: false).toXmlString();
        final contents = (layer.content ?? []).whereType<XppContent>();
        if (contents.isEmpty) {
          yield layerTag;
          continue;
        }
        yield '${layerTag.substring(0, layerTag.length - 2)}>';
        for (final content in contents) {
          yield content.toXmlElement().toXmlString();
        }
        yield '</layer>';
      }
      yield '</page>';
    }
    yield '</xournal>';
  }

  void validateSaveLimits() {
    if (pages == null ||
        pages!.isEmpty ||
        pages!.length > DocumentLimits.standard.pages)
      throw const FormatException('Numero di pagine non valido');
    var points = 0,
        layers = 0,
        nodes = pages!.length + 1,
        media = previewImage?.length ?? 0;
    for (final bytes in pdfAttachments.values) {
      media += bytes.length;
    }
    for (final recording in recordings.values) {
      media += recording.bytes.length;
    }
    for (final card in flashcards.values) {
      media += (card.front.image?.length ?? 0) + (card.back.image?.length ?? 0);
    }
    for (final page in pages!) {
      layers += page.layers?.length ?? 0;
      nodes += 1 + (page.layers?.length ?? 0);
      for (final content
          in page.layers?.expand((l) => l.content ?? <XppContent?>[]) ??
              <XppContent?>[]) {
        nodes += 1;
        if (content is XppStroke)
          nodes +=
              content.erasures.length + (content.audioLink == null ? 0 : 1);
        if (content is XppStroke)
          points += (content.points?.length ?? 0) + content.erasures.length;
        if (content is XppImage) media += content.data?.length ?? 0;
      }
    }
    if (nodes > DocumentLimits.standard.nodes ||
        points > DocumentLimits.standard.points ||
        layers > DocumentLimits.standard.layers ||
        media > DocumentLimits.standard.mediaBytes)
      throw const FormatException(
        'Il documento supera i limiti di salvataggio e riapertura',
      );
  }

  String toXmlString() {
    return '<?xml version="1.0" standalone="no"?>\n' +
        toXmlDocument().toXmlString();
  }

  Uint8List? toUint8List() {
    return compression.compressXml(_xmlChunks());
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
      localId: localId,
      originHash: originHash,
      importWarnings: List.of(importWarnings),
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
