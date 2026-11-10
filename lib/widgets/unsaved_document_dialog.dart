import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/l10n/app_localizations.dart';

/// Shared by standalone canvases and the workspace, including unmounted tabs.
Future<bool> confirmDocumentClose(
  BuildContext context,
  CanvasController controller,
) async {
  await controller.audio.stop();
  if (!context.mounted) return false;
  if (!controller.hasUnsavedChanges) return true;
  final l10n = context.l10n;
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.unsavedChanges),
      content: Text(
        l10n.saveBeforeClosing(controller.file?.title ?? l10n.untitledDocument),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'cancel'),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'discard'),
          child: Text(l10n.closeWithoutSaving),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, 'save'),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
  if (choice == 'discard') {
    await controller.discardRecovery();
    return true;
  }
  if (choice != 'save' || !context.mounted) return false;
  return await controller.saveFile(context) && !controller.hasUnsavedChanges;
}
