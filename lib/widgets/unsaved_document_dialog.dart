import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';

/// Shared by standalone canvases and the workspace, including unmounted tabs.
Future<bool> confirmDocumentClose(
    BuildContext context, CanvasController controller) async {
  if (!controller.hasUnsavedChanges) return true;
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Modifiche non salvate'),
      content: Text(
          'Salvare "${controller.file?.title ?? 'Documento'}" prima di chiudere?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Annulla')),
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('Chiudi senza salvare')),
        ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Salva')),
      ],
    ),
  );
  if (choice == 'discard') return true;
  if (choice != 'save' || !context.mounted) return false;
  return await controller.saveFile(context) && !controller.hasUnsavedChanges;
}
