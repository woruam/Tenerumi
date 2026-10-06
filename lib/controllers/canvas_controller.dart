import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'package:xournalpp/src/pdf_raster_cache.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';

import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:xournalpp/src/compat/file_picker_cross.dart';

import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/content_snapshot.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

import 'package:xournalpp/layer_contents/XppStroke.dart';

class PageSnapshot {
  final int pageIndex;
  final List<XppContent?> content;
  PageSnapshot(this.pageIndex, this.content);
}

enum EraserMode { pixel, stroke }

// Dove inserire le pagine di un PDF importato.
enum PdfInsertMode { start, end, after }

class PdfInsertChoice {
  final PdfInsertMode mode;
  final int
  afterPage; // indice 0-based della pagina esistente dopo cui inserire
  final bool newTab;
  PdfInsertChoice({
    required this.mode,
    this.afterPage = 0,
    this.newTab = false,
  });
}

class CanvasController extends ChangeNotifier {
  final Future<Uint8List?> Function(int)? pdfRasterizer;
  CanvasController({this.pdfRasterizer});
  XppFile? file;

  Color penColor = Colors.black;
  double penWidth = 2.5;
  Color highlighterColor = const Color(0xFFFFF59D);
  double highlighterWidth = 15.0;
  EraserMode eraserMode = EraserMode.pixel;
  double eraserWidth = 10.0;

  Map<PointerDeviceKind?, EditingTool> toolData = {};
  PointerDeviceKind? currentDevice = PointerDeviceKind.touch;
  final Map<int, GlobalKey<XppPageStackState>> pageStackKeys = {};

  bool savingFile = false;
  bool shapeRecognition = false;
  bool touchDrawingEnabled = false;
  bool _hasUnsavedChanges = false;
  int _revision = 0;
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  set hasUnsavedChanges(bool value) {
    _hasUnsavedChanges = value;
    if (value) _revision++;
  }

  String buttonDownAction = 'eraser';
  String buttonUpAction = 'select';

  bool eraserSnapshotTaken = false;
  List<PageSnapshot> undoStack = [];
  List<PageSnapshot> redoStack = [];

  // --- MEMORIA PDF ---
  final PdfRasterCache pdfBackgrounds = PdfRasterCache(maxPages: 32);
  bool _disposed = false;
  Set<int> _visiblePdfPages = {};
  final Map<int, String> pdfErrors = {};
  Future<void> _renderQueue = Future.value();
  int _pdfEpoch = 0;
  final Map<String, Uint8List> _pdfSources = {};
  String? linkedPdfPath;

  bool get isPanEnabled =>
      toolData[PointerDeviceKind.stylus] == EditingTool.MOVE;
  bool get isShapeTool {
    final tool = toolData[PointerDeviceKind.stylus];
    return tool == EditingTool.SHAPE_LINE ||
        tool == EditingTool.SHAPE_RECT ||
        tool == EditingTool.SHAPE_CIRCLE ||
        tool == EditingTool.SHAPE_SQUARE ||
        tool == EditingTool.SHAPE_DASHED_LINE ||
        tool == EditingTool.SHAPE_CUBE ||
        tool == EditingTool.SHAPE_CYLINDER ||
        tool == EditingTool.SHAPE_SPHERE;
  }

  // RIPRISTINATO AD UN SOLO PARAMETRO (Così non rompe il routing della tua Home)
  void init(XppFile? initialFile) {
    if (file != null) return;
    file = initialFile;
    toolData[PointerDeviceKind.stylus] = EditingTool.STYLUS;
    toolData[PointerDeviceKind.touch] = EditingTool.MOVE;
    // Coda-gomma delle penne per tavoletta grafica (Wacom & co.): sempre gomma.
    toolData[PointerDeviceKind.invertedStylus] = EditingTool.ERASER;

    SharedPreferences.getInstance()
        .then((prefs) {
          final enabled = prefs.getBool(PreferencesKeys.kShapeRecognition);
          if (enabled != null) shapeRecognition = enabled;
          touchDrawingEnabled =
              prefs.getBool(PreferencesKeys.kTouchDrawing) ?? false;
          toolData[PointerDeviceKind.touch] = touchDrawingEnabled
              ? toolData[PointerDeviceKind.stylus] ?? EditingTool.STYLUS
              : EditingTool.MOVE;
          final bDown =
              prefs.getString('buttonDownAction') ??
              prefs.getString('stylusButtonAction');
          final bUp = prefs.getString('buttonUpAction');
          if (bDown != null) buttonDownAction = bDown;
          if (bUp != null) buttonUpAction = bUp;

          // IL FIX DELLA MEMORIA: Cerchiamo il PDF usando il Titolo del file!
          if (file?.title != null) {
            final savedPdf = prefs.getString('pdf_link_${file!.title}');
            if (savedPdf != null) {
              _restorePdfBackground(savedPdf);
            }
          }

          notifyListeners();
        })
        .catchError((e) {});
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pdfEpoch++;
    _pdfSources.clear();
    _visiblePdfPages.clear();
    pdfBackgrounds.clear();
    pageStackKeys.clear();
    undoStack.clear();
    redoStack.clear();
    super.dispose();
  }

