import 'dart:async';

import 'note_audio_controller.dart';

import 'package:xournalpp/src/note_audio.dart';

import 'package:xournalpp/src/autosave_store.dart';
import 'package:xournalpp/src/recent_documents.dart';

import 'package:flutter/foundation.dart';

import 'dart:math' as math;

import 'package:xournalpp/src/pdf_raster_cache.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';

import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:xournalpp/src/compat/file_picker_cross.dart';

import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/content_snapshot.dart';
import 'package:xournalpp/src/document_export.dart';
import 'package:xournalpp/src/selection_clipboard.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

import 'package:xournalpp/layer_contents/XppStroke.dart';

class PageSnapshot {
  final int pageIndex;
  final List<XppLayer> layers;
  final int activeIndex;
  List<XppContent?> get content => layers[activeIndex].content ?? [];
  PageSnapshot(this.pageIndex, this.layers, this.activeIndex);
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

class CanvasController extends ChangeNotifier with WidgetsBindingObserver {
  final Future<Uint8List?> Function(int)? pdfRasterizer;
  final Future<String?> Function(FilePickerCross)? documentExporter;
  CanvasController({
    this.autosaveEnabled = true,
    this.pdfRasterizer,
    this.documentExporter,
    SelectionClipboard? clipboard,
  }) : clipboard = clipboard ?? SelectionClipboard();
  final SelectionClipboard clipboard;
  final bool autosaveEnabled;
  Future<String?> _exportDocument(FilePickerCross data) =>
      documentExporter?.call(data) ?? data.exportToStorage();
  XppFile? file;
  late final NoteAudioController audio = NoteAudioController(
    file!,
    onModeChanged: notifyListeners,
    onDocumentChanged: () {
      if (_disposed) {
        _hasUnsavedChanges = true;
        _revision++;
      } else {
        hasUnsavedChanges = true;
        notifyListeners();
      }
    },
  );
  void listenAt(int page, Offset position) {
    for (final layer in file!.pages![page].layers!.reversed) {
      if (!layer.visible) continue;
      for (final stroke
          in (layer.content ?? []).whereType<XppStroke>().toList().reversed) {
        final link = stroke.audioLink;
        if (link != null &&
            !stroke.erasures.any((cut) => cut.contains(position)) &&
            (stroke.containsVisibleInk(position) ||
                stroke.shouldSelectAt(coordinates: position))) {
          unawaited(audio.play(link.recordingId, position: link.startMs));
          return;
        }
      }
    }
  }

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
  int get pluginRevision => _revision;
  bool get acceptsPluginEdits => !_disposed;
  int activePageIndex = 0;
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  set hasUnsavedChanges(bool value) {
    _hasUnsavedChanges = value;
    if (value) {
      _revision++;
      file?.modifiedAt = DateTime.now().toUtc();
      if (!autosaveEnabled) return;
      _scheduleAutosave();
    }
  }

  Timer? _autosaveTimer;
  Timer? _autosaveDeadline;
  Future<void>? _autosaveQueue;
  int _checkpointRevision = -1;
  Uint8List? _checkpointPreview;
  bool _discardRecovery = false;
  DateTime? lastAutosave;
  String? autosaveError;
  bool autosaving = false;
  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(
      const Duration(seconds: 2),
      () => unawaited(flushAutosave()),
    );
    _autosaveDeadline ??= Timer(
      const Duration(seconds: 10),
      () => unawaited(flushAutosave()),
    );
  }

