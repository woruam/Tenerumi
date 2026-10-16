import 'dart:typed_data';

import 'package:xournalpp/plugins/plugin_controller.dart';
import 'package:xournalpp/src/app_features.dart';
import 'package:xournalpp/widgets/bounded_image.dart';
import 'package:xournalpp/widgets/note_flashcards_panel.dart';

import '../widgets/audio_timeline_overlay.dart';

import 'package:xournalpp/widgets/pdf_zoom_detail.dart';
import 'package:xournalpp/src/XppBackground.dart';

import 'package:xournalpp/src/app_appearance.dart';

import 'dart:math';

import 'package:xournalpp/src/document_scene_geometry.dart';
import 'package:xournalpp/widgets/split_resize_scope.dart';
import 'package:xournalpp/widgets/virtual_page_column.dart';
import 'package:xournalpp/widgets/infinite_canvas.dart';

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/widgets/page_scrollbar.dart';
import 'package:provider/provider.dart';

import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';
import 'package:xournalpp/widgets/PomodoroTimer.dart';

import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/widgets/canvas_toolbar.dart';
import 'package:xournalpp/widgets/unsaved_document_dialog.dart';

import 'package:xournalpp/src/editing_tool.dart';

class StylusGestureRecognizer extends OneSequenceGestureRecognizer {
  bool blockStylusPan;
  StylusGestureRecognizer({required this.blockStylusPan});

  @override
  String get debugDescription => 'stylus_interceptor';

  @override
  void addPointer(PointerDownEvent event) {
    if (blockStylusPan &&
        (event.kind == PointerDeviceKind.stylus ||
            event.kind == PointerDeviceKind.invertedStylus)) {
      startTrackingPointer(event.pointer);
      resolve(GestureDisposition.accepted);
    } else {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent)
      stopTrackingPointer(event.pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}
}

class CanvasPage extends StatefulWidget {
  final XppFile? file;
  final String? filePath;
  // PDF da importare automaticamente quando la pagina nasce in una NUOVA scheda.
  final String? pdfToImportPath;
  final Uint8List? pdfToImportBytes;
  // Callback per aprire un PDF in una scheda separata (gestita dalla WorkspacePage).
  final void Function(String pdfPath, String title, Uint8List pickedBytes)?
  onOpenPdfInNewTab;
  // Controller esterno (fornito dal WorkspaceController in split). Se null, la pagina ne crea uno proprio.
  final CanvasController? controller;
  final TransformationController? zoomController;
  // In modalita' split la toolbar e' unica e globale: qui si nasconde quella interna.
  final bool showInternalToolbar;
  // Notifica al genitore che questo pannello ha ricevuto il focus (tocco/stilo).
  final VoidCallback? onFocus;
  const CanvasPage({
    Key? key,
    this.file,
    this.filePath,
    this.pdfToImportPath,
    this.pdfToImportBytes,
    this.onOpenPdfInNewTab,
    this.controller,
    this.zoomController,
    this.showInternalToolbar = true,
    this.onFocus,
  }) : super(key: key);
  @override
  CanvasPageState createState() => CanvasPageState();
}

class CanvasPageState extends State<CanvasPage> {
  double? _pageDisplayWidth;
  final Set<int> _activeInputs = {};

  void _endInput(PointerEvent event) {
    if (_activeInputs.remove(event.pointer)) {
      _controller.endInput(event.pointer);
    }
  }

