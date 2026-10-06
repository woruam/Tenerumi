import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/WorkspacePage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';

/// Drop area to open .xopp (or import .pdf) files by drag and drop.
/// Works on the web and on desktop (Windows, Linux, macOS).
class DropFile extends StatefulWidget {
  @override
  _DropFileState createState() => _DropFileState();
}

class _DropFileState extends State<DropFile> {
  bool _fileHover = false;
  bool _loading = false;

  Future<void> _openDropped(String name, dynamic xFile) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _fileHover = false;
      _loading = true;
    });
    final controller = messenger.showSnackBar(SnackBar(
      content: Text(S.of(context).openingFile + name + ' ...'),
      duration: const Duration(days: 999),
    ));
    try {
      final bytes = await xFile.readAsBytes();
      final picker = FilePickerCross(bytes,
          path: xFile.path as String? ?? name,
          type: FileTypeCross.custom,
          fileExtension: 'xopp');
      XppFile file;
      if (name.toLowerCase().endsWith('.pdf')) {
        file = await XppFile.importPdf(pdf: picker);
      } else {
        file = await XppFile.fromFilePickerCross(picker, (percentage) {},
            (_) async => throw Exception('File non trovato'));
      }
      controller.close();
      if (!mounted) return;
      setState(() => _loading = false);
      navigator.push(MaterialPageRoute(
          builder: (context) => WorkspacePage(initialFile: file)));
    } catch (e) {
      controller.close();
      if (!mounted) return;
      setState(() => _loading = false);
      showDialog(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(S.of(context).errorOpeningFile),
                content: SelectableText(
                    S.of(context).imVerySorryButICouldntReadTheFile +
                        name +
                        S.of(context).areYouSureIHaveThePermissionAndAreYou +
                        '\n${e.toString()}'),
                actions: [
                  TextButton(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: e.toString())),
                      child: Text(S.of(context).copyErrorMessage)),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(S.of(context).okay),
                  ),
                ],
              ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: DropTarget(
          onDragDone: (detail) {
            if (detail.files.isEmpty) return;
            final file = detail.files.first;
            _openDropped(file.name, file);
          },
          onDragEntered: (detail) => setState(() => _fileHover = true),
          onDragExited: (detail) => setState(() => _fileHover = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            constraints: const BoxConstraints(maxHeight: 128),
            decoration: BoxDecoration(
              color: _fileHover
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
              border: _fileHover
                  ? Border.all(color: colorScheme.primary, width: 2)
                  : Border.all(color: Colors.transparent, width: 2),
            ),
            child: Center(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.open_with,
                              color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(S.of(context).dropFilesToOpen,
                              style: TextStyle(
                                  color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
