import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import 'XppBackground.dart';
import 'XppFile.dart';
import 'autosave_store.dart';
import 'compat/file_picker_cross.dart';
import 'note_tags.dart';
import 'recent_documents.dart';

class BackupNote {
  final XppFile file;
  final bool favorite;
  BackupNote(this.file, {this.favorite = false});
}

class PreparedBackup {
  final Uint8List bytes;
  final int count;
  final List<String> unavailable;
  PreparedBackup(this.bytes, this.count, this.unavailable);
}

class BackupContents {
  final List<BackupNote> notes;
  final List<String> tags;
  final DateTime? createdAt;
  BackupContents(this.notes, this.tags, this.createdAt);
}

/// Backups contain portable documents, never device-specific library paths.
class NoteBackup {
  static const maxBytes = 512 * 1024 * 1024;
  static const maxNotes = 10000;
  static bool _restoring = false;

  static Future<XppFile> _read(String path) async =>
      XppFile.fromFilePickerCross(
        await FilePickerCross.fromInternalPath(path: path),
        null,
        (_) async => throw StateError('Allegato mancante'),
      );

  static Future<PreparedBackup> create({
    ValueChanged<String>? onProgress,
  }) async {
    final entries = await RecentDocuments.list();
    final recoveries = await AutosaveStore.list();
    final usedRecoveries = <String>{};
    final notes = <BackupNote>[];
    final unavailable = <String>[];
    for (final entry in entries) {
      final title = entry['name'] as String? ?? 'Appunto';
      onProgress?.call('Preparazione: $title');
      final path = entry['path'] as String?;
      final recovery = recoveries
          .where(
            (r) =>
                (path != null && path.isNotEmpty && r['source'] == path) ||
                (entry['id'] != null &&
                    r['id'] == entry['id'] &&
                    (r['source'] == null || r['source'] == path)),
          )
          .firstOrNull;
      XppFile? saved, recovered;
      if (path != null && path.isNotEmpty) {
        try {
          saved = await _read(path);
          saved.sourcePath = path;
          saved.modifiedAt ??= await FilePickerCross.lastModified(path);
        } catch (_) {
          /* A current checkpoint can replace a missing original. */
        }
      }
      if (recovery != null) {
        try {
          recovered = await AutosaveStore.restore(recovery);
          if (recovery['time'] is int) {
            recovered.modifiedAt ??= DateTime.fromMillisecondsSinceEpoch(
              recovery['time'] as int,
              isUtc: true,
            );
          }
          usedRecoveries.add(recovery['id'] as String);
        } catch (_) {
          /* Fall back to the saved note and report lost recovery. */
          unavailable.add('$title: recupero automatico non accessibile');
        }
      }
      final file =
          recovered != null &&
              (saved == null ||
                  saved.modifiedAt == null ||
                  recovered.modifiedAt == null ||
                  !recovered.modifiedAt!.isBefore(saved.modifiedAt!))
          ? recovered
          : saved;
      if (file == null) {
        unavailable.add('$title: file non accessibile');
        continue;
      }
      file.title = title;
      file.tag = entry['tag'] as String? ?? file.tag;
      try {
        await _makePortable(file);
        notes.add(BackupNote(file, favorite: entry['favorite'] == true));
      } catch (_) {
        unavailable.add('$title: PDF o immagine di sfondo non accessibile');
      }
    }
    for (final recovery in recoveries) {
      if (usedRecoveries.contains(recovery['id'])) continue;
      final title = recovery['title'] as String? ?? 'Appunto recuperato';
      onProgress?.call('Preparazione: $title');
      try {
        final file = await AutosaveStore.restore(recovery);
        await _makePortable(file);
        notes.add(BackupNote(file));
      } catch (_) {
        unavailable.add('$title: recupero automatico non accessibile');
      }
    }
    if (notes.isEmpty) {
      throw StateError(
        unavailable.isEmpty
            ? 'Non ci sono appunti da salvare.'
            : 'Nessun appunto accessibile. ${unavailable.join('; ')}',
      );
    }
    final bytes = await encode(
      notes,
      tags: await NoteTags.load(),
      onProgress: onProgress,
    );
    return PreparedBackup(bytes, notes.length, unavailable);
  }

