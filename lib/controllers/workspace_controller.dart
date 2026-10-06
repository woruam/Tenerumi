import 'package:flutter/foundation.dart';

import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/XppFile.dart';

/// Quale dei due pannelli affiancati ha il focus.
enum WorkspacePanel { primary, secondary }

/// Stato "sollevato" della workspace.
///
/// Possiede i [CanvasController] di tutti i documenti aperti, la modalità split,
/// la posizione del divisore e il pannello con il focus. È la sorgente di verità
/// a cui guarda la TOOLBAR UNIFICATA: i comandi sono sempre instradati al
/// [CanvasController] del pannello ATTIVO (getter [active]).
///
/// In questo modo lo stato della toolbar è sollevato fuori dalle singole
/// [CanvasPage]: una sola toolbar globale, due controller con stato isolato.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({XppFile? initialFile}) {
    final XppFile first =
        initialFile ?? (XppFile.empty()..title = 'Nuovo Documento 1');
    _add(first);
  }

  /// Documenti aperti, nell'ordine delle schede.
  final List<XppFile> documents = [];

  /// Un controller per documento: stato di disegno isolato
  /// (strumento, colore, spessore, zoom, tratti, undo/redo).
  final Map<XppFile, CanvasController> _controllers = {};

  /// Modalità affiancata attiva/disattiva.
  bool splitEnabled = false;

  /// Larghezza relativa del pannello primario (0.2..0.8).
  double dividerRatio = 0.5;

  /// Indici (in [documents]) dei due pannelli affiancati.
  int primaryIndex = 0;
  int? secondaryIndex;

  /// Pannello che riceve i comandi della toolbar unica.
  WorkspacePanel activePanel = WorkspacePanel.primary;

  // ------------------------------------------------------------------ Controller

  void _add(XppFile file) {
    if (!documents.contains(file)) {
      documents.add(file);
      controllerFor(file); // istanzia subito il controller del documento
    }
  }

  /// Restituisce (creandolo se serve) il [CanvasController] di un documento.
  CanvasController controllerFor(XppFile file) =>
      _controllers.putIfAbsent(file, () => CanvasController()..init(file));

  /// Indice del documento mostrato nel pannello con focus.
  int get _activeIndex {
    if (!splitEnabled || activePanel == WorkspacePanel.primary)
      return primaryIndex;
    return secondaryIndex ?? primaryIndex;
  }

  /// Documento attualmente sotto focus.
  XppFile get activeFile {
    if (documents.isEmpty) {
      final XppFile f = XppFile.empty()..title = 'Nuovo Documento 1';
      _add(f);
    }
    final int i = _activeIndex.clamp(0, documents.length - 1).toInt();
    return documents[i];
  }

  /// Controller su cui la toolbar unica deve agire.
  CanvasController get active => controllerFor(activeFile);

  /// Checks every document, even those without a mounted CanvasPage.
  Future<bool> confirmCloseAll(
      Future<bool> Function(CanvasController) confirm) async {
    for (final file in List<XppFile>.of(documents)) {
      if (!await confirm(controllerFor(file))) return false;
    }
    return true;
  }

  // ------------------------------------------------------------------- Documenti

  void addDocument(XppFile file) {
    _add(file);
    notifyListeners();
  }

  void removeDocument(XppFile file) {
    final int idx = documents.indexOf(file);
    if (idx < 0) return;
    documents.removeAt(idx);
    _controllers.remove(file)?.dispose();

    if (idx < primaryIndex) primaryIndex--;
    if (secondaryIndex != null && idx < secondaryIndex!)
      secondaryIndex = secondaryIndex! - 1;
    if (secondaryIndex == primaryIndex) secondaryIndex = null;

    if (primaryIndex >= documents.length) {
      primaryIndex = documents.isEmpty ? 0 : documents.length - 1;
    }
    if (secondaryIndex != null && secondaryIndex! >= documents.length) {
      secondaryIndex = documents.length >= 2 ? documents.length - 1 : null;
    }
    if (documents.length < 2) {
      splitEnabled = false;
      activePanel = WorkspacePanel.primary;
    }
    notifyListeners();
  }

  // --------------------------------------------------------------- Split & focus

  void setPrimary(int index) {
    if (documents.isEmpty) return;
    primaryIndex = index.clamp(0, documents.length - 1).toInt();
    activePanel = WorkspacePanel.primary;
    notifyListeners();
  }

  void toggleSplit() {
    splitEnabled = !splitEnabled;
    if (splitEnabled) {
      if (documents.length < 2) {
        _add(
            XppFile.empty()..title = 'Nuovo Documento ${documents.length + 1}');
      }
      secondaryIndex ??= (primaryIndex == 0) ? 1 : 0;
      if (secondaryIndex == primaryIndex) {
        secondaryIndex = (primaryIndex + 1) % documents.length;
      }
    } else {
      activePanel = WorkspacePanel.primary;
    }
    notifyListeners();
  }

  /// Imposta il pannello con focus (chiamato al tocco/stilo su un pannello).
  void focus(WorkspacePanel panel) {
    if (activePanel == panel) return;
    activePanel = panel;
    notifyListeners(); // la toolbar unica si riallinea al nuovo pannello attivo
  }

  /// Aggiorna la posizione del divisore (0.2..0.8).
  void setDivider(double ratio) {
    final double r = ratio.clamp(0.2, 0.8).toDouble();
    if (r == dividerRatio) return;
    dividerRatio = r;
    notifyListeners();
  }

  // --------------------------------------------------------------------- Cleanup

  @override
  void dispose() {
    for (final CanvasController c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    super.dispose();
  }
}