  double _layoutPageWidth(
    double viewportWidth,
    bool resizing,
    CanvasController ctrl,
  ) {
    final next = max(1.0, viewportWidth - 32);
    final old = _pageDisplayWidth;
    if (resizing && old != null) return old;
    if (old != null && old != next) {
      final matrix = _zoomController.value.clone();
      final oldY = _zoomController.toScene(Offset.zero).dy;
      final newY = reflowSceneY(
        oldY,
        old,
        next,
        (ctrl.file?.pages ?? []).map((p) => p.pageSize!.ratio),
      );
      matrix.setEntry(1, 3, -newY * matrix.getMaxScaleOnAxis());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageDisplayWidth == next)
          _zoomController.value = matrix;
      });
    }
    return _pageDisplayWidth = next;
  }

  late CanvasController _controller;
  late final TransformationController _zoomController;
  final GlobalKey _pdfViewportKey = GlobalKey();
  final GlobalKey<ZoomableWidgetState> _zoomableKey = GlobalKey();

  final GlobalKey _penBtn = GlobalKey(),
      _highlighterBtn = GlobalKey(),
      _shapeBtn = GlobalKey(),
      _eraserBtn = GlobalKey();
  bool _showPomodoro = false;
  final _pomodoroProgress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _zoomController = widget.zoomController ?? TransformationController();
    // Torna ad essere così! Niente widget.filePath
    // Usa il controller esterno se fornito (split: lo possiede il WorkspaceController),
    // altrimenti la pagina ne crea uno proprio (uso a tab singola).
    _controller = widget.controller ?? (CanvasController()..init(widget.file));
    _controller.pageNavigation.addListener(_navigateToPage);
    // Scheda nuova creata per un PDF: importiamolo appena pronta la UI.
    if (widget.pdfToImportPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.loadPdfFresh(
          widget.pdfToImportPath!,
          widget.file?.title ?? 'PDF',
          pickedBytes: widget.pdfToImportBytes,
        );
      });
    }
  }

  void _navigateToPage() {
    final pages = _controller.file?.pages;
    if (pages == null || _pageDisplayWidth == null) return;
    double top = 24;
    for (var i = 0; i < _controller.activePageIndex; i++) {
      top += _pageDisplayWidth! / pages[i].pageSize!.ratio + 24;
    }
    final matrix = _zoomController.value.clone();
    matrix.setEntry(1, 3, 24 - top * matrix.getMaxScaleOnAxis());
    _zoomController.value = matrix;
  }

  Future<bool> promptSaveIfUnsaved() =>
      confirmDocumentClose(context, _controller);

  @override
  void deactivate() {
    // Pin decoded backgrounds before the child image widgets release them.
    _controller.suspendPdfRendering(
      retainRasterCache: widget.controller != null,
    );
    super.deactivate();
  }

  @override
  void dispose() {
    _pomodoroProgress.dispose();
    for (final pointer in _activeInputs) {
      _controller.endInput(pointer);
    }
    _activeInputs.clear();
    _controller.pageNavigation.removeListener(_navigateToPage);
    if (widget.zoomController == null) _zoomController.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resizing = SplitResizeScope.isResizing(context);
    final appearance = context.watch<ThemeController?>();
    final plugins = AppFeatures.plugins
        ? context.watch<PluginController?>()
        : null;
    final pomodoroEnabled =
        AppFeatures.plugins && plugins?.pomodoroEnabled == true;
    if (!pomodoroEnabled) _showPomodoro = false;
    if (plugins?.ankiEnabled != true &&
        _controller.toolData[PointerDeviceKind.stylus] ==
            EditingTool.FLASHCARD) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.cancelFlashcard();
      });
    }
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<CanvasController>(
        builder: (context, ctrl, child) {
          return Scaffold(
            backgroundColor: Theme.of(
              context,
            ).scaffoldBackgroundColor, // segue il tema (nero puro se attivato)

            appBar: widget.showInternalToolbar
                ? CanvasToolbar(
                    penKey: _penBtn,
                    highlighterKey: _highlighterBtn,
                    shapeKey: _shapeBtn,
                    eraserKey: _eraserBtn,
                    onPenTap: () => _openSettingsMenu(
                      context,
                      ctrl,
                      _penBtn,
                      'Penna',
                      [
                        Colors.black,
                        Colors.grey,
                        Colors.white,
                        Colors.red,
                        Colors.blue,
                        Colors.green,
                        Colors.purple,
                        Colors.orange,
                      ],
                      ctrl.penColor,
                      ctrl.penWidth,
                      ctrl.setPenProps,
                    ),
                    onHighlighterTap: () => _openSettingsMenu(
                      context,
                      ctrl,
                      _highlighterBtn,
                      'Evidenziatore',
                      [
                        const Color(0xFFFFF59D),
                        const Color(0xFFA5D6A7),
                        const Color(0xFF81D4FA),
                        const Color(0xFFF48FB1),
                        const Color(0xFFCE93D8),
                        const Color(0xFFFFCC80),
                      ],
                      ctrl.highlighterColor,
                      ctrl.highlighterWidth,
                      ctrl.setHighlighterProps,
                    ),
                    onShapeTap: () => _openShapeSettings(context, ctrl),
                    onEraserTap: () => _openEraserSettings(context, ctrl),
                    onImportPdf: () => ctrl.importPdf(
                      context,
                      onOpenInNewTab: widget.onOpenPdfInNewTab,
                    ),
                    onPomodoroTap: () =>
                        setState(() => _showPomodoro = !_showPomodoro),
                    pomodoroActive: _showPomodoro,
                    pomodoroProgress: _pomodoroProgress,
                    onToolSelect: (tool) {
                      ctrl.setTool(tool);
                      _zoomableKey.currentState?.setState(
                        () => _zoomableKey.currentState!.enabled =
                            ctrl.isPanEnabled,
                      );
                    },
                  )
                : null,

            bottomNavigationBar: ctrl.file?.requiresSaveCopy == true
                ? MaterialBanner(
                    content: const Text(
                      'Apertura protetta: alcuni contenuti o il recupero richiedono verifica. Il salvataggio crea una copia.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Compatibilità e recupero'),
                            content: SingleChildScrollView(
                              child: Text(ctrl.file!.importWarnings.join('\n')),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Chiudi'),
                              ),
                            ],
                          ),
                        ),
                        child: const Text('Dettagli'),
                      ),
                    ],
                  )
                : null,
            body: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                _activeInputs.add(event.pointer);
                ctrl.beginInput(event.pointer);
                widget.onFocus?.call();
              },
              onPointerUp: _endInput,
              onPointerCancel: _endInput,
              child: Stack(
                children: [
                  RawGestureDetector(
                    gestures: <Type, GestureRecognizerFactory>{
                      StylusGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            StylusGestureRecognizer
                          >(
                            () => StylusGestureRecognizer(
                              blockStylusPan: !ctrl.isPanEnabled,
                            ),
                            (instance) =>
                                instance.blockStylusPan = !ctrl.isPanEnabled,
                          ),
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (ctrl.file?.pages?.firstOrNull?.infinite == true) {
                          return IgnorePointer(
                            ignoring: resizing,
                            child: Stack(
                              children: [
                                InfiniteCanvas(
                                  canvas: ctrl,
                                  transform: _zoomController,
                                ),
                                if (ctrl.hasMissingBackground(0))
                                  Positioned(
                                    top: 16,
                                    right: 16,
                                    child: FilledButton.icon(
                                      onPressed: () =>
                                          ctrl.associateBackground(context, 0),
                                      icon: const Icon(Icons.attach_file),
                                      label: const Text(
                                        'Seleziona allegato di sfondo',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }
                        final displayWidth = _layoutPageWidth(
                          constraints.maxWidth,
                          resizing,
                          ctrl,
                        );
                        return IgnorePointer(
                          ignoring: resizing,
                          child: SizedBox(
                            key: _pdfViewportKey,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            child: ZoomableWidget(
                              key: _zoomableKey,
                              controller: _zoomController,
                              sceneSize: Size(
                                displayWidth + 32,
                                24 +
                                    (ctrl.file?.pages ?? []).fold<double>(
                                      0,
                                      (sum, page) =>
                                          sum +
                                          displayWidth / page.pageSize!.ratio +
                                          24,
                                    ),
                              ),
                              stylusPanEnabled: ctrl.isPanEnabled,
                              onEndReached: () {
                                if (ctrl.requestNextPageFromScroll())
                                  ctrl.goToPage(ctrl.file!.pages!.length - 1);
                              },
                              interactionsEnabled: !resizing,
                              touchDrawingEnabled:
                                  ctrl.touchDrawingEnabled &&
                                  !ctrl.isPanEnabled,
                              // Un solo InteractiveViewer (pan verticale + pinch zoom): niente
                              // SingleChildScrollView annidato, cosi' i gesti non si litigano e le
                              // coordinate dello stilo restano allineate al foglio a ogni zoom.
                              child: VirtualPageColumn(
                                transform: _zoomController,
                                viewport: constraints.biggest,
                                width: displayWidth,
                                heights: [
                                  for (final page in ctrl.file?.pages ?? [])
                                    displayWidth / page.pageSize!.ratio,
                                ],
                                onVisiblePages: ctrl.setVisiblePdfPages,
                                onCurrentPage: ctrl.setActivePage,
                                currentPageBorderColor:
                                    appearance?.currentPageBorderColor ??
                                    ThemeController.kDefaultAccent,
                                pageBuilder: (pageIndex) {
                                  ctrl.pageStackKeys.putIfAbsent(
                                    pageIndex,
                                    () => GlobalKey<XppPageStackState>(),
                                  );

                                  final double dispW = displayWidth;

                                  return Container(
                                    width: dispW,
                                    decoration: BoxDecoration(
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Card(
                                      shape: const RoundedRectangleBorder(),
                                      clipBehavior: Clip.hardEdge,
                                      elevation: 0,
                                      margin: EdgeInsets.zero,
                                      color: Colors.white,
                                      child: AspectRatio(
                                        aspectRatio: ctrl
                                            .file!
                                            .pages![pageIndex]
                                            .pageSize!
                                            .ratio,
                                        child: FittedBox(
                                          child: PointerListener(
                                            audio: ctrl.audio,
                                            onListenAt: (p) =>
                                                ctrl.listenAt(pageIndex, p),
                                            key: ObjectKey(
                                              ctrl.activeLayer(pageIndex),
                                            ),
                                            readOnly: !ctrl.canEditLayer(
                                              pageIndex,
                                            ),
                                            translationMatrix:
                                                _zoomController.value,
                                            toolData: ctrl.toolData,
                                            strokeWidth: ctrl
                                                .getCurrentToolWidth(),
                                            highlighterWidth:
                                                ctrl.highlighterWidth,
                                            highlighterColor:
                                                ctrl.highlighterColor,
                                            onFlashcardSelection:
                                                AppFeatures.plugins
                                                ? (region) =>
                                                      captureFlashcardSelection(
                                                        context,
                                                        ctrl,
                                                        pageIndex,
                                                        region,
                                                      )
                                                : null,
                                            clipboard: ctrl.clipboard,
                                            selectionIdentity:
                                                ctrl.file!.pages![pageIndex],
                                            onCopyPdfRegion:
                                                ctrl
                                                        .file!
                                                        .pages![pageIndex]
                                                        .background
                                                    is XppBackgroundPdf
                                                ? (polygon) =>
                                                      ctrl.copyPdfRegion(
                                                        pageIndex,
                                                        polygon,
                                                      )
                                                : null,
                                            onPasteContent: (position) =>
                                                ctrl.pasteSelection(
                                                  pageIndex,
                                                  position,
                                                ),
                                            color: ctrl.getCurrentToolColor(),
                                            shapeRecognition:
                                                ctrl.shapeRecognition,
                                            buttonDownAction:
                                                ctrl.buttonDownAction,
                                            buttonUpAction: ctrl.buttonUpAction,

                                            // IL FIX DELLA SCRITTURA ANCHE QUI
                                            onToolChanged: (tool) {
                                              ctrl.setTool(tool);
                                              _zoomableKey.currentState
                                                  ?.setState(
                                                    () =>
                                                        _zoomableKey
                                                                .currentState!
                                                                .enabled =
                                                            ctrl.isPanEnabled,
                                                  );
                                            },

                                            getPageContent: () =>
                                                ctrl
                                                    .activeLayer(pageIndex)
                                                    .content ??
                                                [],
                                            onDeviceChange:
                                                ({
                                                  int? device,
                                                  PointerDeviceKind? kind,
                                                }) {
                                                  ctrl.activePageIndex =
                                                      pageIndex;
                                                },
                                            onDeleteContent: (deleted) =>
                                                ctrl.deleteContent(
                                                  pageIndex,
                                                  deleted,
                                                ),
                                            onBeforeContentChanged: () =>
                                                ctrl.saveSnapshot(pageIndex),
                                            onContentChanged: () => ctrl
                                                .markContentChanged(pageIndex),
                                            removeLastContent: () => ctrl
                                                .removeLastContent(pageIndex),
                                            filterEraser:
                                                ({
                                                  Offset? coordinates,
                                                  Offset? previousCoordinates,
                                                  double? radius,
                                                }) => ctrl.filterEraser(
                                                  pageIndex: pageIndex,
                                                  coordinates: coordinates,
                                                  previousCoordinates:
                                                      previousCoordinates,
                                                  radius: radius,
                                                ),
                                            eraserWidth: ctrl.eraserWidth,
                                            onEraserStart:
                                                ctrl.beginEraserGesture,
                                            onEraserEnd: ctrl.endEraserGesture,
                                            onNewContent: (newContent) =>
                                                ctrl.addNewContent(
                                                  pageIndex,
                                                  newContent,
                                                ),

                                            child: SizedBox(
                                              width: ctrl
                                                  .file!
                                                  .pages![pageIndex]
                                                  .pageSize!
                                                  .width,
                                              height: ctrl
                                                  .file!
                                                  .pages![pageIndex]
                                                  .pageSize!
                                                  .height,
                                              child: ClipRect(
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    // 1. IL PDF SULLO SFONDO (Se caricato)
                                                    if (ctrl.pdfBackgrounds
                                                        .containsKey(pageIndex))
                                                      BoundedImage(
                                                        ctrl.pdfBackgrounds[pageIndex]!,
                                                        fit: BoxFit.fill,
                                                      ),
                                                    if (ctrl.pdfErrors
                                                        .containsKey(pageIndex))
                                                      const Center(
                                                        child: Text(
                                                          'Sfondo PDF non disponibile',
                                                          style: TextStyle(
                                                            color: Colors.red,
                                                          ),
                                                        ),
                                                      ),
                                                    if (!ctrl
                                                            .pdfImportPending &&
                                                        ctrl
                                                                .file!
                                                                .pages![pageIndex]
                                                                .background
                                                            is XppBackgroundPdf)
                                                      PdfZoomDetail(
                                                        key: ValueKey((
                                                          ctrl.file!.documentId,
                                                          ctrl.pdfDetailIdentity(
                                                            pageIndex,
                                                          ),
                                                          pageIndex,
                                                        )),
                                                        controller: ctrl,
                                                        pageIndex: pageIndex,
                                                        transform:
                                                            _zoomController,
                                                        viewportKey:
                                                            _pdfViewportKey,
                                                      ),
                                                    // 2. LA TELA REALE PER L'INCHIOSTRO (Sopra)
                                                    XppPageStack(
                                                      renderPdfBackground:
                                                          false,
                                                      key: ctrl
                                                          .pageStackKeys[pageIndex],
                                                      page: ctrl
                                                          .file!
                                                          .pages![pageIndex],
                                                    ),
                                                    Positioned.fill(
                                                      child: AudioTimelineOverlay(
                                                        page: ctrl
                                                            .file!
                                                            .pages![pageIndex],
                                                        audio: ctrl.audio,
                                                      ),
                                                    ),
                                                    if (ctrl
                                                        .hasMissingBackground(
                                                          pageIndex,
                                                        ))
                                                      Center(
                                                        child: FilledButton.icon(
                                                          onPressed: () => ctrl
                                                              .associateBackground(
                                                                context,
                                                                pageIndex,
                                                              ),
                                                          icon: const Icon(
                                                            Icons.attach_file,
                                                          ),
                                                          label: const Text(
                                                            'Seleziona allegato di sfondo',
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if ((appearance?.showPageScrollbar ?? true) &&
                      ctrl.file?.pages?.firstOrNull?.infinite != true)
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width =
                              _pageDisplayWidth ??
                              max(1.0, constraints.maxWidth - 32);
                          return Align(
                            alignment: Alignment.centerRight,
                            child: IgnorePointer(
                              ignoring: resizing,
                              child: PageScrollbar(
                                transform: _zoomController,
                                viewport: constraints.biggest,
                                sceneHeight:
                                    24 +
                                    (ctrl.file?.pages ?? []).fold<double>(
                                      0,
                                      (height, page) =>
                                          height +
                                          width / page.pageSize!.ratio +
                                          24,
                                    ),
                                currentPage: ctrl.activePageIndex,
                                pageCount: ctrl.file?.pages?.length ?? 0,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  // Pannello Pomodoro a comparsa (resta attivo anche se nascosto)
                  if (AppFeatures.plugins &&
                      widget.showInternalToolbar &&
                      pomodoroEnabled)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Offstage(
                        offstage: !_showPomodoro,
                        child: PomodoroTimer(
                          progress: _pomodoroProgress,
                          onClose: () => setState(() => _showPomodoro = false),
                          onPhaseComplete: (finished, next) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  finished == PomodoroPhase.work
                                      ? "Sessione finita! Tempo di pausa."
                                      : "Pausa finita! Si torna a lavorare.",
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openShapeSettings(BuildContext context, CanvasController ctrl) {
    final renderBox =
        _shapeBtn.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    double leftPosition = max(
      16,
      min(
        renderBox.localToGlobal(Offset.zero).dx -
            160 +
            (renderBox.size.width / 2),
        MediaQuery.of(context).size.width - 336,
      ),
    );

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Stack(
        children: [
          Positioned(
            top:
                renderBox.localToGlobal(Offset.zero).dy +
                renderBox.size.height +
                8,
            left: leftPosition,
            child: ClipPath(
              clipper: const ShapeBorderClipper(
                shape: AppAppearance.panelShape,
              ),
              child: Material(
                color: AppAppearance.panel,
                shape: AppAppearance.panelShape,
                elevation: 0,
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.all(16),
                  child: StatefulBuilder(
                    builder: (context, setDialogState) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Strumento Forma:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        _shapeItem(
                          context,
                          'Linea',
                          Icons.horizontal_rule,
                          EditingTool.SHAPE_LINE,
                          ctrl,
                          setDialogState,
                        ),
                        _shapeItem(
                          context,
                          'Linea tratteggiata',
                          Icons.more_horiz,
                          EditingTool.SHAPE_DASHED_LINE,
                          ctrl,
                          setDialogState,
                        ),
                        _shapeItem(
                          context,
                          'Rettangolo',
                          Icons.rectangle_outlined,
                          EditingTool.SHAPE_RECT,
                          ctrl,
                          setDialogState,
                        ),
                        _shapeItem(
                          context,
                          'Cerchio',
                          Icons.circle_outlined,
                          EditingTool.SHAPE_CIRCLE,
                          ctrl,
                          setDialogState,
                        ),
                        _shapeItem(
                          context,
                          'Quadrato',
                          Icons.check_box_outline_blank,
                          EditingTool.SHAPE_SQUARE,
                          ctrl,
                          setDialogState,
                        ),
                        _shapeItem(
                          context,
                          'Cubo',
                          Icons.view_in_ar,
                          EditingTool.SHAPE_CUBE,
                          ctrl,
                          setDialogState,
                        ),
                        _shapeItem(
                          context,
                          'Cilindro',
                          Icons.album,
                          EditingTool.SHAPE_CYLINDER,
                          ctrl,
                          setDialogState,
                        ),
                        _shapeItem(
                          context,
                          'Sfera',
                          Icons.lens,
                          EditingTool.SHAPE_SPHERE,
                          ctrl,
                          setDialogState,
                        ),
                        const Divider(),
                        const Text(
                          'Proprietà figure:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              [
                                    Colors.black,
                                    Colors.grey,
                                    Colors.red,
                                    Colors.blue,
                                    Colors.green,
                                  ]
                                  .map(
                                    (c) => InkWell(
                                      onTap: () {
                                        ctrl.setShapeProps(c, null);
                                        setDialogState(() {});
                                      },
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: c,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: ctrl.shapeColor == c
                                                ? Colors.black
                                                : Colors.black12,
                                            width: ctrl.shapeColor == c ? 3 : 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                        Slider(
                          value: ctrl.shapeWidth,
                          min: 0.5,
                          max: 20.0,
                          onChanged: (val) {
                            ctrl.setShapeProps(null, val);
                            setDialogState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shapeItem(
    BuildContext context,
    String title,
    IconData icon,
    EditingTool tool,
    CanvasController ctrl,
    StateSetter setState,
  ) {
    final isSelected = ctrl.toolData[PointerDeviceKind.stylus] == tool;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
      ),
      onTap: () {
        ctrl.setTool(tool);
        _zoomableKey.currentState?.setState(
          () => _zoomableKey.currentState!.enabled = ctrl.isPanEnabled,
        );
        setState(() {});
      },
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  void _openEraserSettings(BuildContext context, CanvasController ctrl) {
    final renderBox =
        _eraserBtn.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    double leftPosition = max(
      16,
      min(
        renderBox.localToGlobal(Offset.zero).dx -
            160 +
            (renderBox.size.width / 2),
        MediaQuery.of(context).size.width - 336,
      ),
    );

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Stack(
        children: [
          Positioned(
            top:
                renderBox.localToGlobal(Offset.zero).dy +
                renderBox.size.height +
                8,
            left: leftPosition,
            child: ClipPath(
              clipper: const ShapeBorderClipper(
                shape: AppAppearance.panelShape,
              ),
              child: Material(
                color: AppAppearance.panel,
                shape: AppAppearance.panelShape,
                elevation: 0,
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.all(16),
                  child: StatefulBuilder(
                    builder: (context, setDialogState) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Modalità Gomma:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        RadioListTile<EraserMode>(
                          title: const Text('Pixel per Pixel'),
                          value: EraserMode.pixel,
                          groupValue: ctrl.eraserMode,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) {
                            if (val != null) {
                              ctrl.setEraserProps(val, null);
                              setDialogState(() {});
                            }
                          },
                        ),
                        RadioListTile<EraserMode>(
                          title: const Text('Intero Tratto'),
                          value: EraserMode.stroke,
                          groupValue: ctrl.eraserMode,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) {
                            if (val != null) {
                              ctrl.setEraserProps(val, null);
                              setDialogState(() {});
                            }
                          },
                        ),
                        const Divider(),
                        Text(
                          'Grandezza Gomma: ${(ctrl.eraserWidth * 0.3528).toStringAsFixed(2)} mm',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Slider(
                          value: ctrl.eraserWidth,
                          min: 2.0,
                          max: 40.0,
                          onChanged: (val) {
                            ctrl.setEraserProps(null, val);
                            setDialogState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSettingsMenu(
    BuildContext context,
    CanvasController ctrl,
    GlobalKey key,
    String title,
    List<Color> colors,
    Color curC,
    double curW,
    Function(Color?, double?) onUpdate,
  ) {
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    double leftPosition = max(
      16,
      min(
        renderBox.localToGlobal(Offset.zero).dx -
            160 +
            (renderBox.size.width / 2),
        MediaQuery.of(context).size.width - 336,
      ),
    );

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Stack(
        children: [
          Positioned(
            top:
                renderBox.localToGlobal(Offset.zero).dy +
                renderBox.size.height +
                8,
            left: leftPosition,
            child: ClipPath(
              clipper: const ShapeBorderClipper(
                shape: AppAppearance.panelShape,
              ),
              child: Material(
                color: AppAppearance.panel,
                shape: AppAppearance.panelShape,
                elevation: 0,
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.all(16),
                  child: StatefulBuilder(
                    builder: (context, setDialogState) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: colors
                              .map(
                                (c) => InkWell(
                                  onTap: () {
                                    onUpdate(c, null);
                                    setDialogState(() => curC = c);
                                  },
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: curC == c
                                            ? Colors.black
                                            : Colors.black12,
                                        width: curC == c ? 3 : 1,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Spessore: ${(curW * 0.3528).toStringAsFixed(2)} mm',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Slider(
                          value: curW,
                          min: title == 'Penna' ? 0.1 : 0.5,
                          max: 30.0,
                          onChanged: (val) {
                            onUpdate(null, val);
                            setDialogState(() => curW = val);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