  Future<void> _restorePdfBackground(String pdfPath) async {
    if (_disposed || file == null) return;
    if (file!.pages?.any((p) => p.background is XppBackgroundPdf) == true)
      return;
    // Migrate legacy title-based links only where no page association exists.
    linkedPdfPath = pdfPath;
    for (var i = 0; i < (file!.pages?.length ?? 0); i++) {
      final p = file!.pages![i];
      if (p.background is! XppBackgroundPdf) {
        p.background = XppBackgroundPdf(
          filename: pdfPath,
          page: i,
          onUnavailable: (path) =>
              FilePickerCross.fromInternalPath(path: path!),
        );
      }
    }
    notifyListeners();
    final visible = Set<int>.of(_visiblePdfPages);
    _visiblePdfPages = {};
    setVisiblePdfPages(visible);
  }

  void setVisiblePdfPages(Set<int> indices) {
    if (_disposed) return;
    if (setEquals(indices, _visiblePdfPages)) return;
    _visiblePdfPages = Set.of(indices);
    final epoch = _pdfEpoch;
    _renderQueue = _renderQueue.then((_) async {
      for (final i in indices) {
        if (_disposed || epoch != _pdfEpoch) return;
        if (!_visiblePdfPages.contains(i) ||
            pdfBackgrounds.containsKey(i) ||
            pdfErrors.containsKey(i))
          continue;
        try {
          final bytes = await (pdfRasterizer?.call(i) ?? rasterPdfPage(i));
          if (!_disposed &&
              epoch == _pdfEpoch &&
              _visiblePdfPages.contains(i) &&
              bytes != null) {
            pdfBackgrounds[i] = bytes;
            notifyListeners();
          }
        } catch (e) {
          if (!_disposed && epoch == _pdfEpoch) {
            pdfErrors[i] = e.toString();
            notifyListeners();
          }
        }
      }
    });
  }

  void suspendPdfRendering() {
    _pdfEpoch++;
    _visiblePdfPages = {};
    pdfBackgrounds.clear();
  }

  Future<pdfx.PdfDocument> _openPdf(String name) async {
    final bytes = await _readPdfBytes(name);
    return pdfx.PdfDocument.openData(bytes);
  }

  Future<Uint8List> _readPdfBytes(String name) async {
    final embedded = file?.pdfAttachments[name];
    if (embedded != null) return embedded;
    String path = name;
    final source = file?.sourcePath?.replaceAll('\\', '/');
    if (!name.startsWith('/') &&
        !name.contains(':') &&
        source != null &&
        source.contains('/')) {
      path = '${source.substring(0, source.lastIndexOf('/') + 1)}$name';
    }
    try {
      return (await FilePickerCross.fromInternalPath(path: path)).toUint8List();
    } catch (_) {
      final background = file?.pages
          ?.map((p) => p.background)
          .whereType<XppBackgroundPdf>()
          .where((b) => b.filename == name)
          .firstOrNull;
      if (background == null) rethrow;
      return (await background.onUnavailable(path)).toUint8List();
    }
  }