  Future<void> flushAutosave() {
    _autosaveTimer?.cancel();
    _autosaveDeadline?.cancel();
    _autosaveDeadline = null;
    final document = file;
    if (!autosaveEnabled ||
        _discardRecovery ||
        document == null ||
        savingFile ||
        !hasUnsavedChanges) {
      return _autosaveQueue ?? Future.value();
    }
    _autosaveQueue = (_autosaveQueue ?? Future.value()).then((_) async {
      if (_discardRecovery || _checkpointRevision == _revision) return;
      final revision = _revision;
      autosaving = true;
      notifyListeners();
      try {
        final snapshot = document.snapshot();
        await _preparePreview(snapshot);
        final bytes = await snapshot.serializeSnapshotAsync();
        if (_discardRecovery) return;
        await AutosaveStore.save(snapshot, bytes);
        lastAutosave = DateTime.now();
        // A recovery copy is always secured before touching the original file.
        // Browser documents stay recoverable locally until explicitly exported.
        if (!kIsWeb &&
            document.sourcePath != null &&
            !savingFile &&
            !_discardRecovery) {
          await FilePickerCross(bytes).saveToPath(path: document.sourcePath!);
          await RecentDocuments.save(snapshot, document.sourcePath!);
          if (identical(file, document) && _revision == revision) {
            _hasUnsavedChanges = false;
            document.previewImage = snapshot.previewImage;
          }
        }
        if (!savingFile || document.sourcePath == null) {
          _checkpointRevision = revision;
          _checkpointPreview = snapshot.previewImage;
        }
        autosaveError = null;
      } catch (error) {
        autosaveError = error.toString();
      } finally {
        autosaving = false;
        notifyListeners();
      }
    });
    return _autosaveQueue!;
  }

  Future<void> discardRecovery() async {
    _discardRecovery = true;
    _autosaveTimer?.cancel();
    _autosaveDeadline?.cancel();
    if (_autosaveQueue != null) await _autosaveQueue;
    if (!autosaveEnabled) return;
    if (file != null) await AutosaveStore.remove(file!.documentId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(audio.suspend().then((_) => flushAutosave()));
    } else if (state != AppLifecycleState.resumed) {
      unawaited(flushAutosave());
    }
  }

  final Map<int, int> _activeLayers = {};
  int activeLayerIndex(int page) {
    final layers = file!.pages![page].layers!;
    return (_activeLayers[page] ?? 0).clamp(0, layers.length - 1);
  }

  XppLayer activeLayer(int page) =>
      file!.pages![page].layers![activeLayerIndex(page)];
  bool canEditLayer(int page) =>
      activeLayer(page).visible && !activeLayer(page).locked;
  void selectLayer(int page, int index) {
    if (index < 0 || index >= file!.pages![page].layers!.length) return;
    _activeLayers[page] = index;
    _revision++;
    notifyListeners();
  }

  void addLayer(int page) {
    saveSnapshot(page);
    final layers = file!.pages![page].layers!;
    layers.add(XppLayer(content: [], name: 'Livello ${layers.length + 1}'));
    _activeLayers[page] = layers.length - 1;
    markContentChanged(page);
  }

  void updateLayer(
    int page,
    int index, {
    String? name,
    bool? visible,
    bool? locked,
  }) {
    saveSnapshot(page);
    final layer = file!.pages![page].layers![index];
    if (name != null && name.trim().isNotEmpty) layer.name = name.trim();
    if (visible != null) layer.visible = visible;
    if (locked != null) layer.locked = locked;
    markContentChanged(page);
  }

  void deleteLayer(int page, int index) {
    final layers = file!.pages![page].layers!;
    if (layers.length == 1) return;
    saveSnapshot(page);
    final selected = activeLayer(page);
    layers.removeAt(index);
    _activeLayers[page] = layers.contains(selected)
        ? layers.indexOf(selected)
        : (index - 1).clamp(0, layers.length - 1);
    markContentChanged(page);
  }

  void moveLayer(int page, int index, int destination) {
    final layers = file!.pages![page].layers!;
    if (destination < 0 ||
        destination >= layers.length ||
        index == destination) {
      return;
    }
    saveSnapshot(page);
    final selected = activeLayer(page);
    layers.insert(destination, layers.removeAt(index));
    _activeLayers[page] = layers.indexOf(selected);
    markContentChanged(page);
  }

  String buttonDownAction = 'eraser';
  String buttonUpAction = 'select';

  bool eraserSnapshotTaken = false;
  // Points are unchanged while erasing, and replacement strokes share them.
  // Cache only page geometry for this gesture, never native paths or history.
  final Map<List<XppStrokePoint>, Rect?> _eraserBounds = Map.identity();

  void beginEraserGesture() {
    eraserSnapshotTaken = false;
    _eraserBounds.clear();
  }

