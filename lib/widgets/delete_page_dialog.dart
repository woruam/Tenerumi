import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/l10n/app_localizations.dart';

Future<void> requestDeleteCurrentPage(
  BuildContext context,
  CanvasController controller,
) async {
  if (!controller.canDeletePage) return;
  final page = controller.file!.pages![controller.activePageIndex];
  if (controller.pageHasAnnotations(controller.activePageIndex)) {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePageConfirmTitle),
        content: Text(
          l10n.deletePageConfirmMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-page'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
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
