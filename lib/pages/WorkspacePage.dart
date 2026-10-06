import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/controllers/workspace_controller.dart';
import 'package:xournalpp/widgets/PomodoroTimer.dart';
import 'package:xournalpp/widgets/unified_toolbar.dart';
import 'package:xournalpp/widgets/split_screen_view.dart';
import 'package:xournalpp/widgets/unsaved_document_dialog.dart';

class WorkspacePage extends StatefulWidget {
  final XppFile? initialFile;
  final Future<XppFile?> Function()? documentOpener;

  WorkspacePage({this.initialFile, this.documentOpener});

  @override
  _WorkspacePageState createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late WorkspaceController _ws;
  bool _allowPop = false;
  bool _checkingClose = false;
  bool _openingFile = false;
  final Map<XppFile, TransformationController> _zoomControllers = {};

  // Chiavi per richiamare promptSaveIfUnsaved sullo stato di ogni CanvasPage.
  final Map<XppFile, GlobalKey<CanvasPageState>> canvasKeys = {};
  // PDF in attesa di import nelle schede appena create.
  final Map<XppFile, String> _pendingPdf = {};

  // ---------------- POMODORO GLOBALE ----------------
  // FIX: prima il pulsante Pomodoro della toolbar unificata era collegato a un
  // callback vuoto e il pannello viveva (invisibile) dentro le CanvasPage.
  // Ora il timer e' UNICO per tutta la workspace: sopravvive al cambio di
  // scheda e allo split-screen, e il pannello si puo' trascinare.
  bool _showPomodoro = false;
  Offset _pomodoroPos = const Offset(12, 12); // distanza da (destra, alto)

  @override
  void initState() {
    super.initState();
    _ws = WorkspaceController(initialFile: widget.initialFile);
  }

  GlobalKey<CanvasPageState> _keyFor(XppFile f) =>
      canvasKeys.putIfAbsent(f, () => GlobalKey<CanvasPageState>());

  void _addNewDocument() {
    final XppFile f = XppFile.empty()
      ..title = "Nuovo Documento ${_ws.documents.length + 1}";
    _ws.addDocument(f);
    _ws.setPrimary(_ws.documents.length - 1);
  }

  Future<void> _openFile() async {
    if (_openingFile || _checkingClose || _allowPop) return;
    setState(() => _openingFile = true);
    try {
      final file = widget.documentOpener != null
          ? await widget.documentOpener!()
          : await XppFile.open(
              (_) {},
              (_) => FilePickerCross.importFromStorage(
                  type: FileTypeCross.custom, fileExtension: 'pdf'));
      if (!mounted || file == null || _allowPop) return;
      _ws.addDocument(file);
      _ws.setPrimary(_ws.documents.indexOf(file));
    } catch (error) {
      // The compatibility picker reports cancellation as this sentinel.
      if (mounted && error != 'No file selected.') {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Impossibile aprire il file: $error')));
      }
    } finally {
      if (mounted) setState(() => _openingFile = false);
    }
  }

  // Apre un PDF in una scheda separata, senza toccare i documenti gia' aperti.
  void _openPdfInNewTab(String pdfPath, String title) {
    final XppFile f = XppFile.empty()..title = title;
    _pendingPdf[f] = pdfPath;
    _ws.addDocument(f);
    _ws.setPrimary(_ws.documents.length - 1);
  }

  Future<void> _closeDocument(int index) async {
    if (_checkingClose ||
        _allowPop ||
        index < 0 ||
        index >= _ws.documents.length) return;
    if (_ws.documents.length <= 1) {
      await _exitWorkspace();
      return;
    }
    _checkingClose = true;
    try {
      final XppFile f = _ws.documents[index];
      final bool canClose =
          await confirmDocumentClose(context, _ws.controllerFor(f));
      if (!canClose || !mounted) return;
      canvasKeys.remove(f);
      _zoomControllers.remove(f)?.dispose();
      _pendingPdf.remove(f);
      _ws.removeDocument(f);
    } finally {
      _checkingClose = false;
    }
  }