  void endEraserGesture() {
    eraserSnapshotTaken = false;
    _eraserBounds.clear();
  }

  List<PageSnapshot> undoStack = [];
  List<PageSnapshot> redoStack = [];

  // --- MEMORIA PDF ---
  final PdfRasterCache pdfBackgrounds = PdfRasterCache(maxPages: 32);
  bool _disposed = false;
  Set<int> _visiblePdfPages = {};
  final Map<int, String> pdfErrors = {};
  Future<void>? _renderQueue;
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
    WidgetsBinding.instance.addObserver(this);
    if (initialFile?.recovered == true) hasUnsavedChanges = true;
    toolData[PointerDeviceKind.stylus] = EditingTool.STYLUS;
    toolData[PointerDeviceKind.touch] = EditingTool.MOVE;
    // Coda-gomma delle penne per tavoletta grafica (Wacom & co.): sempre gomma.
    toolData[PointerDeviceKind.invertedStylus] = EditingTool.ERASER;

    SharedPreferences.getInstance()
        .then((prefs) {
          if (_disposed) return;
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
    _eraserBounds.clear();
    WidgetsBinding.instance.removeObserver(this);
    if (file != null) {
      unawaited(
        audio.stop().then((_) => flushAutosave()).whenComplete(audio.dispose),
      );
    }
    _disposed = true;
    _releaseViewPdf();
    pageNavigation.dispose();
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
              FilePickerCross.fromInternalPath(path: path ?? pdfPath),
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
    final result = (_renderQueue ?? Future.value()).then((_) async {
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
    final completed = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _renderQueue = completed;
    unawaited(
      completed.then((_) {
        if (identical(_renderQueue, completed)) _renderQueue = null;
      }),
    );
  }

  void suspendPdfRendering() {
    _releaseViewPdf();
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

  Future<pdfx.PdfDocument>? _viewPdf;
  String? _viewPdfName;
  void _releaseViewPdf() {
    final document = _viewPdf, pending = _renderQueue;
    _viewPdf = null;
    _viewPdfName = null;
    if (document != null)
      unawaited(() async {
        try {
          await pending;
          await (await document).close();
        } catch (_) {}
      }());
  }

  Future<Uint8List?> rasterPdfPage(int index) async {
    if (_disposed || index >= (file?.pages?.length ?? 0)) return null;
    final epoch = _pdfEpoch;
    final background = file!.pages![index].background;
    if (background is! XppBackgroundPdf || background.filename == null)
      return null;
    if (_viewPdfName != background.filename) {
      // The visible render queue is serial: the previous page is already closed.
      final previous = _viewPdf;
      _viewPdf = null;
      _viewPdfName = background.filename;
      if (previous != null) {
        try {
          await (await previous).close();
        } catch (_) {}
      }
    }
    if (_disposed || epoch != _pdfEpoch) return null;
    final opening = _viewPdf ??= _openPdf(background.filename!);
    try {
      final document = await opening;
      if (_disposed || epoch != _pdfEpoch) return null;
      return await _renderPdfPage(
        document,
        background,
        pixelBudget: math.min(
          4000000.0,
          4000000.0 / math.max(1, _visiblePdfPages.length),
        ),
      );
    } catch (_) {
      if (identical(_viewPdf, opening)) _releaseViewPdf();
      rethrow;
    }
  }

  Future<Uint8List?> _rasterPdfBackground(
    XppBackgroundPdf background, {
    required double pixelBudget,
  }) async {
    if (background.filename == null) return null;
    final document = await _openPdf(background.filename!);
    try {
      return await _renderPdfPage(
        document,
        background,
        pixelBudget: pixelBudget,
      );
    } finally {
      await document.close();
    }
  }

  Future<Uint8List?> _renderPdfPage(
    pdfx.PdfDocument document,
    XppBackgroundPdf background, {
    required double pixelBudget,
  }) async {
    final page = await document.getPage((background.page ?? 0) + 1);
    try {
      final scale = math.min(
        4.0,
        math.min(
          4096 / math.max(page.width, page.height),
          math.sqrt(pixelBudget / (page.width * page.height)),
        ),
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
      final String filePath =
          fileData.path ??
          fileData.fileName ??
          'import_${DateTime.now().microsecondsSinceEpoch}.pdf';
      _pdfSources[filePath] = fileData.toUint8List();
      final String pdfTitle =
          fileData.fileName?.replaceAll('.pdf', '') ?? 'Documento_PDF';
      if (!context.mounted || _disposed) return;
      final int existingPages = file?.pages?.length ?? 0;
      if (file?.pages?.firstOrNull?.infinite == true &&
          onOpenInNewTab == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Apri il PDF in un documento separato dal canvas infinito.',
            ),
          ),
        );
        return;
      }

      // Chiediamo DOVE inserire il PDF (senza cancellare nulla di esistente).
      final PdfInsertChoice? choice = file?.pages?.firstOrNull?.infinite == true
          ? PdfInsertChoice(mode: PdfInsertMode.start, newTab: true)
          : await _askPdfInsertPosition(context, existingPages);
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
    file!.autoGeneratePages = false;
    file!.pages!.insertAll(insertAt, newPages);
    _activeLayers.clear();

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
  Future<bool> saveFile(BuildContext context) => _saveFile(context);

  Future<bool> exportToXopp(BuildContext context) =>
      _saveFile(context, saveAs: true);

  Future<bool> _saveFile(BuildContext context, {bool saveAs = false}) async {
    if (savingFile || file == null) return false;
    savingFile = true;
    notifyListeners();
    try {
      if (audio.recording || audio.busy) await audio.stop();
      if (!context.mounted || _disposed) return false;
      if (_autosaveQueue != null) await _autosaveQueue;
      final savedRevision = _revision;
      final document = file!;
      bool addedAttachment = false;
      // Make existing native PDF references portable on the next save.
      for (final background
          in document.pages
                  ?.map((p) => p.background)
                  .whereType<XppBackgroundPdf>() ??
              <XppBackgroundPdf>[]) {
        final name = background.filename;
        if (name != null && !document.pdfAttachments.containsKey(name)) {
          document.pdfAttachments[name] = await _readPdfBytes(name);
          addedAttachment = true;
        }
      }
      final snapshot = document.snapshot();
      snapshot.modifiedAt ??= DateTime.now().toUtc();
      Uint8List? prepared;
      if (_checkpointRevision == savedRevision && !addedAttachment) {
        prepared = await AutosaveStore.checkpointBytes(
          document.documentId,
          snapshot.modifiedAt,
        );
        if (prepared != null)
          snapshot.previewImage = _checkpointPreview ?? snapshot.previewImage;
      }
      if (prepared == null) {
        await _preparePreview(snapshot);
        prepared = await snapshot.serializeSnapshotAsync();
      }
      final data = FilePickerCross(
        prepared,
        type: FileTypeCross.custom,
        fileExtension: 'xopp',
        path: document.suggestedFileName,
      );
      final String? absolutePath;
      if (saveAs || kIsWeb) {
        absolutePath = await _exportDocument(data);
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

      await RecentDocuments.save(snapshot, absolutePath);
      if (_revision == savedRevision) {
        document.previewImage = snapshot.previewImage;
        document.modifiedAt = snapshot.modifiedAt;
      }
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Documento salvato")));
      if (_revision == savedRevision) {
        hasUnsavedChanges = false;
        _autosaveTimer?.cancel();
        _autosaveDeadline?.cancel();
        _autosaveDeadline = null;
        if (_autosaveQueue != null) await _autosaveQueue;
        if (_revision == savedRevision && autosaveEnabled) {
          autosaveError = null;
          try {
            await AutosaveStore.remove(document.documentId);
          } catch (error) {
            autosaveError = error.toString();
          }
        }
      }
      return true;
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Errore: $e")));
      return false;
    } finally {
      savingFile = false;
      if (autosaveEnabled &&
          hasUnsavedChanges &&
          !_disposed &&
          !_discardRecovery) {
        _scheduleAutosave();
      }
      notifyListeners();
    }
  }

  Future<void>? _thumbnailQueue;
  Future<Uint8List> buildPageThumbnail(int index) {
    final page = file!.pages![index];
    final result = (_thumbnailQueue ?? Future.value()).then((_) {
      if (_disposed || !file!.pages!.contains(page))
        throw StateError('Anteprima non disponibile');
      return _renderPageThumbnail(page, file!.pages!.indexOf(page));
    });
    final completed = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _thumbnailQueue = completed;
    unawaited(
      completed.then((_) {
        if (identical(_thumbnailQueue, completed)) _thumbnailQueue = null;
      }),
    );
    return result;
  }

  Future<Uint8List> _renderPageThumbnail(XppPage source, int index) async {
    final page = exportPageSnapshot(source);
    Uint8List? background;
    if (page.background case final XppBackgroundPdf pdf) {
      background =
          await (pdfRasterizer?.call(index) ??
              _rasterPdfBackground(pdf, pixelBudget: 50000));
      if (background == null) throw StateError('Sfondo non disponibile');
    } else if (page.background case final XppBackgroundImage image) {
      if (image.filename != null)
        background = await _readPdfBytes(image.filename!);
    }
    return rasterizeExportPage(
      page,
      backgroundBytes: background,
      maxDimension: 180,
      pixelBudget: 50000,
    );
  }

  Future<void> _preparePreview(XppFile snapshot) async {
    try {
      snapshot.previewImage = await buildPreviewBytes(snapshot);
    } catch (_) {
      snapshot.previewImage = kTransparentImage;
    }
  }

  /// Uses document painters, not a screenshot of mounted pages. Works for
  /// inactive tabs and infinite notes, including their visible layers.
  Future<Uint8List> buildPreviewBytes([XppFile? snapshot]) async {
    final document = snapshot ?? file!;
    final source = document.pages?.firstOrNull;
    if (source == null) throw StateError('Documento senza pagine');
    final page = snapshot == null || source.infinite
        ? exportPageSnapshot(source)
        : source;
    Uint8List? background;
    if (page.background case final XppBackgroundPdf pdf) {
      background =
          pdfBackgrounds[0] ??
          await (pdfRasterizer?.call(0) ??
              _rasterPdfBackground(pdf, pixelBudget: 100000));
      if (background == null) throw StateError('Sfondo PDF non disponibile');
    } else if (page.background case final XppBackgroundImage image) {
      if (image.filename == null) {
        throw StateError('Sfondo immagine non disponibile');
      }
      background = await _readPdfBytes(image.filename!);
    }
    return rasterizeExportPage(
      page,
      backgroundBytes: background,
      maxDimension: 320,
      pixelBudget: 100000,
    );
  }

  Future<Uint8List> buildPdfBytes() async {
    final document = file;
    if (document == null) throw StateError('Nessun documento aperto');
    // One source handle at a time across adjacent exported PDF pages. An export
    // owns its handles independently of the visible canvas and thumbnail queue.
    pdfx.PdfDocument? source;
    String? sourceName;
    try {
      return await buildNotesPdf(
        document,
        loadBackground: (index, background) async {
          if (background is XppBackgroundPdf) {
            if (pdfRasterizer != null) return pdfRasterizer!(index);
            final name = background.filename;
            if (name == null) return null;
            if (sourceName != name) {
              final previous = source;
              source = null;
              sourceName = null;
              if (previous != null) await previous.close();
              source = await _openPdf(name);
              sourceName = name;
            }
            return _renderPdfPage(source!, background, pixelBudget: 4000000);
          }
          if (background is XppBackgroundImage && background.filename != null)
            return _readPdfBytes(background.filename!);
          return null;
        },
      );
    } finally {
      await source?.close();
    }
  }

  Future<Uint8List?> pluginPageBackground(int index) async {
    final background = file!.pages![index].background;
    if (background is XppBackgroundPdf) {
      return await (pdfRasterizer?.call(index) ??
          _rasterPdfBackground(background, pixelBudget: 4000000));
    }
    if (background is XppBackgroundImage && background.filename != null)
      return _readPdfBytes(background.filename!);
    return null;
  }

  Future<void> exportToPdf(BuildContext context) async {
    if (savingFile || file == null) return;
    final fileName =
        '${file!.suggestedFileName.substring(0, file!.suggestedFileName.length - 5)}.pdf';
    savingFile = true;
    notifyListeners();
    try {
      final bytes = await buildPdfBytes();
      final data = FilePickerCross(
        bytes,
        type: FileTypeCross.custom,
        fileExtension: 'pdf',
        path: fileName,
      );
      final destination = await _exportDocument(data);
      if (destination != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('PDF esportato')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Errore esportazione PDF: $e')));
      }
    } finally {
      savingFile = false;
      notifyListeners();
    }
  }

  // --- GESTIONE DEI TRATTI E UNDO ---
  void addNewContent(int pageIndex, XppContent? newContent) {
    if (newContent == null || !canEditLayer(pageIndex)) return;
    saveSnapshot(pageIndex);
    hasUnsavedChanges = true;
    activeLayer(pageIndex).content ??= [];
    activeLayer(pageIndex).content!.add(newContent);
    _growAfterInk(pageIndex, newContent);
    pageStackKeys[pageIndex]?.currentState?.setPageData(
      file!.pages![pageIndex],
    );
    notifyListeners();
  }

  void deleteContent(int pageIndex, List<XppContent> deleted) {
    if (!canEditLayer(pageIndex)) return;
    saveSnapshot(pageIndex);
    hasUnsavedChanges = true;
    activeLayer(pageIndex).content!
        .removeWhere((element) => deleted.contains(element));
    pageStackKeys[pageIndex]?.currentState?.setPageData(
      file!.pages![pageIndex],
    );
    notifyListeners();
  }

  List<XppContent> pasteSelection(int pageIndex, Offset position) {
    if (!canEditLayer(pageIndex)) return [];
    final pasted = clipboard.pasteAt(position);
    var bytes = audio.totalBytes;
    for (final stroke in pasted.whereType<XppStroke>()) {
      final id = stroke.audioLink?.recordingId;
      if (id == null || file!.recordings.containsKey(id)) continue;
      final recording = clipboard.recordings[id];
      if (recording != null &&
          bytes + recording.bytes.length <= maxAudioBytes) {
        file!.recordings[id] = recording;
        bytes += recording.bytes.length;
      } else {
        stroke.audioLink = null;
      }
    }
    if (pasted.isEmpty) return pasted;
    saveSnapshot(pageIndex);
    final layer = activeLayer(pageIndex);
    layer.content ??= [];
    layer.content!.addAll(pasted);
    markContentChanged(pageIndex);
    return pasted;
  }

  void removeLastContent(int pageIndex) {
    if (!canEditLayer(pageIndex)) return;
    if (activeLayer(pageIndex).content!.isEmpty) return;
    saveSnapshot(pageIndex);
    hasUnsavedChanges = true;
    activeLayer(pageIndex).content!.removeLast();
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
    if (coordinates == null || !canEditLayer(pageIndex)) return;
    final tipRadius = radius ?? 5;
    final cut = StrokeErasure(
      previousCoordinates ?? coordinates,
      coordinates,
      tipRadius,
    );
    if (!cut.isValid) return;
    final contents = activeLayer(pageIndex).content ?? [];
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
      final points = content.points;
      if (points == null || points.isEmpty) continue;
      final bounds = _eraserBounds.putIfAbsent(points, content.bounds);
      if (bounds == null || !bounds.overlaps(cut.bounds)) continue;
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

  List<XppLayer> snapshotLayers(int page) => [
    for (final layer in file!.pages![page].layers!)
      XppLayer(
        name: layer.name,
        visible: layer.visible,
        locked: layer.locked,
        content: cloneContents(layer.content ?? []),
      ),
  ];

  void saveSnapshot(int pageIndex) {
    if (file?.pages == null || file!.pages!.isEmpty) return;
    undoStack.add(
      PageSnapshot(
        pageIndex,
        snapshotLayers(pageIndex),
        activeLayerIndex(pageIndex),
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
        snapshotLayers(last.pageIndex),
        activeLayerIndex(last.pageIndex),
      ),
    );
    file!.pages![last.pageIndex].layers = last.layers;
    _activeLayers[last.pageIndex] = last.activeIndex;
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
        snapshotLayers(future.pageIndex),
        activeLayerIndex(future.pageIndex),
      ),
    );
    file!.pages![future.pageIndex].layers = future.layers;
    _activeLayers[future.pageIndex] = future.activeIndex;
    pageStackKeys[future.pageIndex]?.currentState?.setPageData(
      file!.pages![future.pageIndex],
    );
    hasUnsavedChanges = true;
    notifyListeners();
  }

  void setTool(EditingTool t) {
    if (audio.listenMode) audio.setListenMode(false);
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

  final ValueNotifier<int> pageNavigation = ValueNotifier(0);
  XppPage? _lastAutomaticBlank;
  void setActivePage(int index) {
    if (_disposed || file?.pages?.isEmpty != false) return;
    final next = index.clamp(0, file!.pages!.length - 1);
    if (next == activePageIndex) return;
    activePageIndex = next;
    notifyListeners();
  }

  void goToPage(int index) {
    setActivePage(index);
    pageNavigation.value++;
  }

  void addPage() => insertPage(after: true);
  void insertPage({required bool after}) => insertBlankPage(
    activePageIndex + (after ? 1 : 0),
    reference: activePageIndex,
    navigate: true,
  );

  void insertBlankPage(
    int at, {
    required int reference,
    bool navigate = false,
  }) {
    final pages = file?.pages;
    if (_disposed ||
        pages == null ||
        pages.isEmpty ||
        pages.any((p) => p.infinite) ||
        pages.length >= 10000)
      return;
    final previous = pages[reference.clamp(0, pages.length - 1)];
    final size = XppPageSize(
      width: previous.pageSize!.width,
      height: previous.pageSize!.height,
    );
    final page = XppPage.empty(
      pageSize: size,
      template:
          _cloneBackgroundForNewPage(previous.background, size) ??
          XppBackgroundSolidLined(color: Colors.white, size: size),
    );
    at = at.clamp(0, pages.length);
    // Index changes preserve layer selection and existing ink undo history.
    void shift<T>(Map<int, T> map) {
      final old = Map<int, T>.of(map);
      map.clear();
      for (final e in old.entries) {
        map[e.key >= at ? e.key + 1 : e.key] = e.value;
      }
    }

    shift(_activeLayers);
    shift(pageStackKeys);
    for (final stack in [undoStack, redoStack]) {
      for (var i = 0; i < stack.length; i++) {
        final old = stack[i];
        if (old.pageIndex >= at)
          stack[i] = PageSnapshot(
            old.pageIndex + 1,
            old.layers,
            old.activeIndex,
          );
      }
    }
    _pdfEpoch++;
    _visiblePdfPages = {};
    pdfBackgrounds.clear();
    pdfErrors.clear();
    pages.insert(at, page);
    if (activePageIndex >= at) activePageIndex++;
    hasUnsavedChanges = true;
    notifyListeners();
    if (navigate) goToPage(at);
  }

  bool get automaticPagesEnabled =>
      file?.autoGeneratePages == true &&
      file!.pages!.every(
        (p) => !p.infinite && p.background is! XppBackgroundPdf,
      );
  bool requestNextPageFromScroll() {
    if (!automaticPagesEnabled) return false;
    final last = file!.pages!.last;
    final empty = last.layers!.every((l) => l.content?.isEmpty != false);
    if (empty && identical(last, _lastAutomaticBlank)) return false;
    insertBlankPage(file!.pages!.length, reference: file!.pages!.length - 1);
    _lastAutomaticBlank = file!.pages!.last;
    return !identical(last, _lastAutomaticBlank);
  }

  void _growAfterInk(int page, XppContent content) {
    if (!automaticPagesEnabled ||
        page != file!.pages!.length - 1 ||
        content is! XppStroke ||
        content.tool == XppStrokeTool.ERASER)
      return;
    final bounds = content.bounds();
    if (bounds != null &&
        bounds.bottom >= file!.pages![page].pageSize!.height * .88) {
      insertBlankPage(file!.pages!.length, reference: page);
      _lastAutomaticBlank = file!.pages!.last;
    }
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
