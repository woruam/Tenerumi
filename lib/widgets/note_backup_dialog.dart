import 'package:flutter/material.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/note_backup.dart';
import 'package:xournalpp/src/app_features.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

Future<void> showNoteBackupDialog(
  BuildContext context, {
  required bool restore,
}) => !AppFeatures.manualBackup
    ? Future<void>.value()
    : showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _NoteBackupDialog(restore: restore),
      );

class _NoteBackupDialog extends StatefulWidget {
  final bool restore;
  const _NoteBackupDialog({required this.restore});
  @override
  State<_NoteBackupDialog> createState() => _NoteBackupDialogState();
}

class _NoteBackupDialogState extends State<_NoteBackupDialog> {
  bool busy = false;
  String progress = '', message = '';
  PreparedBackup? prepared;
  BackupContents? selected;
  BackupCancellation? cancellation;
  @override
  void dispose() {
    cancellation?.cancel();
    if (prepared != null) unawaited(prepared!.dispose());
    if (selected != null) unawaited(selected!.dispose());
    super.dispose();
  }

  String _problem(Object error) {
    if (error is FormatException) return error.message;
    if (error is StateError) return error.message;
    return 'Impossibile completare l’operazione. Controlla il file scelto, '
        'lo spazio disponibile e l’accesso ai documenti.';
  }

  void _progress(String value) {
    if (mounted) setState(() => progress = value);
  }

  Future<void> _prepare() async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      cancellation = BackupCancellation();
      if (widget.restore) {
        BackupContents backup;
        if (!kIsWeb) {
          final path = await FilePickerCross.importBackupToStaging();
          if (path == null) return;
          try {
            backup = await NoteBackup.inspectStaged(
              path,
              onProgress: _progress,
              cancellation: cancellation,
            );
          } finally {
            await FilePickerCross.discardStagedBackup(path);
          }
        } else {
          final file = await FilePickerCross.importFromStorage(
            type: FileTypeCross.custom,
            fileExtension: 'zip',
            maxBytes: NoteBackup.inMemoryBytes,
          );
          backup = await NoteBackup.inspect(
            file.toUint8List(),
            onProgress: _progress,
          );
        }
        if (mounted)
          setState(() => selected = backup);
        else
          await backup.dispose();
      } else {
        final backup = await NoteBackup.create(
          onProgress: _progress,
          staged: !kIsWeb,
          cancellation: cancellation,
        );
        if (mounted)
          setState(() => prepared = backup);
        else
          await backup.dispose();
      }
    } catch (error) {
      if (mounted && error != 'No file selected.') {
        setState(() => message = _problem(error));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _finish() async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      cancellation = BackupCancellation();
      if (widget.restore) {
        final count = await NoteBackup.restore(
          selected!,
          onProgress: _progress,
          cancellation: cancellation,
        );
        await selected!.dispose();
        if (mounted) {
          setState(() {
            selected = null;
            message = '$count appunti ripristinati nella libreria.';
          });
        }
      } else {
        final date = DateTime.now();
        final day =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final path = prepared!.stagedPath != null
            ? await FilePickerCross.exportStagedFile(
                prepared!.stagedPath!,
                'OSI-backup-$day.zip',
              )
            : await FilePickerCross(
                prepared!.bytes,
                path: 'OSI-backup-$day.zip',
              ).exportToStorage();
        if (path != null) await prepared!.dispose();
        if (mounted && path != null) {
          setState(() {
            message =
                'Backup di ${prepared!.count} appunti esportato. '
                'Trasferisci il file ZIP al nuovo dispositivo e usa Ripristina Backup.';
            prepared = null;
          });
        }
      }
    } catch (error) {
      if (mounted) setState(() => message = _problem(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.restore ? 'Ripristina Backup' : 'Crea Backup'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.restore
                    ? 'Scegli un backup ZIP creato da OSI. Gli appunti saranno aggiunti '
                          'come nuove copie, con tag, preferiti e allegati. Gli appunti esistenti vengono conservati.'
                    : 'Crea un file ZIP con gli appunti della libreria e i recuperi automatici. '
                          'Sono inclusi PDF, immagini, registrazioni audio e flashcard.',
              ),
              if (busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(progress),
              ],
              if (prepared != null) ...[
                const SizedBox(height: 16),
                Text('${prepared!.count} appunti pronti per il backup.'),
                if (prepared!.unavailable.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Backup parziale: ${prepared!.unavailable.length} problemi rilevati.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  for (final issue in prepared!.unavailable) Text('• $issue'),
                ],
              ],
              if (selected != null) ...[
                const SizedBox(height: 16),
                Text('${selected!.notes.length} appunti nel backup.'),
                if (selected!.createdAt != null)
                  Text(
                    'Creato il ${selected!.createdAt!.toLocal().day}/'
                    '${selected!.createdAt!.toLocal().month}/${selected!.createdAt!.toLocal().year}',
                  ),
                const SizedBox(height: 8),
                for (final note in selected!.notes.take(8))
                  Text('• ${note.title}'),
                if (selected!.notes.length > 8)
                  Text('… e altri ${selected!.notes.length - 8} appunti'),
              ],
              if (message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(message),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (busy)
          TextButton(
            onPressed: () => cancellation?.cancel(),
            child: const Text('Annulla operazione'),
          ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
        if (selected != null || prepared != null)
          FilledButton(
            onPressed: busy ? null : _finish,
            child: Text(
              widget.restore
                  ? 'Ripristina appunti'
                  : prepared!.unavailable.isEmpty
                  ? 'Esporta backup'
                  : 'Esporta backup parziale',
            ),
          )
        else
          FilledButton(
            onPressed: busy ? null : _prepare,
            child: Text(widget.restore ? 'Scegli backup' : 'Prepara backup'),
          ),
      ],
    ),
  );
}