  Future<void> _exitWorkspace({bool checkDocuments = true}) async {
    if (_checkingClose || _allowPop) return;
    _checkingClose = true;
    try {
      final allowed = !checkDocuments ||
          await _ws.confirmCloseAll(
              (controller) => confirmDocumentClose(context, controller));
      if (!allowed || !mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } finally {
      _checkingClose = false;
    }
  }

  @override
  void dispose() {
    for (final zoom in _zoomControllers.values) {
      zoom.dispose();
    }
    _ws.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<WorkspaceController>.value(
      value: _ws,
      child: Consumer<WorkspaceController>(
        builder: (context, ws, _) {
          // Indice secondario valido solo se diverso dal primario (evita doppia GlobalKey).
          final int? secIdx = (ws.secondaryIndex != null &&
                  ws.secondaryIndex! != ws.primaryIndex &&
                  ws.secondaryIndex! >= 0 &&
                  ws.secondaryIndex! < ws.documents.length)
              ? ws.secondaryIndex
              : null;
          final bool canSplit =
              ws.splitEnabled && secIdx != null && ws.documents.length >= 2;

          return PopScope(
            canPop: _allowPop,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) _exitWorkspace();
            },
            child: Scaffold(
              backgroundColor: Theme.of(context).colorScheme.surface,
              // TOOLBAR UNICA GLOBALE: comanda sempre il pannello con focus.
              appBar: UnifiedToolbar(
                onPomodoroTap: () =>
                    setState(() => _showPomodoro = !_showPomodoro),
                pomodoroActive: _showPomodoro,
                onOpenPdfInNewTab: _openPdfInNewTab,
                onOpenFile: _openFile,
                openingFile: _openingFile,
              ),
              body: Stack(
                children: [
                  Column(
                    children: [
                      _buildTabRow(context, ws),
                      Expanded(
                        child: canSplit
                            ? SplitScreenView(
                                primaryWidget: _buildPanel(
                                    ws.primaryIndex, WorkspacePanel.primary),
                                secondaryWidget: _buildPanel(
                                    secIdx, WorkspacePanel.secondary),
                              )
                            : _buildPanel(
                                ws.primaryIndex, WorkspacePanel.primary),
                      ),
                    ],
                  ),
                  // ---- Pannello Pomodoro (globale, trascinabile, sempre vivo) ----
                  _buildPomodoroOverlay(context),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPomodoroOverlay(BuildContext context) {
    return Positioned(
      top: _pomodoroPos.dy,
      right: _pomodoroPos.dx,
      child: Offstage(
        offstage: !_showPomodoro,
        child: GestureDetector(
          // Trascina il pannello dove vuoi: cosi' non copre mai gli appunti.
          onPanUpdate: (details) {
            final Size screen = MediaQuery.of(context).size;
            setState(() {
              _pomodoroPos = Offset(
                (_pomodoroPos.dx - details.delta.dx)
                    .clamp(0.0, screen.width - 260),
                (_pomodoroPos.dy + details.delta.dy)
                    .clamp(0.0, screen.height - 220),
              );
            });
          },
          child: PomodoroTimer(
            onClose: () => setState(() => _showPomodoro = false),
            onPhaseComplete: (finished, next) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(finished == PomodoroPhase.work
                      ? "Sessione finita! Tempo di pausa."
                      : "Pausa finita! Si torna a lavorare.")));
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTabRow(BuildContext context, WorkspaceController ws) {
    final cs = Theme.of(context).colorScheme;
    final icons = context.watch<ThemeController>().icons;
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          IconButton(
            icon: Icon(icons.back),
            onPressed: _exitWorkspace,
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: ws.documents.length,
              itemBuilder: (context, index) {
                final bool active = index == ws.primaryIndex;
                return GestureDetector(
                  onTap: () => ws.setPrimary(index),
                  child: Container(
                    width: 150,
                    margin: const EdgeInsets.only(right: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: active
                          ? cs.surfaceContainerHighest.withOpacity(0.9)
                          : Colors.transparent,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            ws.documents[index].title ?? "Documento",
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              color: active
                                  ? cs.onSurface
                                  : Colors.grey.withOpacity(0.5),
                              fontWeight:
                                  active ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _closeDocument(index),
                          borderRadius: BorderRadius.circular(50),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(icons.close, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: Icon(ws.splitEnabled ? icons.splitActive : icons.split),
            color: ws.splitEnabled ? cs.primary : null,
            tooltip: "Dividi Schermo",
            onPressed: () => ws.toggleSplit(),
          ),
          IconButton(icon: Icon(icons.add), onPressed: _addNewDocument),
        ],
      ),
    );
  }

  Widget _buildPanel(int index, WorkspacePanel panel) {
    final XppFile file =
        _ws.documents[index.clamp(0, _ws.documents.length - 1)];
    // Il PDF in attesa va consumato UNA volta sola: se il pannello viene
    // ricostruito (es. attivando/disattivando lo split) non va re-importato.
    final String? pending = _pendingPdf.remove(file);
    return CanvasPage(
      key: _keyFor(file),
      file: file,
      zoomController:
          _zoomControllers.putIfAbsent(file, TransformationController.new),
      controller: _ws
          .controllerFor(file), // controller posseduto dal WorkspaceController
      showInternalToolbar: false, // la toolbar e' unica e globale
      onFocus: () =>
          _ws.focus(panel), // tocco -> questo pannello prende il focus
      pdfToImportPath: pending,
      onOpenPdfInNewTab: _openPdfInNewTab,
    );
  }
}