  static Future<void> _makePortable(XppFile file) async {
    for (final page in file.pages ?? []) {
      final bg = page.background;
      final name = switch (bg) {
        XppBackgroundPdf() => bg.filename,
        XppBackgroundImage() => bg.filename,
        _ => null,
      };
      if (bg is! XppBackgroundPdf && bg is! XppBackgroundImage) continue;
      if (name == null || name.isEmpty) throw StateError('Sfondo senza nome');
      if (file.pdfAttachments.containsKey(name)) continue;
      var source = name;
      final path = file.sourcePath?.replaceAll('\\', '/');
      if (!name.startsWith('/') &&
          !name.contains(':') &&
          path?.contains('/') == true) {
        source = '${path!.substring(0, path.lastIndexOf('/') + 1)}$name';
      }
      file.pdfAttachments[name] = (await FilePickerCross.fromInternalPath(
        path: source,
      )).toUint8List();
    }
  }

  static Future<Uint8List> encode(
    List<BackupNote> notes, {
    List<String> tags = const [],
    ValueChanged<String>? onProgress,
  }) async {
    if (notes.isEmpty || notes.length > maxNotes) {
      throw StateError('Il backup richiede da 1 a $maxNotes appunti.');
    }
    final payload = <Uint8List>[];
    final records = <Map<String, dynamic>>[];
    var total = 0;
    for (final (i, note) in notes.indexed) {
      onProgress?.call('Preparazione appunto ${i + 1} di ${notes.length}');
      final bytes = await note.file.toUint8ListAsync();
      total += bytes.length;
      if (total > maxBytes) throw StateError('Il backup supera 512 MB.');
      payload.add(bytes);
      records.add({
        'file': 'notes/$i.xopp',
        'title': note.file.title ?? 'Appunto',
        'tag': note.file.tag ?? 'Appunti',
        'favorite': note.favorite,
      });
    }
    return compute(_encode, {
      'manifest': {
        'format': 'osipp.notes-backup',
        'version': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'tags': tags,
        'notes': records,
      },
      'payload': payload,
    });
  }

  static Uint8List _encode(Map<String, dynamic> input) {
    final archive = Archive();
    final manifest = utf8.encode(jsonEncode(input['manifest']));
    archive.add(ArchiveFile('manifest.json', manifest.length, manifest));
    final payload = input['payload'] as List<Uint8List>;
    if (manifest.length > 8 * 1024 * 1024 ||
        manifest.length + payload.fold<int>(0, (total, b) => total + b.length) >
            maxBytes) {
      throw StateError('Il backup supera 512 MB.');
    }
    for (var i = 0; i < payload.length; i++) {
      archive.add(
        ArchiveFile.noCompress('notes/$i.xopp', payload[i].length, payload[i]),
      );
    }
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  static Map<String, dynamic> _decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes + 1024 * 1024) {
      throw const FormatException('Dimensione del backup non valida.');
    }
    final decoder = ZipDecoder();
    final archive = decoder.decodeBytes(bytes);
    if (decoder.directory.fileHeaders.length != archive.length ||
        archive.length > maxNotes + 1) {
      throw const FormatException(
        'Archivio con file duplicati o troppi appunti.',
      );
    }
    var total = 0;
    for (final entry in archive) {
      total += entry.size;
      if (!entry.isFile ||
          entry.isSymbolicLink ||
          total > maxBytes ||
          (entry.name != 'manifest.json' &&
              !RegExp(r'^notes/[0-9]+\.xopp$').hasMatch(entry.name))) {
        throw const FormatException('Contenuto del backup non valido.');
      }
    }
    Uint8List content(ArchiveFile file) {
      final data = file.readBytes();
      if (data == null ||
          data.length != file.size ||
          getCrc32(data) != file.crc32) {
        throw const FormatException(
          'Backup danneggiato: verifica del file fallita.',
        );
      }
      return data;
    }