  Future<Uint8List?> rasterPdfPage(int index) async {
    if (_disposed || index >= (file?.pages?.length ?? 0)) return null;
    final background = file!.pages![index].background;
    if (background is! XppBackgroundPdf || background.filename == null)
      return null;
    final document = await _openPdf(background.filename!);
    try {
      final page = await document.getPage((background.page ?? 0) + 1);
      try {
        // Bound decoded GPU memory even for huge source pages.
        final pixelBudget = math.min(
          1000000.0,
          4000000.0 / math.max(1, _visiblePdfPages.length),
        );
        final scale = math.min(
          2.0,
          math.sqrt(pixelBudget / (page.width * page.height)),
        );
        final image = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: pdfx.PdfPageImageFormat.png,
        );
        return image?.bytes;
      } finally {
        await page.close();
      }
    } finally {
      await document.close();
    }
  }

  // --- FUNZIONE PER IMPORTARE IL PDF (Ottimizzata) ---
  Future<void> importPdf(
    BuildContext context, {
    void Function(String pdfPath, String title)? onOpenInNewTab,
  }) async {
    try {
      final fileData = await FilePickerCross.importFromStorage(
        type: FileTypeCross.custom,
        fileExtension: 'pdf',
      );
      if (fileData.path == null) return;

      final String filePath = fileData.path!;
      _pdfSources[filePath] = fileData.toUint8List();
      final String pdfTitle =
          fileData.fileName?.replaceAll('.pdf', '') ?? 'Documento_PDF';
      if (!context.mounted || _disposed) return;
      final int existingPages = file?.pages?.length ?? 0;

      // Chiediamo DOVE inserire il PDF (senza cancellare nulla di esistente).
      final PdfInsertChoice? choice = await _askPdfInsertPosition(
        context,
        existingPages,
      );
      if (choice == null) return; // annullato dall'utente

      // Opzione "nuova scheda": deleghiamo alla WorkspacePage.
      if (choice.newTab) {
        final storedPath = await fileData.saveToPath(
          path: 'import_${DateTime.now().microsecondsSinceEpoch}.pdf',
        );
        onOpenInNewTab?.call(storedPath, pdfTitle);
        return;
      }

      int insertAt;
      switch (choice.mode) {
        case PdfInsertMode.start:
          insertAt = 0;
          break;
        case PdfInsertMode.end:
          insertAt = existingPages;
          break;
        case PdfInsertMode.after:
          insertAt = (choice.afterPage + 1).clamp(0, existingPages);
          break;
      }

      linkedPdfPath = filePath;
      await _insertPdfAt(filePath, insertAt);
    } catch (e) {
      print("Selezione annullata o errore PDF: $e");
    } finally {
      savingFile = false;
      notifyListeners();
    }
  }

  // Inserisce le pagine del PDF a [insertAt] SENZA toccare pagine/tratti esistenti.
  Future<void> _insertPdfAt(String pdfPath, int insertAt) async {
    savingFile = true;
    notifyListeners();

    final source = _pdfSources.containsKey(pdfPath)
        ? FilePickerCross(_pdfSources[pdfPath]!, path: pdfPath)
        : await FilePickerCross.fromInternalPath(path: pdfPath);
    final document = await pdfx.PdfDocument.openData(source.toUint8List());
    final attachmentName =
        'embedded_pdf_${file?.pdfAttachments.length ?? 0}.pdf';
    final int count = document.pagesCount;

    file ??= XppFile(title: 'Documento')..pages = [];
    file!.pages ??= [];
    insertAt = insertAt.clamp(0, file!.pages!.length);

    // 1) Facciamo spazio: spostiamo in avanti gli sfondi PDF già presenti.
    pdfBackgrounds.clear();
    pdfErrors.clear();
    _pdfEpoch++;

    // 2) Creiamo le nuove pagine (solo misure) e le inseriamo nella posizione scelta.
    final List<XppPage> newPages = [];
    try {
      for (int i = 1; i <= count; i++) {
        final page = await document.getPage(i);
        try {
          final xppPage = XppPage.empty();
          xppPage.pageSize = XppPageSize(
            width: page.width,
            height: page.height,
          );
          xppPage.background = XppBackgroundPdf(
            filename: attachmentName,
            page: i - 1,
            onUnavailable: (_) async => source,
          );
          newPages.add(xppPage);
        } finally {
          await page.close();
        }
      }
    } finally {
      await document.close();
    }

    if (_disposed) return;
    file!.pdfAttachments[attachmentName] = source.toUint8List();
    file!.pages!.insertAll(insertAt, newPages);

    // 3) Indici cambiati: rigeneriamo le chiavi degli stack e azzeriamo l'undo
    //    (gli snapshot erano legati ai vecchi indici di pagina).
    pageStackKeys.clear();
    undoStack.clear();
    redoStack.clear();

    hasUnsavedChanges = true;
    savingFile = false;
    notifyListeners();

    // 4) Renderizziamo gli sfondi delle nuove pagine all'offset corretto (in background).
    final visible = Set<int>.of(_visiblePdfPages);
    _visiblePdfPages = {};
    setVisiblePdfPages(visible);
  }

  // Carica un PDF in una scheda NUOVA e vuota.
  Future<void> loadPdfFresh(String pdfPath, String title) async {
    if (_disposed) return;
    file = XppFile(title: title);
    file!.pages = [];
    pdfBackgrounds.clear();
    linkedPdfPath = pdfPath;
    try {
      await _insertPdfAt(pdfPath, 0);
    } catch (e) {
      if (!_disposed) pdfErrors[0] = e.toString();
    } finally {
      savingFile = false;
      notifyListeners();
    }
  }

  // Dialog: chiede dove inserire le pagine del PDF.
  Future<PdfInsertChoice?> _askPdfInsertPosition(
    BuildContext context,
    int existingPages,
  ) {
    int afterPage = existingPages > 0 ? existingPages - 1 : 0;
    return showDialog<PdfInsertChoice>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: const Text('Inserisci PDF'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Dove vuoi inserire le pagine del PDF?'),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.vertical_align_top),
                title: const Text("All'inizio"),
                onTap: () => Navigator.pop(
                  context,
                  PdfInsertChoice(mode: PdfInsertMode.start),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.vertical_align_bottom),
                title: const Text('Alla fine'),
                onTap: () => Navigator.pop(
                  context,
                  PdfInsertChoice(mode: PdfInsertMode.end),
                ),
              ),
              if (existingPages > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.import_export),
                      const SizedBox(width: 12),
                      const Text('Dopo pag.'),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: afterPage,
                        items: List.generate(
                          existingPages,
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text('${i + 1}'),
                          ),
                        ),
                        onChanged: (v) => setS(() => afterPage = v ?? 0),
                      ),
                      const Spacer(),
                      TextButton(
                        child: const Text('Inserisci'),
                        onPressed: () => Navigator.pop(
                          context,
                          PdfInsertChoice(
                            mode: PdfInsertMode.after,
                            afterPage: afterPage,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tab),
                title: const Text('In una nuova scheda'),
                onTap: () => Navigator.pop(
                  context,
                  PdfInsertChoice(mode: PdfInsertMode.end, newTab: true),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Annulla'),
            ),
          ],
        ),
      ),
    );
  }

  // --- SALVATAGGIO XOPP (Ora salva in base al TITOLO) ---
  Future<bool> saveFile(BuildContext context) async {
    if (savingFile || file == null) return false;
    final savedRevision = _revision;
    savingFile = true;
    notifyListeners();
    try {
      final document = file!;
      // Make existing native PDF references portable on the next save.
      for (final background
          in document.pages
                  ?.map((p) => p.background)
                  .whereType<XppBackgroundPdf>() ??
              <XppBackgroundPdf>[]) {
        final name = background.filename;
        if (name != null && !document.pdfAttachments.containsKey(name)) {
          document.pdfAttachments[name] = await _readPdfBytes(name);
        }
      }
      document.previewImage ??= kTransparentImage;
      final data = await document.toFilePickerCrossAsync(
        filePath: document.suggestedFileName,
      );
      final String? absolutePath;
      if (kIsWeb || document.sourcePath?.startsWith('content://') == true) {
        absolutePath = await data.exportToStorage(
          fileName: document.suggestedFileName,
        );
        if (absolutePath == null) return false;
      } else {
        String destination = document.sourcePath ?? document.suggestedFileName;
        if (document.sourcePath == null) {
          final base = document.suggestedFileName;
          int suffix = 2;
          while (await FilePickerCross.exists(destination)) {
            destination =
                '${base.substring(0, base.length - 5)} ($suffix).xopp';
            suffix++;
          }
        }
        absolutePath = await data.saveToPath(path: destination);
      }
      document.sourcePath = absolutePath;

      final prefs = await SharedPreferences.getInstance();

      List files =
          (jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles) ?? '[]')
                  as List)
              .toList();
      bool wasFav = files.any(
        (e) => e['path'] == absolutePath && e['favorite'] == true,
      );
      files.removeWhere((e) => e['path'] == absolutePath);
      files.add({
        'preview': file!.previewImage != null
            ? base64Encode(file!.previewImage!)
            : "",
        'name': file!.title,
        'path': absolutePath,
        'favorite': wasFav,
      });
      await prefs.setString(PreferencesKeys.kRecentFiles, jsonEncode(files));
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Documento salvato")));
      if (_revision == savedRevision) hasUnsavedChanges = false;
      return true;
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Errore: $e")));
      return false;
    } finally {
      savingFile = false;
      notifyListeners();
    }
  }

  // --- ESPORTAZIONE PDF FINALE CON INCHIOSTRO (Invariato e Funzionante) ---
  Future<void> exportToPdf(BuildContext context) async {
    savingFile = true;
    notifyListeners();
    try {
      final pdfDoc = pw.Document();

      for (int i = 0; i < file!.pages!.length; i++) {
        final xppPage = file!.pages![i];
        final double width = xppPage.pageSize?.width ?? PdfPageFormat.a4.width;
        final double height =
            xppPage.pageSize?.height ?? PdfPageFormat.a4.height;
        final ink = (xppPage.layers?.first.content ?? [])
            .whereType<XppStroke>()
            .toList();
        Uint8List? clippedInk;
        if (ink.any((s) => s.erasures.isNotEmpty)) {
          final scale = math.min(2.0, 4096 / math.max(width, height));
          final recorder = ui.PictureRecorder();
          final rasterCanvas = Canvas(recorder)..scale(scale);
          for (final stroke in ink) {
            rasterCanvas.save();
            rasterCanvas.translate(
              stroke.getOffset().dx,
              stroke.getOffset().dy,
            );
            stroke.paintToCanvas(rasterCanvas, Size(width, height));
            rasterCanvas.restore();
          }
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            (width * scale).ceil(),
            (height * scale).ceil(),
          );
          try {
            clippedInk = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List();
          } finally {
            image.dispose();
            picture.dispose();
          }
        }

        pw.Widget pageContent;
        if (pdfBackgrounds.containsKey(i)) {
          final image = pw.MemoryImage(pdfBackgrounds[i]!);
          pageContent = pw.Image(image, fit: pw.BoxFit.fill);
        } else {
          pageContent = pw.Container();
        }

        final inkBytes = clippedInk;
        pdfDoc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(width, height, marginAll: 0),
            build: (pw.Context ctx) {
              return pw.Stack(
                children: [
                  pageContent,
                  if (inkBytes != null)
                    pw.Image(
                      pw.MemoryImage(inkBytes),
                      width: width,
                      height: height,
                      fit: pw.BoxFit.fill,
                    ),
                  pw.CustomPaint(
                    size: PdfPoint(width, height),
                    painter: (PdfGraphics canvas, PdfPoint size) {
                      final contents = inkBytes != null
                          ? <XppContent?>[]
                          : (xppPage.layers?[0].content ?? <XppContent?>[]);
                      for (final content in contents) {
                        if (content is XppStroke) {
                          final points = content.points ?? [];
                          if (points.isEmpty) continue;

                          final color = content.color ?? Colors.black;
                          final pdfColor = PdfColor(
                            color.red / 255.0,
                            color.green / 255.0,
                            color.blue / 255.0,
                            color.opacity,
                          );

                          double strokeWidth = 2.5;
                          if (points.first.width != null)
                            strokeWidth = points.first.width!.toDouble();

                          canvas.setStrokeColor(pdfColor);
                          canvas.setLineWidth(strokeWidth);

                          final double startX =
                              points.first.x?.toDouble() ?? 0.0;
                          final double startY =
                              points.first.y?.toDouble() ?? 0.0;
                          canvas.moveTo(startX, height - startY);

                          for (int j = 1; j < points.length; j++) {
                            final double px = points[j].x?.toDouble() ?? 0.0;
                            final double py = points[j].y?.toDouble() ?? 0.0;
                            canvas.lineTo(px, height - py);
                          }
                          canvas.strokePath();
                        }
                      }
                    },
                  ),
                ],
              );
            },
          ),
        );
      }

      final Uint8List pdfBytes = await pdfDoc.save();
      await FilePickerCross(
        pdfBytes,
        type: FileTypeCross.custom,
        fileExtension: 'pdf',
        path: "${file!.title ?? "Documento_Esportato"}.pdf",
      ).exportToStorage();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("PDF esportato con i tuoi appunti!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Errore esportazione PDF: $e")));
    } finally {
      savingFile = false;
      notifyListeners();
    }
  }

  // --- GESTIONE DEI TRATTI E UNDO ---
  void addNewContent(int pageIndex, XppContent? newContent) {
    if (newContent == null) return;
    saveSnapshot(pageIndex);
    hasUnsavedChanges = true;
    file!.pages![pageIndex].layers![0].content ??= [];
    file!.pages![pageIndex].layers![0].content!.add(newContent);
    pageStackKeys[pageIndex]?.currentState?.setPageData(
      file!.pages![pageIndex],
    );
    notifyListeners();
  }

  void deleteContent(int pageIndex, List<XppContent> deleted) {
    saveSnapshot(pageIndex);
    hasUnsavedChanges = true;
    file!.pages![pageIndex].layers![0].content!.removeWhere(
      (element) => deleted.contains(element),
    );
    pageStackKeys[pageIndex]?.currentState?.setPageData(
      file!.pages![pageIndex],
    );
    notifyListeners();
  }

  void removeLastContent(int pageIndex) {
    if (file!.pages![pageIndex].layers![0].content!.isEmpty) return;
    saveSnapshot(pageIndex);
    hasUnsavedChanges = true;
    file!.pages![pageIndex].layers![0].content!.removeLast();
    pageStackKeys[pageIndex]?.currentState?.setPageData(
      file!.pages![pageIndex],
    );
    notifyListeners();
  }

  void filterEraser({
    required int pageIndex,
    Offset? coordinates,
    Offset? previousCoordinates,
    double? radius,
  }) {
    if (coordinates == null) return;
    final tipRadius = radius ?? 5;
    final cut = StrokeErasure(
      previousCoordinates ?? coordinates,
      coordinates,
      tipRadius,
    );
    final contents = file!.pages![pageIndex].layers![0].content ?? [];
    final changes = <int, XppContentEraseData>{};
    for (int i = contents.length - 1; i >= 0; i--) {
      final content = contents[i];
      if (content == null) continue;
      if (content is! XppStroke) {
        // Whole-object erasing keeps the previous behavior for text/images.
        if (eraserMode == EraserMode.stroke &&
            content.bounds()?.inflate(tipRadius).contains(coordinates) ==
                true) {
          changes[i] = XppContentEraseData(affected: true, delete: true);
          break;
        }
        continue;
      }
      final bounds = content.bounds();
      if (bounds == null ||
          !bounds.inflate(tipRadius).overlaps(cut.path.getBounds()))
        continue;
      if (eraserMode == EraserMode.stroke) {
        if (!content.intersectsErasure(cut)) continue;
        changes[i] = XppContentEraseData(affected: true, delete: true);
        break;
      }
      final delta = content.eraseAlong(
        coordinates: coordinates,
        previousCoordinates: previousCoordinates,
        radius: tipRadius,
      );
      if (delta.affected) changes[i] = delta;
    }
    if (changes.isEmpty) return;
    if (!eraserSnapshotTaken) {
      saveSnapshot(pageIndex);
      eraserSnapshotTaken = true;
    }
    for (final entry in changes.entries) {
      contents.removeAt(entry.key);
      contents.insertAll(entry.key, entry.value.newContent);
    }
    hasUnsavedChanges = true;
    pageStackKeys[pageIndex]?.currentState?.setPageData(
      file!.pages![pageIndex],
    );
    notifyListeners();
  }

  void saveSnapshot(int pageIndex) {
    if (file?.pages == null || file!.pages!.isEmpty) return;
    undoStack.add(
      PageSnapshot(
        pageIndex,
        cloneContents(file!.pages![pageIndex].layers![0].content ?? []),
      ),
    );
    if (undoStack.length > 50) undoStack.removeAt(0);
    redoStack.clear();
    notifyListeners();
  }

  void undo() {
    if (undoStack.isEmpty) return;
    final last = undoStack.removeLast();
    redoStack.add(
      PageSnapshot(
        last.pageIndex,
        cloneContents(file!.pages![last.pageIndex].layers![0].content ?? []),
      ),
    );
    file!.pages![last.pageIndex].layers![0].content = last.content;
    pageStackKeys[last.pageIndex]?.currentState?.setPageData(
      file!.pages![last.pageIndex],
    );
    hasUnsavedChanges = true;
    notifyListeners();
  }

  void redo() {
    if (redoStack.isEmpty) return;
    final future = redoStack.removeLast();
    undoStack.add(
      PageSnapshot(
        future.pageIndex,
        cloneContents(file!.pages![future.pageIndex].layers![0].content ?? []),
      ),
    );
    file!.pages![future.pageIndex].layers![0].content = future.content;
    pageStackKeys[future.pageIndex]?.currentState?.setPageData(
      file!.pages![future.pageIndex],
    );
    hasUnsavedChanges = true;
    notifyListeners();
  }

  void setTool(EditingTool t) {
    toolData = Map.from(toolData);
    toolData[PointerDeviceKind.touch] = touchDrawingEnabled
        ? t
        : EditingTool.MOVE;
    toolData[PointerDeviceKind.stylus] = t;
    // La coda-gomma delle penne da tavoletta resta sempre gomma.
    toolData[PointerDeviceKind.invertedStylus] = EditingTool.ERASER;
    notifyListeners();
  }

  void markContentChanged(int pageIndex) {
    hasUnsavedChanges = true;
    pageStackKeys[pageIndex]?.currentState?.setPageData(
      file!.pages![pageIndex],
    );
    notifyListeners();
  }

  void addPage() {
    hasUnsavedChanges = true;

    final XppPageSize size =
        (file!.pages!.isNotEmpty && file!.pages!.last.pageSize != null)
        ? XppPageSize(
            width: file!.pages!.last.pageSize!.width,
            height: file!.pages!.last.pageSize!.height,
          )
        : XppPageSize(width: 595.0, height: 842.0);

    // La nuova pagina EREDITA il template della pagina precedente (righe,
    // quadretti, puntini, Nothing...); se non c'e' (es. pagine PDF), si torna
    // al classico foglio bianco a righe.
    final XppBackground? inherited = _cloneBackgroundForNewPage(
      file!.pages!.isNotEmpty ? file!.pages!.last.background : null,
      size,
    );

    final XppPage newPage = XppPage.empty(
      pageSize: size,
      template:
          inherited ?? XppBackgroundSolidLined(color: Colors.white, size: size),
    );

    file!.pages!.add(newPage);
    notifyListeners();
  }

  /// Ricrea lo stesso tipo di sfondo della pagina precedente, adattato alla
  /// nuova dimensione. Le pagine con sfondo PDF/immagine restituiscono null.
  XppBackground? _cloneBackgroundForNewPage(
    XppBackground? prev,
    XppPageSize size,
  ) {
    if (prev is XppBackgroundNothingDark) {
      return XppBackgroundNothingDark(size: size);
    }
    if (prev is XppBackgroundNothingLight) {
      return XppBackgroundNothingLight(size: size);
    }
    if (prev is XppBackgroundSolidLined) {
      return XppBackgroundSolidLined(color: prev.color, size: size);
    }
    if (prev is XppBackgroundSolidRuled) {
      return XppBackgroundSolidRuled(color: prev.color, size: size);
    }
    if (prev is XppBackgroundSolidGraph) {
      return XppBackgroundSolidGraph(color: prev.color, size: size);
    }
    if (prev is XppBackgroundSolidDot) {
      return XppBackgroundSolidDot(color: prev.color, size: size);
    }
    if (prev is XppBackgroundSolidPlain) {
      return XppBackgroundSolidPlain(color: prev.color, size: size);
    }
    return null;
  }

  Color getCurrentToolColor() =>
      toolData[PointerDeviceKind.stylus] == EditingTool.HIGHLIGHT
      ? highlighterColor
      : penColor;
  double getCurrentToolWidth() =>
      toolData[PointerDeviceKind.stylus] == EditingTool.HIGHLIGHT
      ? highlighterWidth
      : (toolData[PointerDeviceKind.stylus] == EditingTool.ERASER
            ? eraserWidth
            : penWidth);
  void setPenProps(Color? c, double? w) {
    if (c != null) penColor = c;
    if (w != null) penWidth = w;
    notifyListeners();
  }

  void setHighlighterProps(Color? c, double? w) {
    if (c != null) highlighterColor = c;
    if (w != null) highlighterWidth = w;
    notifyListeners();
  }

  void setEraserProps(EraserMode? m, double? w) {
    if (m != null) eraserMode = m;
    if (w != null) eraserWidth = w;
    notifyListeners();
  }
}
