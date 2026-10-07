import 'note_audio_panel.dart';

import 'package:xournalpp/src/app_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'dart:ui';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/controllers/theme_controller.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';
import 'package:xournalpp/plugins/plugin_manager_page.dart';

import 'layers_panel.dart';

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
  final VoidCallback? onOpenFile;
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
    this.onOpenFile,
    this.openingFile = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CanvasController>();
    final stylusTool = ctrl.toolData[PointerDeviceKind.stylus];
    // Set di icone scelto dall'utente nelle impostazioni (outlined/rounded/sharp).
    final AppIcons icons = context.watch<ThemeController>().icons;
    final plugins = context.watch<PluginController?>();

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
              ? () => showLayersPanel(context, ctrl)
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
        if (plugins != null)
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
            } else if (action == 'open') {
              onOpenFile?.call();
            }
          },
          itemBuilder: (_) => [
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

            AnimatedScale(
              scale: stylusTool == EditingTool.STYLUS ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: IconButton(
                key: penKey,
                icon: Icon(icons.pen),
                tooltip: 'Penna',
                color: stylusTool == EditingTool.STYLUS
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white54,
                onPressed: () => stylusTool == EditingTool.STYLUS
                    ? onPenTap()
                    : onToolSelect(EditingTool.STYLUS),
              ),
            ),
            AnimatedScale(
              scale: stylusTool == EditingTool.HIGHLIGHT ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: IconButton(
                key: highlighterKey,
                icon: Icon(icons.highlighter),
                tooltip: 'Evidenziatore',
                color: stylusTool == EditingTool.HIGHLIGHT
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white54,
                onPressed: () => stylusTool == EditingTool.HIGHLIGHT
                    ? onHighlighterTap()
                    : onToolSelect(EditingTool.HIGHLIGHT),
              ),
            ),
            AnimatedScale(
              scale: ctrl.isShapeTool ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: IconButton(
                key: shapeKey,
                icon: Icon(icons.shapes),
                tooltip: 'Forme Geometriche',
                color: ctrl.isShapeTool
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white54,
                onPressed: onShapeTap,
              ),
            ),
            AnimatedScale(
              scale: stylusTool == EditingTool.ERASER ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: IconButton(
                key: eraserKey,
                icon: const FaIcon(FontAwesomeIcons.eraser),
                tooltip: 'Gomma',
                color: stylusTool == EditingTool.ERASER
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white54,
                onPressed: () => stylusTool == EditingTool.ERASER
                    ? onEraserTap()
                    : onToolSelect(EditingTool.ERASER),
              ),
            ),
            AnimatedScale(
              scale: stylusTool == EditingTool.SELECT ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: IconButton(
                icon: Icon(icons.lasso),
                tooltip: 'Lazo',
                color: stylusTool == EditingTool.SELECT
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white54,
                onPressed: () => onToolSelect(EditingTool.SELECT),
              ),
            ),
            AnimatedScale(
              scale: stylusTool == EditingTool.MOVE ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: IconButton(
                icon: Icon(icons.hand),
                tooltip: 'Mano (Modalità Sicura)',
                color: stylusTool == EditingTool.MOVE
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white54,
                onPressed: () => onToolSelect(EditingTool.MOVE),
              ),
            ),

            const SizedBox(height: 30, child: VerticalDivider(width: 20)),

            IconButton(
              icon: Icon(icons.addPage),
              tooltip: "Aggiungi Pagina",
              color: Theme.of(context).colorScheme.primary,
              onPressed: ctrl.file?.pages?.firstOrNull?.infinite == true
                  ? null
                  : ctrl.addPage,
            ),

            // --- IL TASTO PDF DIRETTAMENTE QUI, BEN VISIBILE ---
            IconButton(
              icon: Icon(icons.pdf),
              tooltip: 'Importa PDF',
              color: Theme.of(context)
                  .colorScheme
                  .primary, // Niente più rosso per forza, segue il tema Nothing
              onPressed: onImportPdf,
            ),

            IconButton(
              icon: Icon(icons.timer),
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