    final manifestFile = archive.find('manifest.json');
    if (manifestFile == null || manifestFile.size > 8 * 1024 * 1024) {
      throw const FormatException('Manifest del backup mancante o non valido.');
    }
    final manifest = jsonDecode(utf8.decode(content(manifestFile)));
    if (manifest is! Map ||
        manifest['format'] != 'osipp.notes-backup' ||
        manifest['version'] != 1 ||
        manifest['notes'] is! List ||
        (manifest['notes'] as List).isEmpty ||
        (manifest['notes'] as List).length != archive.length - 1) {
      throw const FormatException(
        'Questo file non è un backup OSI supportato.',
      );
    }
    final names = <String>{};
    final payload = <Uint8List>[];
    for (final record in manifest['notes'] as List) {
      if (record is! Map ||
          record['file'] is! String ||
          record['title'] is! String ||
          record['tag'] is! String ||
          record['favorite'] is! bool ||
          !names.add(record['file'] as String) ||
          !RegExp(r'^notes/[0-9]+\.xopp$').hasMatch(record['file'] as String)) {
        throw const FormatException('Indice degli appunti non valido.');
      }
      final entry = archive.find(record['file'] as String);
      if (entry == null) {
        throw const FormatException('Un appunto è assente dal backup.');
      }
      payload.add(content(entry));
    }
    if (manifest['tags'] is! List ||
        (manifest['tags'] as List).any((t) => t is! String)) {
      throw const FormatException('Elenco dei tag non valido.');
    }
    return {
      'manifest': Map<String, dynamic>.from(manifest),
      'payload': payload,
    };
  }

  static Future<BackupContents> inspect(
    Uint8List bytes, {
    ValueChanged<String>? onProgress,
  }) async {
    final decoded = await compute(_decode, bytes);
    final manifest = decoded['manifest'] as Map;
    final records = manifest['notes'] as List;
    final notes = <BackupNote>[];
    for (final (i, data) in (decoded['payload'] as List<Uint8List>).indexed) {
      onProgress?.call('Verifica appunto ${i + 1} di ${records.length}');
      final file = await XppFile.fromFilePickerCross(
        FilePickerCross(data),
        null,
        (_) async => throw StateError('Il backup non contiene lo sfondo.'),
      );
      if (file.pages?.isNotEmpty != true) {
        throw const FormatException('Appunto senza pagine.');
      }
      for (final page in file.pages!) {
        final name = switch (page.background) {
          XppBackgroundPdf bg => bg.filename,
          XppBackgroundImage bg => bg.filename,
          _ => null,
        };
        if (name != null && !file.pdfAttachments.containsKey(name)) {
          throw const FormatException(
            'Il backup non contiene tutti gli allegati.',
          );
        }
      }
      file.title = records[i]['title'] as String;
      file.tag = records[i]['tag'] as String;
      notes.add(BackupNote(file, favorite: records[i]['favorite'] == true));
    }
    return BackupContents(
      notes,
      (manifest['tags'] as List).cast<String>(),
      DateTime.tryParse(manifest['createdAt'] as String? ?? ''),
    );
  }

  static Future<int> restore(
    BackupContents backup, {
    ValueChanged<String>? onProgress,
  }) async {
    if (_restoring) throw StateError('Un ripristino è già in corso.');
    if (backup.notes.isEmpty || backup.notes.length > maxNotes) {
      throw const FormatException('Numero di appunti non valido.');
    }
    _restoring = true;
    final written = <String>[];
    final restored = <BackupNote>[];
    try {
      for (final (i, note) in backup.notes.indexed) {
        onProgress?.call(
          'Ripristino appunto ${i + 1} di ${backup.notes.length}',
        );
        final source = note.file;
        final file = XppFile(
          title: source.title,
          tag: source.tag,
          modifiedAt: source.modifiedAt,
          autoGeneratePages: source.autoGeneratePages,
          previewImage: source.previewImage,
          pages: source.snapshot().pages,
          pdfAttachments: Map.of(source.pdfAttachments),
          recordings: Map.of(source.recordings),
          flashcards: Map.of(source.flashcards),
        );
        var destination = 'backup-${file.documentId}.xopp';
        while (await FilePickerCross.exists(destination)) {
          destination =
              'backup-${file.documentId}-${Random.secure().nextInt(1 << 32)}.xopp';
        }
        final data = FilePickerCross(await file.toUint8ListAsync());
        file.sourcePath = await data.saveToPath(path: destination);
        written.add(file.sourcePath!);
        restored.add(BackupNote(file, favorite: note.favorite));
      }
      await RecentDocuments.addRestored([
        for (final n in restored) (file: n.file, favorite: n.favorite),
      ], backup.tags);
      return restored.length;
    } catch (_) {
      for (final path in written) {
        try {
          await FilePickerCross.delete(path: path);
        } catch (_) {}
      }
      rethrow;
    } finally {
      _restoring = false;
    }
  }
}
