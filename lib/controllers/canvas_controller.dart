import 'dart:async';
import 'dart:convert';

import 'package:xournalpp/src/stylus_shortcut.dart';

import 'package:xournalpp/src/stylus_profile.dart';

import 'dart:collection';

import 'note_audio_controller.dart';

import 'package:xournalpp/src/note_audio.dart';
import 'package:xournalpp/src/note_flashcards.dart';

import 'package:xournalpp/src/autosave_store.dart';
import 'package:xournalpp/src/recent_documents.dart';

import 'package:flutter/foundation.dart';

import 'dart:math' as math;

import 'package:xournalpp/src/pdf_raster_cache.dart';
import 'package:xournalpp/src/pdf_selection.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/decoded_image_cache.dart';
import 'package:transparent_image/transparent_image.dart';

import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:xournalpp/src/compat/file_picker_cross.dart';

import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/PdfImage.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/content_snapshot.dart';
import 'package:xournalpp/src/document_limits.dart';
import 'package:xournalpp/src/document_export.dart';
import 'package:xournalpp/src/selection_clipboard.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/paper_template.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

import 'package:xournalpp/layer_contents/XppStroke.dart';

class PageSnapshot {
  final int pageIndex;
  final List<XppLayer> layers;
  final int activeIndex;
  final XppPageSize? pageSize;
  List<XppContent?> get content => layers[activeIndex].content ?? [];
  PageSnapshot(this.pageIndex, this.layers, this.activeIndex, {this.pageSize});
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
  }) : clipboard = clipboard ?? SelectionClipboard() {
    if (autosaveEnabled) _backupSources.add(WeakReference(this));
  }

  static final _backupSources = <WeakReference<CanvasController>>[];
  static final _closingDocuments = <Future<void>>{};

  /// Secure current strokes and completed audio before collecting backup files.
  static Future<void> prepareForBackup() async {
    await Future.wait(_closingDocuments.toList());
    _backupSources.removeWhere(
      (reference) => reference.target == null || reference.target!._disposed,
    );
    for (final reference in _backupSources.toList()) {
      final controller = reference.target;
      if (controller == null ||
          controller._disposed ||
          controller._discardRecovery ||
          controller.file == null) {
        continue;
      }
      await controller.audio.stop();
      await controller.flushAutosave();
      if (controller.autosaveError != null) {
        throw StateError(
          'Salvataggio prima del backup non riuscito: ${controller.autosaveError}',
        );
      }
    }
  }

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
  bool penPressureEnabled = true;
  static const penPressurePreference = 'pen_pressure_enabled';
  List<StylusShortcut> stylusShortcuts = List.of(StylusShortcut.defaults);

  Future<void> setPenPressureEnabled(bool value) async {
    penPressureEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(penPressurePreference, value);
  }

  Future<void> setStylusShortcuts(List<StylusShortcut> shortcuts) async {
    if (shortcuts.length != 5) return;
    stylusShortcuts = List.unmodifiable(shortcuts);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      StylusShortcut.preferenceKey,
      jsonEncode(shortcuts.map((s) => s.toJson()).toList()),
    );
  }

  void applyStylusShortcut(StylusShortcut shortcut) {
    if (shortcut.tool == EditingTool.STYLUS) {
      penColor = shortcut.color;
      penWidth = shortcut.width;
    } else if (shortcut.tool == EditingTool.HIGHLIGHT) {
      highlighterColor = shortcut.color;
      highlighterWidth = shortcut.width;
    } else if (shortcut.tool == EditingTool.ERASER) {
      eraserWidth = shortcut.width;
    } else if (shortcut.tool.isShape) {
      shapeColor = shortcut.color;
      shapeWidth = shortcut.width;
    }
    setTool(shortcut.tool);
  }

  Color shapeColor = Colors.black;
  double shapeWidth = 2.5;
  FlashcardSide? flashcardFront;
  bool capturingFlashcard = false;
  int flashcardGeneration = 0;
  void refreshFlashcardTool() {
    if (!_disposed) notifyListeners();
  }

  Future<Uint8List?> flashcardBackground(int pageIndex) async {
    final background = file?.pages?[pageIndex].background;
    if (background is! XppBackgroundPdf) return null;
    return pdfBackgrounds[pageIndex] ??
        await _rasterPdfBackground(background, pixelBudget: 4000000);
  }

  void beginFlashcard() {
    flashcardFront = null;
    setTool(EditingTool.FLASHCARD);
  }

  void cancelFlashcard() {
    flashcardFront = null;
    if (toolData[PointerDeviceKind.stylus] == EditingTool.FLASHCARD) {
      setTool(EditingTool.STYLUS);
    }
  }

  void saveFlashcard(NoteFlashcard card) {
    if (savingFile || file == null) {
      throw StateError('Attendere il salvataggio');
    }
    FlashcardLimits.validate([
      ...file!.flashcards.values.where((e) => e.id != card.id),
      card,
    ]);
    file!.flashcards[card.id] = card;
    hasUnsavedChanges = true;
    notifyListeners();
  }

  void deleteFlashcard(String id) {
    if (savingFile || file == null) return;
    if (file!.flashcards.remove(id) != null) {
      hasUnsavedChanges = true;
      notifyListeners();
    }
  }

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
  Timer? _compactIdleTimer;
  final Set<int> _activeInputPointers = {};
  bool _inputInGrace = false;
  bool _compactDeferred = false;
  static const _compactInputGrace = Duration(milliseconds: 250);

  /// Background checkpoints wait for a break in writing, zooming or panning.
  /// Explicit flushes (save, lifecycle, close) always bypass this scheduling.
  void beginInput(int pointer) {
    if (_disposed || !autosaveEnabled) return;
    _activeInputPointers.add(pointer);
    _inputInGrace = true;
    _compactIdleTimer?.cancel();
  }

  void endInput(int pointer) {
    if (!_activeInputPointers.remove(pointer)) return;
    if (_activeInputPointers.isEmpty) {
      _scheduleCompactIdle();
    }
  }

  void _scheduleCompactIdle() {
    _compactIdleTimer?.cancel();
    _inputInGrace = true;
    _compactIdleTimer = Timer(_compactInputGrace, () {
      _inputInGrace = false;
      if (_compactDeferred) _scheduledCompact();
    });
  }

  void _scheduledCompact() {
    _autosaveDeadline?.cancel();
    _autosaveDeadline = null;
    if (_activeInputPointers.isNotEmpty || _inputInGrace) {
      _compactDeferred = true;
      // Keep the recovery deadline while avoiding preview/origin rewrites under
      // the pen. The complete journal remains durable throughout a long gesture.
      unawaited(flushAutosave(compact: false));
      _autosaveDeadline = Timer(const Duration(seconds: 10), _scheduledCompact);
      return;
    }
    _compactDeferred = false;
    unawaited(_flushAutosave(compact: true, scheduledOnly: true));
  }

  void _deferScheduledCompaction() {
    _compactDeferred = true;
    _autosaveDeadline ??= Timer(const Duration(seconds: 10), _scheduledCompact);
  }

  Future<void>? _autosaveQueue;
  int _checkpointRevision = -1;
  Uint8List? _checkpointPreview;
  bool _pageZeroDirty = true;
  DateTime? _originModifiedAt;
  bool _discardRecovery = false;
  DateTime? lastAutosave;
  String? autosaveError;
  bool autosaving = false;
  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(
      const Duration(seconds: 2),
      () => unawaited(flushAutosave(compact: false)),
    );
    _autosaveDeadline ??= Timer(const Duration(seconds: 10), _scheduledCompact);
  }

  Future<bool> _originChanged(XppFile document) async {
    final path = document.sourcePath;
    if (path == null || !await FilePickerCross.exists(path)) return false;
    if (document.originHash == null) return true;
    final lastMod = await FilePickerCross.lastModified(path);
    if (_originModifiedAt != null &&
        lastMod != null &&
        _originModifiedAt == lastMod) {
      return false;
    }
    final changed = await FilePickerCross.hashAt(path) != document.originHash;
    if (!changed && lastMod != null) {
      _originModifiedAt = lastMod;
    }
    return changed;
  }

  Future<void> flushAutosave({bool compact = true}) =>
      _flushAutosave(compact: compact);

  Future<void> _flushAutosave({
    required bool compact,
    bool scheduledOnly = false,
  }) {
    _autosaveTimer?.cancel();
    if (compact) {
      _compactDeferred = false;
      if (!scheduledOnly) {
        _compactIdleTimer?.cancel();
        _inputInGrace = false;
      }
      _autosaveDeadline?.cancel();
      _autosaveDeadline = null;
    }
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
        final deferCompact =
            compact &&
            scheduledOnly &&
            (_activeInputPointers.isNotEmpty || _inputInGrace);
        if (deferCompact) _deferScheduledCompaction();
        final snapshot = document.snapshot();
        Future<void> secureJournal() async {
          await AutosaveStore.saveIncremental(snapshot);
          await audio.acknowledge(snapshot.recordings.keys);
          lastAutosave = DateTime.now();
          autosaveError = null;
        }

        if (!compact || deferCompact) {
          await secureJournal();
          return;
        }
        await _preparePreview(snapshot);
        // Input can also begin while an asynchronous PDF preview is rendering.
        if (scheduledOnly &&
            (_activeInputPointers.isNotEmpty || _inputInGrace)) {
          _deferScheduledCompaction();
          await secureJournal();
          return;
        }
        final bytes = await snapshot.serializeSnapshotAsync();
        if (_discardRecovery) return;
        await AutosaveStore.save(snapshot, bytes);
        _checkpointRevision = revision;
        _checkpointPreview = snapshot.previewImage;
        await audio.acknowledge(snapshot.recordings.keys);
        lastAutosave = DateTime.now();
        // A recovery copy is always secured before touching the original file.
        // Browser documents stay recoverable locally until explicitly exported.
        if (!kIsWeb &&
            document.sourcePath != null &&
            !document.requiresSaveCopy &&
            !savingFile &&
            !_discardRecovery) {
          if (await _originChanged(document)) {
            document.importWarnings.add(
              'L’originale è cambiato: recupero conservato, salvare una copia',
            );
            throw StateError('Conflitto con l’originale: salvare una copia');
          }
          final destination = document.sourcePath!;
          final output = FilePickerCross(bytes);
          final hash = await output.contentHashAsync();
          final blobPath = await AutosaveStore.checkpointBlobPath(
            document.recoveryKey,
            snapshot.modifiedAt,
          );
          if (blobPath != null) {
            try {
              await FilePickerCross.saveFromFile(
                sourceFilePath: blobPath,
                destinationPath: destination,
              );
            } catch (_) {
              await output.saveToPath(path: destination);
            }
          } else {
            await output.saveToPath(path: destination);
          }
          if (!await output.verifyAt(destination, expectedHash: hash))
            throw StateError(
              'Scrittura non verificata: recupero locale conservato',
            );
          document.originHash = hash;
          _originModifiedAt = await FilePickerCross.lastModified(destination);
          await RecentDocuments.save(snapshot, destination);
          if (identical(file, document) && _revision == revision) {
            _hasUnsavedChanges = false;
            document.previewImage = snapshot.previewImage;
          }
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
    _compactIdleTimer?.cancel();
    if (_autosaveQueue != null) await _autosaveQueue;
    if (file != null) await AutosaveStore.remove(file!.recoveryKey);
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
  StylusProfile stylusProfile = StylusProfile.automatic;

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
  // Only compressed viewport snapshots survive a tab switch. Native documents
  // are still closed, and inactive tabs share one application-wide budget.
  static final _suspendedPdfCaches = LinkedHashSet<CanvasController>();
  static const _inactivePdfCacheBytes = 32 * 1024 * 1024;
  bool _disposed = false;
  Set<int> _visiblePdfPages = {};
  bool _pdfImportPending = false;
  bool get pdfImportPending => _pdfImportPending;
  final Map<int, String> pdfErrors = {};
  Future<void>? _renderQueue;
  int _pdfEpoch = 0;
  String? linkedPdfPath;

  bool get isPanEnabled =>
      toolData[PointerDeviceKind.stylus] == EditingTool.MOVE;
  bool get isShapeTool {
    final tool = toolData[PointerDeviceKind.stylus];
    return tool?.isShape ?? false;
  }

  // RIPRISTINATO AD UN SOLO PARAMETRO (Così non rompe il routing della tua Home)
  void init(XppFile? initialFile) {
    if (file != null) return;
    file = initialFile;
    if (initialFile?.previewImage != null) {
      _checkpointPreview = initialFile!.previewImage;
      _pageZeroDirty = false;
    } else {
      _pageZeroDirty = true;
    }
    if (initialFile?.sourcePath != null) {
      unawaited(
        FilePickerCross.lastModified(initialFile!.sourcePath!)
            .then((time) {
              if (identical(file, initialFile)) {
                _originModifiedAt = time;
              }
            })
            .catchError((_) {}),
      );
    }
    if (file != null && audio.supported) unawaited(audio.recoverStaged());
    WidgetsBinding.instance.addObserver(this);
    // A restored checkpoint does not authorize overwriting its origin.
    if (initialFile?.recovered == true) _hasUnsavedChanges = true;
    toolData[PointerDeviceKind.stylus] = EditingTool.STYLUS;
    toolData[PointerDeviceKind.touch] = EditingTool.MOVE;
    // Coda-gomma delle penne per tavoletta grafica (Wacom & co.): sempre gomma.
    toolData[PointerDeviceKind.invertedStylus] = EditingTool.ERASER;

    SharedPreferences.getInstance()
        .then((prefs) {
          if (_disposed) return;
          penPressureEnabled = prefs.getBool(penPressurePreference) ?? true;
          try {
            final stored = prefs.getString(StylusShortcut.preferenceKey);
            if (stored != null) {
              final values = (jsonDecode(stored) as List)
                  .map(StylusShortcut.fromJson)
                  .toList();
              if (values.length == 5)
                stylusShortcuts = List.unmodifiable(values);
            }
          } catch (_) {
            /* Keep usable defaults for obsolete preferences. */
          }
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
          stylusProfile = StylusProfile.fromPreference(
            prefs.getString(StylusProfile.preferenceKey),
          );
          if (bDown != null) buttonDownAction = bDown;
          if (bUp != null) buttonUpAction = bUp;

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
    _backupSources.removeWhere(
      (reference) =>
          reference.target == null || identical(reference.target, this),
    );
    if (_suspendedPdfCaches.remove(this))
      DecodedImageCache.shared.release(this);
    _autosaveTimer?.cancel();
    _autosaveDeadline?.cancel();
    _compactIdleTimer?.cancel();
    _eraserBounds.clear();
    WidgetsBinding.instance.removeObserver(this);
    if (file != null) {
      final closing = audio
          .stop()
          .then((_) => flushAutosave())
          .whenComplete(audio.dispose);
      _closingDocuments.add(closing);
      unawaited(closing.whenComplete(() => _closingDocuments.remove(closing)));
    }
    _disposed = true;
    _releaseViewPdf();
    pageNavigation.dispose();
    _pdfEpoch++;
    _visiblePdfPages.clear();
    pdfBackgrounds.clear();
    pageStackKeys.clear();
    undoStack.clear();
    redoStack.clear();
    super.dispose();
  }

  void setVisiblePdfPages(Set<int> indices) {
    if (_disposed) return;
    if (indices.isNotEmpty && _suspendedPdfCaches.remove(this)) {
      // Visibility arrives after the returning canvas has retained its images.
      DecodedImageCache.shared.release(this);
    }
    if (_pdfImportPending) {
      // Retain viewport changes while the recovery copy is being committed.
      _visiblePdfPages = Set.of(indices);
      return;
    }
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

  void suspendPdfRendering({bool retainRasterCache = false}) {
    final wasSuspended = _suspendedPdfCaches.remove(this);
    final retained = retainRasterCache
        ? ([activePageIndex, ..._visiblePdfPages]
              .where((page) => _visiblePdfPages.contains(page))
              .toSet()
              .take(4)
              .toSet())
        : const <int>{};
    for (final page in pdfBackgrounds.keys.toList()) {
      if (!retained.contains(page)) pdfBackgrounds.remove(page);
    }
    _releaseViewPdf();
    _pdfEpoch++;
    _visiblePdfPages = {};
    if (pdfBackgrounds.isNotEmpty) {
      _suspendedPdfCaches.add(this);
      // Preserve the decoded first frame too, under the shared native budget.
      DecodedImageCache.shared.retain(this, [
        for (final page in pdfBackgrounds.keys.toList()) pdfBackgrounds[page]!,
      ]);
    } else if (wasSuspended) {
      DecodedImageCache.shared.release(this);
    }
    var bytes = _suspendedPdfCaches.fold<int>(
      0,
      (sum, controller) => sum + controller.pdfBackgrounds.byteCount,
    );
    while (bytes > _inactivePdfCacheBytes || _suspendedPdfCaches.length > 2) {
      final oldest = _suspendedPdfCaches.first;
      bytes -= oldest.pdfBackgrounds.byteCount;
      oldest.pdfBackgrounds.clear();
      _suspendedPdfCaches.remove(oldest);
      DecodedImageCache.shared.release(oldest);
    }
  }

  Future<pdfx.PdfDocument> _openPdf(String name) async {
    final bytes = await _readPdfBytes(name);
    return openPdfData(bytes);
  }

  Future<Uint8List> _readPdfBytes(String name) async {
    final embedded = file?.pdfAttachments[name];
    if (embedded != null) return embedded;
    throw StateError(
      'Sfondo non associato: seleziona esplicitamente l’allegato',
    );
  }

  bool hasMissingBackground(int index) {
    final name = switch (file?.pages?[index].background) {
      XppBackgroundPdf bg => bg.filename,
      XppBackgroundImage bg => bg.filename,
      _ => null,
    };
    return name != null && !file!.pdfAttachments.containsKey(name);
  }

  Future<void> associateBackground(BuildContext context, int index) async {
    if (_disposed || savingFile || file == null) return;
    final document = file!, page = file!.pages![index];
    final background = page.background;
    final name = switch (background) {
      XppBackgroundPdf bg => bg.filename,
      XppBackgroundImage bg => bg.filename,
      _ => null,
    };
    if (name == null) return;
    try {
      final selected = await FilePickerCross.importFromStorage(
        type: background is XppBackgroundPdf
            ? FileTypeCross.custom
            : FileTypeCross.image,
        fileExtension: background is XppBackgroundPdf ? 'pdf' : null,
      );
      if (background is XppBackgroundPdf) {
        final pdf = await openPdfData(selected.toUint8List());
        try {
          for (final p in document.pages!) {
            final b = p.background;
            if (b is XppBackgroundPdf &&
                b.filename == name &&
                (b.page ?? 0) >= pdf.pagesCount) {
              throw StateError(
                'Il PDF scelto non contiene tutte le pagine richieste',
              );
            }
          }
        } finally {
          await pdf.close();
        }
      }
      if (_disposed ||
          !context.mounted ||
          !identical(file, document) ||
          !document.pages!.contains(page) ||
          !identical(page.background, background)) {
        return;
      }
      document.attachSelectedBackground(name, selected);
      suspendPdfRendering();
      pdfErrors.clear();
      hasUnsavedChanges = true;
      notifyListeners();
    } catch (error) {
      if (context.mounted && error != 'No file selected.') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossibile associare lo sfondo: $error')),
        );
      }
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

  Object pdfDetailIdentity(int index) {
    final source = file!.pages![index].background as XppBackgroundPdf;
    return (_pdfEpoch, source.filename, source.page);
  }

  int pdfSourcePage(int index) =>
      ((file!.pages![index].background as XppBackgroundPdf).page ?? 0) + 1;

  /// Dedicated detail handle: never opens pages concurrently with the base queue.
  Future<pdfx.PdfDocument> openPdfDetail(int index) {
    if (_disposed) throw StateError('Documento chiuso');
    final source = file!.pages![index].background as XppBackgroundPdf;
    return _openPdf(source.filename!);
  }

  Future<XppImage?> copyPdfRegion(int index, List<Offset> polygon) async {
    if (_disposed || index < 0 || index >= (file?.pages?.length ?? 0))
      return null;
    final document = file;
    final page = document!.pages![index];
    final background = page.background;
    if (background is! XppBackgroundPdf || background.filename == null)
      return null;
    if (polygon.length < 3 ||
        polygon.length > 20000 ||
        polygon.any((p) => !p.dx.isFinite || !p.dy.isFinite))
      return null;
    final pageSize = page.pageSize;
    if (pageSize == null) return null;
    final filename = background.filename;
    final sourcePage = background.page;
    final epoch = _pdfEpoch;
    final selection = List<Offset>.of(polygon);
    bool current() =>
        !_disposed &&
        identical(file, document) &&
        epoch == _pdfEpoch &&
        index < document.pages!.length &&
        identical(document.pages![index], page) &&
        identical(page.background, background) &&
        identical(page.pageSize, pageSize) &&
        background.filename == filename &&
        background.page == sourcePage;
    final raster = await _rasterPdfBackground(background, pixelBudget: 4000000);
    if (!current() || raster == null) return null;
    final image = await cropPdfSelection(raster, pageSize.toSize(), selection);
    return current() ? image : null;
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
    validatePdfPage(document, background.page ?? 0);
    final page = await document.getPage((background.page ?? 0) + 1);
    try {
      validatePdfSize(page);
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
    void Function(String pdfPath, String title, Uint8List pickedBytes)?
    onOpenInNewTab,
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
        onOpenInNewTab?.call(filePath, pdfTitle, fileData.toUint8List());
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
      await _insertPdfAt(
        filePath,
        insertAt,
        pickedBytes: fileData.toUint8List(),
      );
    } catch (e) {
      if (e != 'No file selected.' && context.mounted && !_disposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossibile importare il PDF: $e')),
        );
      }
    } finally {
      _pdfImportPending = false;
      savingFile = false;
      notifyListeners();
    }
  }

  // Inserisce le pagine del PDF a [insertAt] SENZA toccare pagine/tratti esistenti.
  Future<void> _insertPdfAt(
    String pdfPath,
    int insertAt, {
    Uint8List? pickedBytes,
  }) async {
    savingFile = true;
    _pdfImportPending = true;
    notifyListeners();

    final source = pickedBytes != null
        ? FilePickerCross(pickedBytes, path: pdfPath)
        : await FilePickerCross.fromInternalPath(path: pdfPath);
    final document = await openPdfData(source.toUint8List());
    final attachmentName =
        'embedded_pdf_${file?.pdfAttachments.length ?? 0}.pdf';
    final int count = document.pagesCount;
    if (count < 1 ||
        count + (file?.pages?.length ?? 0) > DocumentLimits.standard.pages) {
      await document.close();
      throw const FormatException('Troppe pagine PDF');
    }

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
      final sizes = await pdfDocumentSizes(document);
      for (int i = 1; i <= count; i++) {
        final xppPage = XppPage.empty();
        xppPage.pageSize = sizes[i - 1];
        xppPage.background = XppBackgroundPdf(
          filename: attachmentName,
          page: i - 1,
          onUnavailable: (_) async => source,
        );
        newPages.add(xppPage);
      }
    } finally {
      await document.close();
    }

    if (_disposed) return;
    file!.pdfAttachments[attachmentName] = source.toUint8List();
    file!.autoGeneratePages = false;
    file!.pages!.insertAll(insertAt, newPages);
    _activeLayers.clear();
    if (insertAt == 0) _pageZeroDirty = true;

    // 3) Indici cambiati: rigeneriamo le chiavi degli stack e azzeriamo l'undo
    //    (gli snapshot erano legati ai vecchi indici di pagina).
    pageStackKeys.clear();
    undoStack.clear();
    redoStack.clear();

    hasUnsavedChanges = true;
    // Secure the imported document before the first native page render. In
    // particular, a PDF can be much more expensive to render than to inspect.
    await AutosaveStore.saveIncremental(file!.snapshot());
    if (_disposed) return;
    _pdfImportPending = false;
    savingFile = false;
    if (autosaveEnabled) _scheduleAutosave();
    notifyListeners();

    // 4) Renderizziamo gli sfondi delle nuove pagine all'offset corretto (in background).
    final visible = Set<int>.of(_visiblePdfPages);
    _visiblePdfPages = {};
    setVisiblePdfPages(visible);
  }

  // Carica un PDF in una scheda NUOVA e vuota.
  Future<void> loadPdfFresh(
    String pdfPath,
    String title, {
    Uint8List? pickedBytes,
  }) async {
    if (_disposed) return;
    // The workspace owns this instance and persists its local recovery key.
    // Replacing it leaves the workspace pointing at the original empty tab.
    file ??= XppFile.empty(title: title);
    file!.title = title;
    file!.pages = [];
    _pageZeroDirty = true;
    pdfBackgrounds.clear();
    linkedPdfPath = pdfPath;
    try {
      await _insertPdfAt(pdfPath, 0, pickedBytes: pickedBytes);
    } catch (e) {
      if (!_disposed) pdfErrors[0] = e.toString();
    } finally {
      _pdfImportPending = false;
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
      if (audio.recording || audio.busy || audio.cleaning) await audio.stop();
      if (!context.mounted || _disposed) return false;
      if (_autosaveQueue != null) await _autosaveQueue;
      final savedRevision = _revision;
      final document = file!;
      final oldRecoveryKey = document.recoveryKey;
      final snapshot = document.snapshot();
      if (!saveAs && !kIsWeb && await _originChanged(document))
        document.importWarnings.add(
          'L’originale è cambiato: salvare una copia',
        );
      saveAs |= document.requiresSaveCopy;
      if (!saveAs &&
          !kIsWeb &&
          document.sourcePath != null &&
          document.originHash != null &&
          await FilePickerCross.exists(document.sourcePath!) &&
          _revision == savedRevision &&
          !hasUnsavedChanges) {
        // The origin was verified above. A repeated save needs no new preview,
        // XML/base64 encoding, compression, checkpoint or provider overwrite.
        return true;
      }
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
          snapshot.pdfAttachments[name] = document.pdfAttachments[name]!;
          addedAttachment = true;
        }
      }
      snapshot.modifiedAt ??= DateTime.now().toUtc();
      Uint8List? prepared;
      if (_checkpointRevision == savedRevision && !addedAttachment) {
        prepared = await AutosaveStore.checkpointBytes(
          document.recoveryKey,
          snapshot.modifiedAt,
        );
        if (prepared != null)
          snapshot.previewImage = _checkpointPreview ?? snapshot.previewImage;
      }
      final securedCheckpoint = prepared != null;
      if (prepared == null) {
        await _preparePreview(snapshot);
        prepared = await snapshot.serializeSnapshotAsync();
      }
      // Manual saves have the same crash protection even when autosave is off.
      if (!securedCheckpoint) await AutosaveStore.save(snapshot, prepared);
      await audio.acknowledge(snapshot.recordings.keys);
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
        final blobPath = !kIsWeb
            ? await AutosaveStore.checkpointBlobPath(
                document.recoveryKey,
                snapshot.modifiedAt,
              )
            : null;
        if (blobPath != null) {
          String? saved;
          try {
            saved = await FilePickerCross.saveFromFile(
              sourceFilePath: blobPath,
              destinationPath: destination,
            );
          } catch (_) {
            saved = null;
          }
          absolutePath = saved ?? await data.saveToPath(path: destination);
        } else {
          absolutePath = await data.saveToPath(path: destination);
        }
      }
      final hash = await data.contentHashAsync();
      final verified =
          !kIsWeb &&
          data.reopenableGrant &&
          await data.verifyAt(absolutePath, expectedHash: hash);
      if (verified) {
        document.sourcePath = absolutePath;
        document.originHash = hash;
        _originModifiedAt = await FilePickerCross.lastModified(absolutePath);
        document.importWarnings.clear();
        snapshot.sourcePath = absolutePath;
        await RecentDocuments.save(snapshot, absolutePath);
      } else {
        document.importWarnings.add(
          'Copia esportata senza verifica o accesso persistente: il recupero locale è conservato, salvare una nuova copia',
        );
      }
      if (_revision == savedRevision) {
        document.previewImage = snapshot.previewImage;
        document.modifiedAt = snapshot.modifiedAt;
      }
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              verified
                  ? 'Documento salvato e verificato'
                  : 'Copia esportata; recupero locale conservato',
            ),
          ),
        );
      if (_revision == savedRevision) {
        hasUnsavedChanges = false;
        _autosaveTimer?.cancel();
        _autosaveDeadline?.cancel();
        _autosaveDeadline = null;
        if (_autosaveQueue != null) await _autosaveQueue;
        if (_revision == savedRevision && verified) {
          autosaveError = null;
          try {
            await AutosaveStore.remove(oldRecoveryKey);
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
    if (!_pageZeroDirty && _checkpointPreview != null) {
      snapshot.previewImage = _checkpointPreview;
      return;
    }
    try {
      snapshot.previewImage = await buildPreviewBytes(snapshot);
      _checkpointPreview = snapshot.previewImage;
      _pageZeroDirty = false;
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
    final prepared = await buildPreparedPdf();
    try {
      return prepared.bytes ??
          (await FilePickerCross.fromInternalPath(path: prepared.path!))
              .toUint8List();
    } finally {
      await prepared.dispose();
    }
  }

  Future<PreparedPdf> buildPreparedPdf() async {
    final document = file;
    if (document == null) throw StateError('Nessun documento aperto');
    // One source handle at a time across adjacent exported PDF pages. An export
    // owns its handles independently of the visible canvas and thumbnail queue.
    pdfx.PdfDocument? source;
    String? sourceName;
    try {
      return await prepareNotesPdf(
        document,
        loadBackground: (index, background, pixelBudget) async {
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
            return _renderPdfPage(
              source!,
              background,
              pixelBudget: pixelBudget.toDouble(),
            );
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
    PreparedPdf? prepared;
    try {
      if (!kIsWeb && documentExporter == null) {
        prepared = await buildPreparedPdf();
        if (prepared.path == null) throw StateError('PDF non disponibile');
        final destination = await FilePickerCross.exportStagedFile(
          prepared.path!,
          fileName,
        );
        if (destination != null && context.mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('PDF esportato')));
        return;
      }
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
      await prepared?.dispose();
      savingFile = false;
      notifyListeners();
    }
  }

  // --- GESTIONE DEI TRATTI E UNDO ---
  void addNewContent(int pageIndex, XppContent? newContent) {
    if (newContent == null || !canEditLayer(pageIndex)) return;
    saveSnapshot(pageIndex);
    if (pageIndex == 0) _pageZeroDirty = true;
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
    if (pageIndex == 0) _pageZeroDirty = true;
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
    if (pageIndex == 0) _pageZeroDirty = true;
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
    if (pageIndex == 0) _pageZeroDirty = true;
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
        pageSize: pageIndex < file!.pages!.length
            ? file!.pages![pageIndex].pageSize
            : null,
      ),
    );
    if (undoStack.length > 50) undoStack.removeAt(0);
    redoStack.clear();
    notifyListeners();
  }

  void undo() {
    if (undoStack.isEmpty) return;
    final last = undoStack.removeLast();
    final page = file?.pages != null && last.pageIndex < file!.pages!.length
        ? file!.pages![last.pageIndex]
        : null;
    final currentSize = page?.pageSize;
    redoStack.add(
      PageSnapshot(
        last.pageIndex,
        snapshotLayers(last.pageIndex),
        activeLayerIndex(last.pageIndex),
        pageSize: currentSize,
      ),
    );
    file!.pages![last.pageIndex].layers = last.layers;
    _activeLayers[last.pageIndex] = last.activeIndex;
    if (page != null && last.pageSize != null) {
      page.pageSize = last.pageSize;
      if (page.background != null) {
        page.background!.size = last.pageSize;
      }
    }
    pageStackKeys[last.pageIndex]?.currentState?.setPageData(
      file!.pages![last.pageIndex],
    );
    if (last.pageIndex == 0) _pageZeroDirty = true;
    hasUnsavedChanges = true;
    notifyListeners();
  }

  void redo() {
    if (redoStack.isEmpty) return;
    final future = redoStack.removeLast();
    final page = file?.pages != null && future.pageIndex < file!.pages!.length
        ? file!.pages![future.pageIndex]
        : null;
    final currentSize = page?.pageSize;
    undoStack.add(
      PageSnapshot(
        future.pageIndex,
        snapshotLayers(future.pageIndex),
        activeLayerIndex(future.pageIndex),
        pageSize: currentSize,
      ),
    );
    file!.pages![future.pageIndex].layers = future.layers;
    _activeLayers[future.pageIndex] = future.activeIndex;
    if (page != null && future.pageSize != null) {
      page.pageSize = future.pageSize;
      if (page.background != null) {
        page.background!.size = future.pageSize;
      }
    }
    pageStackKeys[future.pageIndex]?.currentState?.setPageData(
      file!.pages![future.pageIndex],
    );
    if (future.pageIndex == 0) _pageZeroDirty = true;
    hasUnsavedChanges = true;
    notifyListeners();
  }

  void setTool(EditingTool t) {
    flashcardGeneration++;
    if (t != EditingTool.FLASHCARD) flashcardFront = null;
    if (audio.listenMode) audio.setListenMode(false);
    toolData = Map.from(toolData);
    toolData[PointerDeviceKind.touch] =
        touchDrawingEnabled || t == EditingTool.FLASHCARD
        ? t
        : EditingTool.MOVE;
    if (t == EditingTool.FLASHCARD ||
        toolData.containsKey(PointerDeviceKind.mouse)) {
      toolData[PointerDeviceKind.mouse] = t;
    }
    toolData[PointerDeviceKind.stylus] = t;
    // La coda-gomma delle penne da tavoletta resta sempre gomma.
    toolData[PointerDeviceKind.invertedStylus] = EditingTool.ERASER;
    notifyListeners();
  }

  void markContentChanged(int pageIndex) {
    if (pageIndex == 0) _pageZeroDirty = true;
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

  bool get canDeletePage =>
      !_disposed &&
      !savingFile &&
      (file?.pages?.length ?? 0) > 1 &&
      file!.pages!.every((p) => !p.infinite);

  bool pageHasAnnotations(int index) =>
      file!.pages![index].layers?.any(
        (layer) => layer.content?.any((c) => c != null) ?? false,
      ) ??
      false;

  bool deletePage(int index) {
    if (!canDeletePage || index < 0 || index >= file!.pages!.length)
      return false;
    final pages = file!.pages!;
    final removed = pages.removeAt(index);
    void shift<T>(Map<int, T> map) {
      final old = Map<int, T>.of(map);
      map.clear();
      for (final e in old.entries) {
        if (e.key != index) map[e.key > index ? e.key - 1 : e.key] = e.value;
      }
    }

    shift(_activeLayers);
    shift(pageStackKeys);
    for (final stack in [undoStack, redoStack]) {
      stack.removeWhere((s) => s.pageIndex == index);
      for (var i = 0; i < stack.length; i++) {
        final s = stack[i];
        if (s.pageIndex > index)
          stack[i] = PageSnapshot(
            s.pageIndex - 1,
            s.layers,
            s.activeIndex,
            pageSize: s.pageSize,
          );
      }
    }
    if (identical(removed, _lastAutomaticBlank)) _lastAutomaticBlank = null;
    activePageIndex =
        (activePageIndex > index ? activePageIndex - 1 : activePageIndex).clamp(
          0,
          pages.length - 1,
        );
    _pdfEpoch++;
    _visiblePdfPages = {};
    pdfBackgrounds.clear();
    pdfErrors.clear();
    if (index == 0) _pageZeroDirty = true;
    hasUnsavedChanges = true;
    notifyListeners();
    // Wait until the shorter column has laid out before navigating to its page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) pageNavigation.value++;
    });
    return true;
  }

  void insertPage({required bool after, PaperSettings? paper}) =>
      insertBlankPage(
        activePageIndex + (after ? 1 : 0),
        reference: activePageIndex,
        navigate: true,
        paper: paper,
      );

  void insertBlankPage(
    int at, {
    required int reference,
    bool navigate = false,
    PaperSettings? paper,
  }) {
    final pages = file?.pages;
    if (_disposed ||
        pages == null ||
        pages.isEmpty ||
        pages.any((p) => p.infinite) ||
        pages.length >= 10000)
      return;
    final chosen = paper ?? file!.defaultPaper;
    final size = chosen.size;
    final page = XppPage.empty(pageSize: size, template: chosen.build());
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
            pageSize: old.pageSize,
          );
      }
    }
    _pdfEpoch++;
    _visiblePdfPages = {};
    pdfBackgrounds.clear();
    pdfErrors.clear();
    pages.insert(at, page);
    if (at == 0) _pageZeroDirty = true;
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

  Color getCurrentToolColor() =>
      toolData[PointerDeviceKind.stylus] == EditingTool.HIGHLIGHT
      ? highlighterColor
      : isShapeTool
      ? shapeColor
      : penColor;
  double getCurrentToolWidth() =>
      toolData[PointerDeviceKind.stylus] == EditingTool.HIGHLIGHT
      ? highlighterWidth
      : (toolData[PointerDeviceKind.stylus] == EditingTool.ERASER
            ? eraserWidth
            : isShapeTool
            ? shapeWidth
            : penWidth);
  void setShapeProps(Color? c, double? w) {
    if (c != null) shapeColor = c;
    if (w != null) shapeWidth = w;
    notifyListeners();
  }

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

  /// Espande la pagina specificata aggiungendo larghezza a destra ([deltaWidth])
  /// e/o altezza in basso ([deltaHeight]).
  void expandPage(
    int pageIndex, {
    double deltaWidth = 0.0,
    double deltaHeight = 300.0,
  }) {
    if (file?.pages == null ||
        pageIndex < 0 ||
        pageIndex >= file!.pages!.length) {
      return;
    }
    final page = file!.pages![pageIndex];
    final currentSize = page.pageSize ?? XppPageSize.a4;
    final newWidth = (currentSize.width + deltaWidth).clamp(100.0, 10000.0);
    final newHeight = (currentSize.height + deltaHeight).clamp(100.0, 10000.0);
    resizePage(pageIndex, width: newWidth, height: newHeight);
  }

  /// Imposta dimensioni personalizzate (larghezza e altezza in pt) per la pagina.
  void resizePage(
    int pageIndex, {
    required double width,
    required double height,
  }) {
    if (file?.pages == null ||
        pageIndex < 0 ||
        pageIndex >= file!.pages!.length) {
      return;
    }
    saveSnapshot(pageIndex);
    final page = file!.pages![pageIndex];
    final newSize = XppPageSize(
      width: width.clamp(100.0, 10000.0),
      height: height.clamp(100.0, 10000.0),
    );
    page.pageSize = newSize;
    if (page.background != null) {
      page.background!.size = newSize;
    }
    if (pageIndex == 0) _pageZeroDirty = true;
    pageStackKeys[pageIndex]?.currentState?.setPageData(page);
    hasUnsavedChanges = true;
    flushAutosave();
    notifyListeners();
  }
}
