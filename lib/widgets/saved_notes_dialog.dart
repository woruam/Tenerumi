import 'package:flutter/material.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/recent_documents.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';

Future<XppFile?> openSavedNote(BuildContext context) async {
  final entries = await RecentDocuments.list();
  if (!context.mounted) return null;
  final selected = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Apri appunto'),
      content: SizedBox(
        width: 400,
        height: 350,
        child: entries.isEmpty
            ? const Center(child: Text('Non ci sono appunti salvati.'))
            : ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final entry = entries[entries.length - 1 - i];
                  return ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(entry['name'] as String? ?? 'Appunto'),
                    subtitle: Text(entry['tag'] as String? ?? 'Appunti'),
                    onTap: () => Navigator.pop(context, entry),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, <String, dynamic>{'device': true}),
          child: const Text('Apri file dal dispositivo'),
        ),
      ],
    ),
  );
  if (selected == null) return null;
  if (selected['device'] == true)
    return XppFile.open(
      (_) {},
      (_) => FilePickerCross.importFromStorage(
        type: FileTypeCross.custom,
        fileExtension: 'pdf',
      ),
    );
  final path = selected['path'] as String;
  final picker = await FilePickerCross.fromInternalPath(path: path);
  final file = await XppFile.fromFilePickerCross(
    picker,
    null,
    (_) => FilePickerCross.importFromStorage(
      type: FileTypeCross.custom,
      fileExtension: 'pdf',
    ),
  );
  // Xournal parsing retains its source; PDF import needs a new .xopp save.
  if (selected['localId'] is String)
    file.localId = selected['localId'] as String;
  file.title = selected['name'] as String? ?? file.title;
  file.tag = selected['tag'] as String? ?? file.tag;
  return file;
}
