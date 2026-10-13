import 'dart:typed_data';

import 'package:xournalpp/plugins/plugin_controller.dart';

import 'dart:convert';
import 'dart:async';

import 'package:xournalpp/src/workspace_session.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/app_appearance.dart';
import 'package:xournalpp/widgets/document_navigator.dart';
import 'package:xournalpp/widgets/saved_notes_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/controllers/workspace_controller.dart';
import 'package:xournalpp/widgets/PomodoroTimer.dart';
import 'package:xournalpp/widgets/unified_toolbar.dart';
import 'package:xournalpp/widgets/split_screen_view.dart';
import 'package:xournalpp/widgets/unsaved_document_dialog.dart';

class WorkspacePage extends StatefulWidget {
  final XppFile? initialFile;
  final bool autosaveEnabled;
  final RestoredWorkspace? restored;
  final Future<XppFile?> Function()? documentOpener;

  WorkspacePage({
    this.initialFile,
    this.documentOpener,
    this.restored,
    this.autosaveEnabled = true,
  });

  @override
  _WorkspacePageState createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage>
    with WidgetsBindingObserver {
  Timer? _sessionTimer;
  final Set<CanvasController> _observed = {};
  bool _savingSession = false, _saveAgain = false, _checkpointPending = false;
  late WorkspaceController _ws;
  bool _allowPop = false;
  bool _checkingClose = false;
  bool _openingFile = false;
  final Map<XppFile, TransformationController> _zoomControllers = {};

  // Chiavi per richiamare promptSaveIfUnsaved sullo stato di ogni CanvasPage.
  final Map<XppFile, GlobalKey<CanvasPageState>> canvasKeys = {};
  // PDF in attesa di import nelle schede appena create.
  final Map<XppFile, (String, Uint8List)> _pendingPdf = {};

  // ---------------- POMODORO GLOBALE ----------------
  // FIX: prima il pulsante Pomodoro della toolbar unificata era collegato a un
  // callback vuoto e il pannello viveva (invisibile) dentro le CanvasPage.
  // Ora il timer e' UNICO per tutta la workspace: sopravvive al cambio di
  // scheda e allo split-screen, e il pannello si puo' trascinare.
  bool _showPomodoro = false;
  bool _showNavigator = false;
  Offset _pomodoroPos = const Offset(12, 12); // distanza da (destra, alto)

  @override
  void initState() {
    super.initState();
    final restored = widget.restored;
    _ws = WorkspaceController(
      autosaveEnabled: widget.autosaveEnabled,
      initialFile: restored?.files.firstOrNull ?? widget.initialFile,
    );
    if (restored != null) {
      for (final file in restored.files.skip(1)) {
        _ws.addDocument(file);
      }
      _ws.primaryIndex = (restored.state['primary'] as int? ?? 0).clamp(
        0,
        _ws.documents.length - 1,
      );
      _ws.secondaryIndex = restored.state['secondary'] as int?;
      _ws.splitEnabled =
          restored.state['split'] == true && _ws.secondaryIndex != null;
      _ws.dividerRatio = (restored.state['divider'] as num? ?? .5)
          .toDouble()
          .clamp(.2, .8);
      if (restored.state['focus'] == 'secondary' && _ws.splitEnabled)
        _ws.activePanel = WorkspacePanel.secondary;
      for (var i = 0; i < restored.files.length; i++) {
        final file = restored.files[i], tab = restored.tabs[i];
        final ctrl = _ws.controllerFor(file);
        ctrl.setActivePage((tab['page'] as int? ?? 0));
        final values = tab['zoom'];
        if (values is List &&
            values.length == 16 &&
            values.every((v) => v is num && v.isFinite)) {
          final matrix = Matrix4.fromList(
            values.map((v) => (v as num).toDouble()).toList(),
          );
          final scale = matrix.getMaxScaleOnAxis();
          if (scale >= .1 && scale <= 10 && matrix.entry(3, 3) == 1) {
            _zoomFor(file).value = matrix;
          }
        }
      }
    }
    WidgetsBinding.instance.addObserver(this);
    _ws.addListener(_workspaceChanged);
    _workspaceChanged();
  }

  TransformationController _zoomFor(XppFile file) =>
      _zoomControllers.putIfAbsent(
        file,
        () => TransformationController()..addListener(_scheduleSession),
      );
  void _workspaceChanged() {
    final current = _ws.documents.map(_ws.controllerFor).toSet();
    for (final ctrl in _observed.difference(current)) {
      ctrl.removeListener(_scheduleSession);
    }
    for (final ctrl in current.difference(_observed)) {
      ctrl.addListener(_scheduleSession);
    }
    _observed
      ..clear()
      ..addAll(current);
    _scheduleSession();
  }

  void _scheduleSession() {
    if (_allowPop) return;
    _sessionTimer?.cancel();
    _sessionTimer = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_persistSession()),
    );
  }

  String? _emptyTemplate(XppFile file) {
    if (file.sourcePath != null ||
        file.pdfAttachments.isNotEmpty ||
        file.recordings.isNotEmpty ||
        file.flashcards.isNotEmpty ||
        file.pages?.length != 1 ||
        file.pages!.any(
          (p) => p.layers!.any((l) => l.content?.isNotEmpty == true),
        ))
      return null;
    final bytes = file.toUint8List();
    return bytes != null && bytes.length < 32000 ? base64Encode(bytes) : null;
  }

  Future<void> _persistSession({bool checkpoint = false}) async {
    if (_allowPop) return;
    if (_savingSession) {
      _checkpointPending |= checkpoint;
      _saveAgain = true;
      return;
    }
    _savingSession = true;
    try {
      checkpoint |= _checkpointPending;
      _checkpointPending = false;
      if (!mounted || _allowPop) return;
      await WorkspaceSession.save({
        'primary': _ws.primaryIndex,
        'secondary': _ws.secondaryIndex,
        'split': _ws.splitEnabled,
        'divider': _ws.dividerRatio,
        'focus': _ws.activePanel.name,
        'tabs': [
          for (final f in _ws.documents)
            {
              'template': _emptyTemplate(f),
              'id': f.documentId,
              'key': f.recoveryKey,
              'localId': f.localId,
              'recoveryOnly': f.recovered,
              'path': f.sourcePath,
              'title': f.title,
              'tag': f.tag,
              'page': _ws.controllerFor(f).activePageIndex,
              'zoom': _zoomFor(f).value.storage.toList(),
              'blank':
                  f.sourcePath == null &&
                  f.pdfAttachments.isEmpty &&
                  f.recordings.isEmpty &&
                  f.pages?.length == 1 &&
                  f.pages!.every(
                    (p) => p.layers!.every((l) => l.content?.isEmpty != false),
                  ),
            },
        ],
      });
      if (checkpoint) {
        for (final file in List<XppFile>.of(_ws.documents)) {
          if (!mounted || _allowPop || !_ws.documents.contains(file)) break;
          final ctrl = _ws.controllerFor(file);
          await ctrl.audio.suspend();
          await ctrl.flushAutosave();
        }
      }
    } catch (error) {
      if (mounted && !_allowPop)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ripristino schede non disponibile: $error')),
        );
    } finally {
      _savingSession = false;
      if (_saveAgain && mounted && !_allowPop) {
        _saveAgain = false;
        unawaited(_persistSession(checkpoint: _checkpointPending));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _sessionTimer?.cancel();
      unawaited(_persistSession(checkpoint: true));
    }
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
          : await openSavedNote(context);
      if (!mounted || file == null || _allowPop) return;
      final existing = _ws.documents
          .where((f) => f.sourcePath != null && f.sourcePath == file.sourcePath)
          .firstOrNull;
      if (existing != null) {
        _ws.setPrimary(_ws.documents.indexOf(existing));
        return;
      }
      _ws.addDocument(file);
      _ws.setPrimary(_ws.documents.indexOf(file));
    } catch (error) {
      // The compatibility picker reports cancellation as this sentinel.
      if (mounted && error != 'No file selected.') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossibile aprire il file: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingFile = false);
    }
  }

  // Apre un PDF in una scheda separata, senza toccare i documenti gia' aperti.
  void _openPdfInNewTab(String pdfPath, String title, Uint8List pickedBytes) {
    final XppFile f = XppFile.empty(
      template: (size) => XppBackgroundSolidPlain(size: size),
    )..title = title;
    _pendingPdf[f] = (pdfPath, pickedBytes);
    _ws.addDocument(f);
    _ws.setPrimary(_ws.documents.length - 1);
  }

  Future<void> _closeDocument(int index) async {
    if (_checkingClose ||
        _allowPop ||
        index < 0 ||
        index >= _ws.documents.length)
      return;
    if (_ws.documents.length <= 1) {
      await _exitWorkspace();
      return;
    }
    _checkingClose = true;
    try {
      final XppFile f = _ws.documents[index];
      final bool canClose = await confirmDocumentClose(
        context,
        _ws.controllerFor(f),
      );
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
      final allowed =
          !checkDocuments ||
          await _ws.confirmCloseAll(
            (controller) => confirmDocumentClose(context, controller),
          );
      if (!allowed || !mounted) return;
      setState(() => _allowPop = true);
      _sessionTimer?.cancel();
      await WorkspaceSession.save(null);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } finally {
      _checkingClose = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    _ws.removeListener(_workspaceChanged);
    for (final ctrl in _observed) {
      ctrl.removeListener(_scheduleSession);
    }
    _observed.clear();
    for (final zoom in _zoomControllers.values) {
      zoom.dispose();
    }
    _ws.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pomodoroEnabled =
        context.watch<PluginController?>()?.pomodoroEnabled == true;
    if (!pomodoroEnabled) _showPomodoro = false;
    return ChangeNotifierProvider<WorkspaceController>.value(
      value: _ws,
      child: Consumer<WorkspaceController>(
        builder: (context, ws, _) {
          // Indice secondario valido solo se diverso dal primario (evita doppia GlobalKey).
          final int? secIdx =
              (ws.secondaryIndex != null &&
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
                onNavigationTap: () =>
                    setState(() => _showNavigator = !_showNavigator),
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
                                  ws.primaryIndex,
                                  WorkspacePanel.primary,
                                ),
                                secondaryWidget: _buildPanel(
                                  secIdx,
                                  WorkspacePanel.secondary,
                                ),
                              )
                            : _buildPanel(
                                ws.primaryIndex,
                                WorkspacePanel.primary,
                              ),
                      ),
                    ],
                  ),
                  if (_showNavigator)
                    Positioned(
                      top: 50,
                      bottom: 0,
                      right: 0,
                      width: MediaQuery.sizeOf(context).width < 380
                          ? MediaQuery.sizeOf(context).width * .85
                          : 320,
                      child: DocumentNavigator(
                        key: ObjectKey(ws.active),
                        controller: ws.active,
                        onClose: () => setState(() => _showNavigator = false),
                      ),
                    ),
                  // ---- Pannello Pomodoro (globale, trascinabile, sempre vivo) ----
                  if (pomodoroEnabled) _buildPomodoroOverlay(context),
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
                (_pomodoroPos.dx - details.delta.dx).clamp(
                  0.0,
                  screen.width - 260,
                ),
                (_pomodoroPos.dy + details.delta.dy).clamp(
                  0.0,
                  screen.height - 220,
                ),
              );
            });
          },
          child: PomodoroTimer(
            onClose: () => setState(() => _showPomodoro = false),
            onPhaseComplete: (finished, next) {
              if (!mounted) return;
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
    );
  }

  Widget _buildTabRow(BuildContext context, WorkspaceController ws) {
    final cs = Theme.of(context).colorScheme;
    final icons = context.watch<ThemeController>().icons;
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          IconButton(icon: Icon(icons.back), onPressed: _exitWorkspace),
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
                      color: active ? AppAppearance.raised : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: active ? cs.primary : AppAppearance.border,
                          width: active ? 2 : 1,
                        ),
                      ),
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
                                  : cs.onSurfaceVariant,
                              fontWeight: active
                                  ? FontWeight.bold
                                  : FontWeight.normal,
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
    final pending = _pendingPdf.remove(file);
    return CanvasPage(
      key: _keyFor(file),
      file: file,
      zoomController: _zoomFor(file),
      controller: _ws.controllerFor(
        file,
      ), // controller posseduto dal WorkspaceController
      showInternalToolbar: false, // la toolbar e' unica e globale
      onFocus: () =>
          _ws.focus(panel), // tocco -> questo pannello prende il focus
      pdfToImportPath: pending?.$1,
      pdfToImportBytes: pending?.$2,
      onOpenPdfInNewTab: _openPdfInNewTab,
    );
  }
}
