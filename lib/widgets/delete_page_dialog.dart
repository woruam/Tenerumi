import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';

Future<void> requestDeleteCurrentPage(
  BuildContext context,
  CanvasController controller,
) async {
  if (!controller.canDeletePage) return;
  final page = controller.file!.pages![controller.activePageIndex];
  if (controller.pageHasAnnotations(controller.activePageIndex)) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la pagina?'),
        content: const Text(
          'Questa pagina contiene modifiche. Eliminandola perderai anche le annotazioni, le immagini e il testo presenti.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-page'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
  }
  // The document may have changed while the confirmation was open.
  final index = controller.file?.pages?.indexOf(page) ?? -1;
  if (index >= 0) controller.deletePage(index);
}
