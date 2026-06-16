import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

// Assicurati che questo percorso punti a dove hai salvato canvas_controller.dart
import 'package:xournalpp/controllers/canvas_controller.dart'; 

class CanvasToolbar extends StatelessWidget implements PreferredSizeWidget {
  final GlobalKey penKey;
  final GlobalKey highlighterKey;
  final GlobalKey eraserKey;
  final VoidCallback onPenTap;
  final VoidCallback onHighlighterTap;
  final VoidCallback onEraserTap;

  const CanvasToolbar({
    Key? key,
    required this.penKey,
    required this.highlighterKey,
    required this.eraserKey,
    required this.onPenTap,
    required this.onHighlighterTap,
    required this.onEraserTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // La magia di Provider: si abbona al Controller!
    final ctrl = context.watch<CanvasController>();
    final stylusTool = ctrl.toolData[PointerDeviceKind.stylus];

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      elevation: 1,
      shadowColor: Colors.black12,
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.undo), tooltip: 'Annulla',
              color: ctrl.undoStack.isNotEmpty ? Theme.of(context).colorScheme.onSurface : Colors.grey,
              onPressed: ctrl.undoStack.isNotEmpty ? ctrl.undo : null,
            ), 
            IconButton(
              icon: const Icon(Icons.redo), tooltip: 'Ripristina',
              color: ctrl.redoStack.isNotEmpty ? Theme.of(context).colorScheme.onSurface : Colors.grey,
              onPressed: ctrl.redoStack.isNotEmpty ? ctrl.redo : null,
            ),
            const SizedBox(height: 30, child: VerticalDivider(width: 20)),
            
            IconButton(
              key: penKey, icon: const Icon(Icons.edit), tooltip: 'Penna',
              color: stylusTool == EditingTool.STYLUS ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => stylusTool == EditingTool.STYLUS ? onPenTap() : ctrl.setTool(EditingTool.STYLUS),
            ),
            IconButton(
              key: highlighterKey, icon: const Icon(Icons.highlight), tooltip: 'Evidenziatore',
              color: stylusTool == EditingTool.HIGHLIGHT ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => stylusTool == EditingTool.HIGHLIGHT ? onHighlighterTap() : ctrl.setTool(EditingTool.HIGHLIGHT),
            ),
            IconButton(
              key: eraserKey, icon: const FaIcon(FontAwesomeIcons.eraser), tooltip: 'Gomma',
              color: stylusTool == EditingTool.ERASER ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => stylusTool == EditingTool.ERASER ? onEraserTap() : ctrl.setTool(EditingTool.ERASER),
            ),
            IconButton(
              icon: const Icon(Icons.all_out), tooltip: 'Lazo',
              color: stylusTool == EditingTool.SELECT ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => ctrl.setTool(EditingTool.SELECT),
            ),
            IconButton(
              icon: const Icon(Icons.pan_tool_alt), tooltip: 'Mano (Modalità Sicura)',
              color: stylusTool == EditingTool.MOVE ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => ctrl.setTool(EditingTool.MOVE),
            ),
            
            const SizedBox(height: 30, child: VerticalDivider(width: 20)),

            IconButton(icon: const Icon(Icons.note_add), color: Theme.of(context).colorScheme.primary, onPressed: ctrl.addPage),
            const SizedBox(width: 16),
            if (ctrl.savingFile) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}