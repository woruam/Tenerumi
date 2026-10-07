import 'package:flutter/material.dart';
import 'package:xournalpp/src/note_tags.dart';

class NoteTagPicker extends StatelessWidget {
  const NoteTagPicker({
    super.key,
    required this.tags,
    required this.value,
    required this.onChanged,
    required this.onCreate,
  });
  final List<String> tags;
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        key: ValueKey('note-tag-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Tag'),
        items: tags
            .map(
              (tag) => DropdownMenuItem(
                value: tag,
                child: Text(tag, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (tag) {
          if (tag != null) onChanged(tag);
        },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('Crea tag'),
        ),
      ),
    ],
  );
}

Future<String?> showCreateNoteTagDialog(BuildContext context) async {
  final controller = TextEditingController();
  String? error;
  var saving = false;
  final result = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Crea tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(
            labelText: 'Nome del tag',
            hintText: 'Es. Università',
            errorText: error,
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    update(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      final tag = await NoteTags.create(controller.text);
                      if (context.mounted) Navigator.pop(context, tag);
                    } catch (failure) {
                      if (context.mounted) {
                        update(() {
                          saving = false;
                          error = failure is FormatException
                              ? failure.message
                              : 'Impossibile salvare il tag';
                        });
                      }
                    }
                  },
            child: const Text('Crea'),
          ),
        ],
      ),
    ),
  );
  // The closing route still uses the controller during its exit transition.
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  return result;
}
