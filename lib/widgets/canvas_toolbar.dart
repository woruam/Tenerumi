import 'stylus_menu_settings.dart';
import 'delete_page_dialog.dart';
import 'note_audio_panel.dart';
import 'note_flashcards_panel.dart';

import 'package:xournalpp/src/app_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'dart:ui';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';
import 'package:xournalpp/src/app_features.dart';
import 'package:xournalpp/plugins/plugin_manager_page.dart';

import 'layers_panel.dart';
import 'add_page_button.dart';
import 'pomodoro_progress_icon.dart';

class CanvasToolbar extends StatelessWidget implements PreferredSizeWidget {
  final GlobalKey penKey;
  final GlobalKey highlighterKey;
  final GlobalKey shapeKey;
  final GlobalKey eraserKey;
  final VoidCallback onPenTap;
  final VoidCallback onHighlighterTap;
  final VoidCallback onShapeTap;
  final VoidCallback onEraserTap;
  final VoidCallback onImportPdf;
  final Function(EditingTool) onToolSelect;
  final VoidCallback onPomodoroTap;
  final bool pomodoroActive;
  final ValueNotifier<double>? pomodoroProgress;
  final VoidCallback? onOpenFile;
  final VoidCallback? onNavigationTap;
  final bool openingFile;

  const CanvasToolbar({
    Key? key,
    required this.penKey,
    required this.highlighterKey,
    required this.shapeKey,
    required this.eraserKey,
    required this.onPenTap,
    required this.onHighlighterTap,
    required this.onShapeTap,
    required this.onEraserTap,
    required this.onImportPdf,
    required this.onToolSelect,
    required this.onPomodoroTap,
    this.pomodoroActive = false,
    this.pomodoroProgress,
    this.onOpenFile,
    this.onNavigationTap,
    this.openingFile = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CanvasController>();
    final stylusTool = ctrl.toolData[PointerDeviceKind.stylus];
    // Set di icone scelto dall'utente nelle impostazioni (outlined/rounded/sharp).
    final AppIcons icons = context.watch<ThemeController>().icons;
    final plugins = AppFeatures.plugins
        ? context.watch<PluginController?>()
        : null;

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      elevation: 0,
      backgroundColor: Colors.transparent,
      actions: [
        IconButton(
          key: const ValueKey('layers-manager'),
          tooltip: 'Livelli',
          icon: const Icon(Icons.layers_outlined),
          onPressed: ctrl.file?.pages?.isNotEmpty == true && !ctrl.savingFile
              ? onNavigationTap ?? () => showLayersPanel(context, ctrl)
              : null,
        ),
        IconButton(
          tooltip: ctrl.autosaveError != null
              ? 'Autosalvataggio fallito: ${ctrl.autosaveError}'
              : ctrl.lastAutosave == null
              ? 'Autosalvataggio attivo'
              : 'Copia di recupero aggiornata alle ${ctrl.lastAutosave!.hour.toString().padLeft(2, '0')}:${ctrl.lastAutosave!.minute.toString().padLeft(2, '0')}',
          icon: Icon(
            ctrl.autosaveError != null
                ? Icons.error_outline
                : ctrl.autosaving
                ? Icons.sync
                : Icons.cloud_done_outlined,
          ),
          onPressed: () async {
            await ctrl.flushAutosave();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  ctrl.autosaveError != null
                      ? 'Autosalvataggio non riuscito: ${ctrl.autosaveError}'
                      : 'Autosalvataggio attivo. Le modifiche sono recuperabili dalla schermata iniziale.',
                ),
              ),
            );
          },
        ),
        if (AppFeatures.plugins && plugins != null)
          IconButton(
            key: const ValueKey('plugin-manager'),
            tooltip: 'Plugin',
            icon: const Icon(Icons.extension_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    PluginManagerPage(plugins: plugins, canvas: ctrl),
              ),
            ),
          ),
        PopupMenuButton<String>(
          key: const ValueKey('document-settings'),
          tooltip: 'Impostazioni documento',
          icon: Icon(icons.settings),
          onSelected: (action) {
            if (action == 'save') {
              ctrl.saveFile(context);
            } else if (action == 'save-xopp') {
              ctrl.exportToXopp(context);
            } else if (action == 'export-pdf') {
              ctrl.exportToPdf(context);
            } else if (action == 'delete-page') {
              requestDeleteCurrentPage(context, ctrl);
            } else if (action == 'open') {
              onOpenFile?.call();
            } else if (action == 'stylus-menu') {
              showStylusMenuSettings(context, context.read<ThemeController>());
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'stylus-menu',
              child: ListTile(
                leading: Icon(Icons.touch_app_outlined),
                title: Text('Menù circolare della penna'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'delete-page',
              enabled: ctrl.canDeletePage,
              child: const ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Elimina pagina corrente'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'save',
              enabled: !ctrl.savingFile,
              child: const ListTile(
                leading: Icon(Icons.save_outlined),
                title: Text('Salva'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'save-xopp',
              enabled: !ctrl.savingFile,
              child: const ListTile(
                leading: Icon(Icons.save_as_outlined),
                title: Text('Salva come XOPP'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'export-pdf',
              enabled: !ctrl.savingFile,
              child: const ListTile(
                leading: Icon(Icons.picture_as_pdf_outlined),
                title: Text('Esporta PDF'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'open',
              enabled: onOpenFile != null && !openingFile,
              child: const ListTile(
                leading: Icon(Icons.folder_open_outlined),
                title: Text('Apri file'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
      flexibleSpace: ClipRect(
        child: Container(
          decoration: BoxDecoration(
            color: AppAppearance.panel,
            border: Border(
              bottom: BorderSide(color: AppAppearance.border, width: 1),
            ),
          ),
        ),
      ),
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            NoteAudioButton(audio: ctrl.audio),
            IconButton(
              icon: Icon(icons.undo),
              tooltip: 'Annulla',
              color: ctrl.undoStack.isNotEmpty
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.grey,
              onPressed: ctrl.undoStack.isNotEmpty ? ctrl.undo : null,
            ),
            IconButton(
              icon: Icon(icons.redo),
              tooltip: 'Ripristina',
              color: ctrl.redoStack.isNotEmpty
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.grey,
              onPressed: ctrl.redoStack.isNotEmpty ? ctrl.redo : null,
            ),
            const SizedBox(height: 30, child: VerticalDivider(width: 20)),

            _ToolButton(
              buttonKey: penKey,
              name: 'Penna',
              selected: stylusTool == EditingTool.STYLUS,
              icon: Icon(icons.pen),
              swatch: ctrl.penColor,
              onPressed: () => stylusTool == EditingTool.STYLUS
                  ? onPenTap()
                  : onToolSelect(EditingTool.STYLUS),
            ),
            _ToolButton(
              buttonKey: highlighterKey,
              name: 'Evidenziatore',
              selected: stylusTool == EditingTool.HIGHLIGHT,
              icon: Icon(icons.highlighter),
              swatch: ctrl.highlighterColor,
              onPressed: () => stylusTool == EditingTool.HIGHLIGHT
                  ? onHighlighterTap()
                  : onToolSelect(EditingTool.HIGHLIGHT),
            ),
            _ToolButton(
              buttonKey: shapeKey,
              name: 'Forme Geometriche',
              selected: ctrl.isShapeTool,
              icon: Icon(icons.shapes),
              onPressed: onShapeTap,
            ),
            _ToolButton(
              buttonKey: eraserKey,
              name: 'Gomma',
              selected: stylusTool == EditingTool.ERASER,
              icon: const FaIcon(FontAwesomeIcons.eraser),
              onPressed: () => stylusTool == EditingTool.ERASER
                  ? onEraserTap()
                  : onToolSelect(EditingTool.ERASER),
            ),
            _ToolButton(
              name: 'Lazo',
              selected: stylusTool == EditingTool.SELECT,
              icon: Icon(icons.lasso),
              onPressed: () => onToolSelect(EditingTool.SELECT),
            ),
            _ToolButton(
              name: 'Mano (Modalità Sicura)',
              selected: stylusTool == EditingTool.MOVE,
              icon: Icon(icons.hand),
              onPressed: () => onToolSelect(EditingTool.MOVE),
            ),
            const SizedBox(height: 30, child: VerticalDivider(width: 20)),

            AddPageButton(controller: ctrl, icon: icons.addPage),

            // --- IL TASTO PDF DIRETTAMENTE QUI, BEN VISIBILE ---
            IconButton(
              icon: Icon(icons.pdf),
              tooltip: 'Importa PDF',
              color: Theme.of(context)
                  .colorScheme
                  .primary, // Niente più rosso per forza, segue il tema Nothing
              onPressed: onImportPdf,
            ),

            if (AppFeatures.plugins && plugins?.ankiEnabled == true) ...[
              _ToolButton(
                selected: stylusTool == EditingTool.FLASHCARD,
                name: ctrl.capturingFlashcard
                    ? 'Preparazione flashcard…'
                    : stylusTool == EditingTool.FLASHCARD
                    ? ctrl.flashcardFront == null
                          ? '1. Seleziona il titolo'
                          : '2. Seleziona la risposta'
                    : 'Flashcard: doppia selezione',
                icon: const Icon(Icons.crop_free),
                onPressed: ctrl.capturingFlashcard || ctrl.savingFile
                    ? null
                    : stylusTool == EditingTool.FLASHCARD
                    ? ctrl.cancelFlashcard
                    : ctrl.beginFlashcard,
              ),
              IconButton(
                tooltip: 'Flashcard dell’appunto',
                icon: const Icon(Icons.style_outlined),
                onPressed: () => showNoteFlashcards(context, ctrl),
              ),
              if (stylusTool == EditingTool.FLASHCARD)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Center(
                    child: Text(
                      ctrl.flashcardFront == null
                          ? '1 · Titolo'
                          : '2 · Risposta',
                    ),
                  ),
                ),
            ],
            if (AppFeatures.plugins && plugins?.pomodoroEnabled == true)
              IconButton(
                icon: PomodoroProgressIcon(progress: pomodoroProgress),
                tooltip: 'Pomodoro',
                color: pomodoroActive
                    ? Theme.of(context).colorScheme.primary
                    : null,
                onPressed: onPomodoroTap,
              ),
            const SizedBox(width: 16),
            if (ctrl.savingFile)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// Tool selection is independent of ink colour and exposed to accessibility.
class _ToolButton extends StatelessWidget {
  final Key? buttonKey;
  final String name;
  final bool selected;
  final Widget icon;
  final Color? swatch;
  final VoidCallback? onPressed;
  const _ToolButton({
    this.buttonKey,
    required this.name,
    required this.selected,
    required this.icon,
    this.swatch,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: IconButton(
        key: buttonKey,
        tooltip: name,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: colors.onSurface,
          backgroundColor: selected ? colors.surfaceContainerHighest : null,
          side: BorderSide(
            color: selected ? colors.onSurface : Colors.transparent,
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            icon,
            if (swatch != null)
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: swatch,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.onSurface),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
