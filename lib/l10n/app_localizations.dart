import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/src/app_brand.dart';
import 'package:xournalpp/src/editing_tool.dart';

class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  bool get isItalian => locale.languageCode == 'it';

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('it'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final localized =
        Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (localized != null) return localized;
    try {
      final theme = Provider.of<ThemeController>(context, listen: false);
      return AppLocalizations(theme.locale);
    } catch (_) {
      return _fallback;
    }
  }

  static const AppLocalizations _fallback = AppLocalizations(Locale('en'));

  // --- Common Actions ---
  String get cancel => isItalian ? 'Annulla' : 'Cancel';
  String get apply => isItalian ? 'Applica' : 'Apply';
  String get save => isItalian ? 'Salva' : 'Save';
  String get delete => isItalian ? 'Elimina' : 'Delete';
  String get close => isItalian ? 'Chiudi' : 'Close';
  String get create => isItalian ? 'Crea' : 'Create';
  String get ok => isItalian ? 'OK' : 'OK';
  String get understood => isItalian ? 'Ho capito' : 'Got it';
  String get open => isItalian ? 'Apri' : 'Open';
  String get openFile => isItalian ? 'Apri file' : 'Open file';
  String get loadingFile =>
      isItalian ? 'Caricamento file...' : 'Loading file...';
  String get noFileSelected =>
      isItalian ? 'Nessun file selezionato' : 'No file selected';
  String get youDidNotSelectAnyFile => isItalian
      ? 'Non è stato selezionato alcun file'
      : 'You did not select any file';

  // --- Home / Library ---
  String get appName => AppBrand.name;
  String get newNote => isItalian ? 'Nuovo Appunto' : 'New Note';
  String get noDocumentsHere =>
      isItalian ? 'Nessun documento qui' : 'No documents here';
  String get tapPlusToStart => isItalian
      ? 'Tocca + per iniziare una nuova nota'
      : 'Tap + to start a new note';
  String get changeTag => isItalian ? 'Cambia tag' : 'Change tag';
  String get createTag => isItalian ? 'Crea tag' : 'Create tag';
  String get deleteNoteConfirmTitle =>
      isItalian ? 'Eliminare l’appunto?' : 'Delete note?';
  String deleteNoteConfirmMessage(String name) => isItalian
      ? '“$name” verrà eliminato insieme ai suoi contenuti e alle registrazioni audio. Questa operazione non può essere annullata.'
      : '“$name” will be deleted along with its contents and audio recordings. This action cannot be undone.';
  String get noteDeleted => isItalian ? 'Appunto eliminato' : 'Note deleted';
  String get deleteNoteFailed => isItalian
      ? 'Impossibile completare l’eliminazione dell’appunto'
      : 'Failed to delete note';
  String get updateTagFailed =>
      isItalian ? 'Impossibile aggiornare il tag' : 'Failed to update tag';
  String fileOpenFailed(Object err) => isItalian
      ? 'Impossibile aprire il file: $err'
      : 'Failed to open file: $err';
  String get fileReadError => isItalian
      ? 'Errore nella lettura del file.'
      : 'Error reading file.';
  String get physicalFileNotFound => isItalian
      ? 'Impossibile trovare il file fisico!'
      : 'Physical file not found!';
  String get untitledDocument => isItalian ? 'Senza Titolo' : 'Untitled';
  String get documentTitleLabel =>
      isItalian ? 'Titolo del documento' : 'Document title';
  String get documentTitleHint =>
      isItalian ? 'Es. Lezione di Matematica' : 'e.g. Math Lecture';
  String get createSheet => isItalian ? 'Crea Foglio' : 'Create Note';
  String get infiniteCanvas => isItalian ? 'Canvas infinito' : 'Infinite canvas';
  String get infiniteCanvasSubtitle => isItalian
      ? 'Scrivi e spostati liberamente in tutte le direzioni'
      : 'Write and move freely in all directions';
  String get pageModelHeader =>
      isItalian ? 'MODELLO PAGINA' : 'PAGE TEMPLATE';
  String get pluginsTooltip => 'Plugin';
  String get defaultTagAll => isItalian ? 'Tutti' : 'All';
  String get defaultTagNotes => isItalian ? 'Appunti' : 'Notes';
  String get defaultTagSchool => isItalian ? 'Scuola' : 'School';
  String get defaultTagWork => isItalian ? 'Lavoro' : 'Work';

  // --- Audio Recovery ---
  String audioToRecoverTitle(int count) => isItalian
      ? 'Audio da recuperare: $count appunti'
      : 'Audio to recover: $count notes';
  String get audioToRecoverSubtitle => isItalian
      ? 'I segmenti finalizzati sono conservati; le registrazioni incomplete vengono segnalate.'
      : 'Finalized segments are saved; incomplete recordings are flagged.';
  String get recoverAudio => isItalian ? 'Recupera audio' : 'Recover audio';
  String get recoveredAudioTitle =>
      isItalian ? 'Audio recuperato' : 'Recovered audio';
  String get restoreAutoCopySubtitle =>
      isItalian ? 'Ripristina copia automatica' : 'Restore automatic copy';
  String recoveryFailed(Object err) =>
      isItalian ? 'Recupero fallito: $err' : 'Recovery failed: $err';
  String get deleteRecoveryCopy =>
      isItalian ? 'Elimina copia di recupero' : 'Delete recovery copy';
  String get deleteRecoveryCopyConfirm => isItalian
      ? 'Questa copia automatica verrà eliminata.'
      : 'This automatic copy will be deleted.';

  // --- Settings ---
  String get settings => isItalian ? 'Impostazioni' : 'Settings';

  // Language section
  String get languageSectionTitle => isItalian ? 'Lingua' : 'Language';
  String get languageSectionSubtitle =>
      isItalian ? 'Italiano o Inglese' : 'Italian or English';
  String get languageEnglish => 'English';
  String get languageItalian => 'Italiano';

  // Appearance section
  String get appearance => isItalian ? 'Aspetto' : 'Appearance';
  String get appearanceSubtitle => isItalian
      ? 'Colori, sfondo e stile delle icone'
      : 'Colors, background, and icon style';
  String get dynamicColors =>
      isItalian ? 'Colori dinamici (Material You)' : 'Dynamic colors (Material You)';
  String get dynamicColorsSubtitle => isItalian
      ? 'Segue lo sfondo del telefono'
      : 'Follows phone wallpaper';
  String get pureBlack => isItalian ? 'Nero puro (OLED)' : 'Pure black (OLED)';
  String get pureBlackSubtitle => isItalian
      ? 'Sfondi completamente neri'
      : 'Completely black backgrounds';
  String get customColor =>
      isItalian ? 'Colore personalizzato' : 'Custom color';
  String get iconStyle => isItalian ? 'Stile delle icone' : 'Icon style';
  String get iconStyleLine => isItalian ? 'Linea' : 'Line';
  String get iconStyleRounded => isItalian ? 'Tonde' : 'Rounded';
  String get iconStyleSharp => isItalian ? 'Nette' : 'Sharp';

  // Pen and gestures section
  String get penAndGestures => isItalian ? 'Penna e gesti' : 'Pen and gestures';
  String get penAndGesturesSubtitle => isItalian
      ? 'Menù circolare, tasti e disegno con le dita'
      : 'Radial menu, buttons, and finger drawing';
  String get stylusRadialMenu =>
      isItalian ? 'Menù circolare della penna' : 'Stylus radial menu';
  String get stylusRadialMenuSubtitle => isItalian
      ? 'Tempo di apertura e cinque scorciatoie personalizzabili'
      : 'Hold delay and five customizable shortcuts';
  String get drawWithFingers =>
      isItalian ? 'Disegna con le dita' : 'Draw with fingers';
  String get drawWithFingersSubtitle => isItalian
      ? 'Un dito disegna; due dita spostano e ingrandiscono. Disattiva per ignorare il palmo.'
      : 'One finger draws; two fingers pan and zoom. Turn off to ignore palm.';
  String get stylusButtons => isItalian ? 'Tasti della penna' : 'Stylus buttons';
  String get stylusProfileAuto => isItalian
      ? 'Automatica (1 o 2 tasti)'
      : 'Automatic (1 or 2 buttons)';
  String get stylusProfileSingle => isItalian
      ? 'Un tasto (S Pen e simili)'
      : 'Single button (S Pen and similar)';
  String get stylusProfileTwo => isItalian
      ? 'Due tasti (Redmi Pen e simili)'
      : 'Two buttons (Redmi Pen and similar)';
  String get stylusSideButton =>
      isItalian ? 'Tasto laterale' : 'Side button';
  String get stylusButton1 => isItalian
      ? 'Tasto 1 (principale / vicino alla punta)'
      : 'Button 1 (primary / near tip)';
  String get stylusButton2 => isItalian
      ? 'Tasto 2 (secondario / superiore)'
      : 'Button 2 (secondary / upper)';
  String get actionEraser => isItalian ? 'Gomma' : 'Eraser';
  String get actionLasso => isItalian ? 'Lazo' : 'Lasso';
  String get actionHighlighter =>
      isItalian ? 'Evidenziatore' : 'Highlighter';
  String get stylusSingleTip => isItalian
      ? 'Tieni premuto il tasto prima di toccare il foglio per usare '
          'l’azione nel tratto. Rilascialo per tornare allo strumento scelto '
          'dal tratto successivo. Le funzioni a distanza e Air Actions non sono incluse.'
      : 'Hold the button before touching the canvas to use the action '
          'for that stroke. Release to return to your chosen tool on the next stroke. '
          'Air Actions and hover gestures are not supported.';
  String get stylusTwoTip => isItalian
      ? 'Suggerimento: tieni premuto il tasto mentre scrivi per usare '
          'l\'azione solo in quel tratto, oppure premilo mentre la penna '
          'e\' sollevata (in hover) per attivare/disattivare l\'azione. '
          'Il secondo tasto viene usato solo se la penna lo possiede.'
      : 'Tip: hold the button while drawing to use the action only for that '
          'stroke, or press while hovering to toggle the action. '
          'The second button is only used if your stylus has one.';

  // Pages and navigation section
  String get pagesAndNavigation =>
      isItalian ? 'Pagine e navigazione' : 'Pages and navigation';
  String get pagesAndNavigationSubtitle => isItalian
      ? 'Scorrimento e contorno del foglio'
      : 'Scrollbar and page outline';
  String get pageScrollbar =>
      isItalian ? 'Barra di scorrimento pagine' : 'Page scrollbar';
  String get pageScrollbarSubtitle => isItalian
      ? 'Trascina la barra laterale per scorrere velocemente la nota.'
      : 'Drag the side scrollbar to navigate through notes quickly.';
  String get currentPageBorderColor => isItalian
      ? 'Colore contorno pagina corrente'
      : 'Current page border color';

  // Backup and restore section
  String get backupAndRestore =>
      isItalian ? 'Backup e ripristino' : 'Backup and restore';
  String get backupAndRestoreSubtitle =>
      isItalian ? 'Esporta o importa gli appunti' : 'Export or import notes';
  String get createBackup => isItalian ? 'Crea Backup' : 'Create Backup';
  String get createBackupSubtitle => isItalian
      ? 'Esporta gli appunti per un altro dispositivo'
      : 'Export notes for another device';
  String get restoreBackup =>
      isItalian ? 'Ripristina Backup' : 'Restore Backup';
  String get restoreBackupSubtitle => isItalian
      ? 'Carica gli appunti da un backup Tenerumi o OSI'
      : 'Load notes from a Tenerumi or OSI backup';
  String get chooseBackup => isItalian ? 'Scegli backup' : 'Choose backup';
  String get prepareBackup => isItalian ? 'Prepara backup' : 'Prepare backup';

  // About section
  String get about => isItalian ? 'Informazioni' : 'About';
  String get aboutSubtitle => isItalian
      ? 'Versione, licenze e progetto'
      : 'Version, licenses, and project';
  String get aboutTenerumi =>
      isItalian ? 'Informazioni su Tenerumi' : 'About Tenerumi';
  String get appInfoTitle => isItalian ? 'Info App' : 'App info';
  String versionLabel(String v) =>
      isItalian ? 'Versione $v' : 'Version $v';
  String buildLabel(String b) => isItalian ? 'Build $b' : 'Build $b';
  String get devVersion =>
      isItalian ? 'Versione in sviluppo' : 'Development version';
  String get appDescription => isItalian
      ? 'Appunti digitali, disegno e annotazioni PDF. Organizza i documenti con tag e personalizza i tuoi strumenti di studio.'
      : 'Digital notes, drawing, and PDF annotations. Organize documents with tags and customize your study tools.';
  String get appAttribution => isItalian
      ? 'Basata su Xournal++ Mobile. Compatibile con documenti .xopp. Licenza EUPL-1.2.'
      : 'Based on Xournal++ Mobile. Compatible with .xopp files. EUPL-1.2 license.';
  String get licenses => isItalian ? 'Licenze' : 'Licenses';

  // Toolbar & Canvas
  String get saveAsXopp =>
      isItalian ? 'Salva come XOPP' : 'Save as XOPP';
  String get exportPdf => isItalian ? 'Esporta PDF' : 'Export PDF';
  String get deleteCurrentPage =>
      isItalian ? 'Elimina pagina corrente' : 'Delete current page';
  String get deletePageConfirmTitle =>
      isItalian ? 'Eliminare la pagina?' : 'Delete page?';
  String get deletePageConfirmMessage => isItalian
      ? 'Questa pagina contiene modifiche. Eliminandola perderai anche le annotazioni, le immagini e il testo presenti.'
      : 'This page contains changes. Deleting it will also discard any annotations, images, and text.';
  String get unsavedChanges =>
      isItalian ? 'Modifiche non salvate' : 'Unsaved changes';
  String saveBeforeClosing(String title) => isItalian
      ? 'Salvare "$title" prima di chiudere?'
      : 'Save "$title" before closing?';
  String get closeWithoutSaving =>
      isItalian ? 'Chiudi senza salvare' : 'Close without saving';
  String get addPage => isItalian ? 'Aggiungi pagina' : 'Add page';
  String get addPageTooltip => isItalian
      ? 'Aggiungi pagina · tieni premuto per scegliere'
      : 'Add page · hold to choose';
  String get pageModel => isItalian ? 'Modello pagina' : 'Page template';
  String get paperFormat => isItalian ? 'Formato' : 'Format';
  String get landscape => isItalian ? 'Orizzontale' : 'Landscape';
  String get before => isItalian ? 'Prima' : 'Before';
  String get after => isItalian ? 'Dopo' : 'After';
  String get add => isItalian ? 'Aggiungi' : 'Add';
  String get layers => isItalian ? 'Livelli' : 'Layers';
  String get pages => isItalian ? 'Pagine' : 'Pages';
  String get pen => isItalian ? 'Penna' : 'Pen';
  String get highlighter => isItalian ? 'Evidenziatore' : 'Highlighter';
  String get eraser => isItalian ? 'Gomma' : 'Eraser';
  String get selection => isItalian ? 'Selezione' : 'Selection';
  String get move => isItalian ? 'Sposta' : 'Move';
  String get shapes => isItalian ? 'Figure' : 'Shapes';
  String get undo => isItalian ? 'Annulla' : 'Undo';
  String get redo => isItalian ? 'Ripeti' : 'Redo';
  String get documentSettings =>
      isItalian ? 'Impostazioni documento' : 'Document settings';

  // Layers panel
  String layersForPage(int page) =>
      isItalian ? 'Livelli · pagina $page' : 'Layers · page $page';
  String get layersDescription => isItalian
      ? 'Il livello in cima copre quelli sottostanti.'
      : 'The top layer covers those below it.';
  String get addLayer => isItalian ? 'Aggiungi livello' : 'Add layer';
  String get hideLayer => isItalian ? 'Nascondi' : 'Hide';
  String get showLayer => isItalian ? 'Mostra' : 'Show';
  String get lockLayer => isItalian ? 'Blocca' : 'Lock';
  String get unlockLayer => isItalian ? 'Sblocca' : 'Unlock';
  String get locked => isItalian ? 'Bloccato' : 'Locked';
  String layerElementsCount(int count) => isItalian
      ? '$count elementi'
      : '$count elements';
  String get deleteLayer =>
      isItalian ? 'Elimina livello' : 'Delete layer';
  String deleteLayerConfirm(String name) => isItalian
      ? 'Eliminare “$name” e tutti i suoi elementi?'
      : 'Delete “$name” and all its elements?';
  String get layerName => isItalian ? 'Nome livello' : 'Layer name';

  // Shapes & Ink
  String strokeThickness(double mm) => isItalian
      ? 'Spessore: ${mm.toStringAsFixed(2)} mm'
      : 'Thickness: ${mm.toStringAsFixed(2)} mm';

  // Tool label translation
  String toolLabel(EditingTool tool) => switch (tool) {
        EditingTool.STYLUS => isItalian ? 'Penna' : 'Pen',
        EditingTool.HIGHLIGHT => isItalian ? 'Evidenziatore' : 'Highlighter',
        EditingTool.ERASER => isItalian ? 'Gomma' : 'Eraser',
        EditingTool.SELECT => isItalian ? 'Selezione' : 'Selection',
        EditingTool.MOVE => isItalian ? 'Sposta' : 'Move',
        EditingTool.SHAPE_LINE => isItalian ? 'Linea' : 'Line',
        EditingTool.SHAPE_DASHED_LINE =>
          isItalian ? 'Linea tratteggiata' : 'Dashed line',
        EditingTool.SHAPE_RECT => isItalian ? 'Rettangolo' : 'Rectangle',
        EditingTool.SHAPE_CIRCLE => isItalian ? 'Cerchio' : 'Circle',
        EditingTool.SHAPE_SQUARE => isItalian ? 'Quadrato' : 'Square',
        EditingTool.SHAPE_CUBE => isItalian ? 'Cubo' : 'Cube',
        EditingTool.SHAPE_CYLINDER => isItalian ? 'Cilindro' : 'Cylinder',
        EditingTool.SHAPE_SPHERE => isItalian ? 'Sfera' : 'Sphere',
        EditingTool.SHAPE_AXES =>
          isItalian ? 'Assi cartesiani' : 'Cartesian axes',
        _ => tool.name,
      };

  // Paper template translation
  String paperTemplateName(String id) => switch (id.toLowerCase()) {
        'bianco' || 'plain' => isItalian ? 'Bianco' : 'Plain',
        'righe' || 'lined' => isItalian ? 'Righe' : 'Lined',
        'righe con margine' || 'ruled' =>
          isItalian ? 'Righe con margine' : 'Ruled',
        'quadretti' || 'graph' => isItalian ? 'Quadretti' : 'Grid',
        'puntini' || 'dotted' => isItalian ? 'Puntini' : 'Dotted',
        'carta di smith' || 'smith' =>
          isItalian ? 'Carta di Smith' : 'Smith Chart',
        'nothing dark' => 'Nothing Dark',
        'nothing light' => 'Nothing Light',
        _ => id,
      };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension LocalizedContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
