import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/paper_template.dart';

class AddPageButton extends StatelessWidget {
  final CanvasController controller;
  final IconData icon;
  const AddPageButton({
    super.key,
    required this.controller,
    this.icon = Icons.note_add_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final enabled =
        controller.file?.pages?.firstOrNull?.infinite != true &&
        controller.file?.pages?.isNotEmpty == true;
    return Tooltip(
      message: 'Aggiungi pagina · tieni premuto per scegliere',
      // The default tooltip long press competes with the page chooser.
      triggerMode: TooltipTriggerMode.manual,
      child: GestureDetector(
        onLongPress: enabled ? () => choosePage(context, controller) : null,
        child: IconButton(
          icon: Icon(icon),
          onPressed: enabled ? () => controller.insertPage(after: true) : null,
        ),
      ),
    );
  }
}

Future<void> choosePage(
  BuildContext context,
  CanvasController controller,
) async {
  final document = controller.file;
  if (document == null) return;
  final original = document.defaultPaper;
  var template = original.template;
  var format = 'Originale';
  var landscape = original.width > original.height;
  var after = true;
  final selected = await showDialog<PaperSettings>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        final dimensions = switch (format) {
          'A4' => (595.28, 841.89),
          'A5' => (419.53, 595.28),
          'Letter' => (612.0, 792.0),
          _ => (original.width, original.height),
        };
        final short = dimensions.$1 < dimensions.$2
            ? dimensions.$1
            : dimensions.$2;
        final long = dimensions.$1 > dimensions.$2
            ? dimensions.$1
            : dimensions.$2;
        final paper = PaperSettings(
          template: template,
          width: landscape ? long : short,
          height: landscape ? short : long,
          color: original.color,
        );
        return AlertDialog(
          title: const Text('Aggiungi pagina'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Modello pagina'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final choice in PaperTemplate.values)
                        ChoiceChip(
                          label: Text(choice.label),
                          selected: template == choice,
                          onSelected: (_) => update(() => template = choice),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: format,
                    decoration: const InputDecoration(labelText: 'Formato'),
                    items: [
                      for (final value in ['Originale', 'A4', 'A5', 'Letter'])
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (value) => update(() => format = value!),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Orizzontale'),
                    value: landscape,
                    onChanged: (value) => update(() => landscape = value),
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Prima')),
                      ButtonSegment(value: true, label: Text('Dopo')),
                    ],
                    selected: {after},
                    onSelectionChanged: (value) =>
                        update(() => after = value.single),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: SizedBox(
                      width: 100,
                      height: 100 * paper.height / paper.width,
                      child: FittedBox(
                        child: SizedBox(
                          width: paper.width,
                          height: paper.height,
                          child: paper.build().render(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, paper),
              child: const Text('Aggiungi'),
            ),
          ],
        );
      },
    ),
  );
  if (selected != null &&
      context.mounted &&
      identical(controller.file, document)) {
    controller.insertPage(after: after, paper: selected);
  }
}
