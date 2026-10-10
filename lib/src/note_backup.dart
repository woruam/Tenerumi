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
import 'bounded_archive.dart';
import 'document_limits.dart';
import 'critical_data.dart';
import 'compat/backup_staging_stub.dart'
    if (dart.library.io) 'compat/backup_staging_io.dart'
    as staging;

class BackupNote {
  final XppFile? _file;
  final String? payloadPath;
  final String? _title, _tag;
  XppFile get file =>
      _file ?? (throw StateError('Caricare prima l’appunto dallo staging'));
  String? get title => _title ?? _file?.title;
  Future<XppFile> load() async {
    if (_file != null) return _file;
    final file = await XppFile.fromFilePickerCross(
      FilePickerCross(await staging.readStaged(payloadPath!)),
      null,
      (_) async => throw StateError('Sfondo mancante'),
      limits: NoteBackup.workingLimits,
    );
    file.title = _title;
    file.tag = _tag;
    return file;
  }

  final bool favorite;
  BackupNote(XppFile file, {this.favorite = false})
    : _file = file,
      payloadPath = null,
      _title = null,
      _tag = null;
  BackupNote.staged(
    this.payloadPath,
    this._title,
    this._tag, {
    this.favorite = false,
  }) : _file = null;
}

class BackupCancellation {
  bool cancelled = false;
  void cancel() => cancelled = true;
  void check() {
    if (cancelled) throw StateError('Operazione annullata');
  }
}

class PreparedBackup {
  final Uint8List? _bytes;
  Uint8List get bytes =>
      _bytes ?? (throw StateError('Esportare il backup dallo staging'));
  final String? stagedPath, stagingRoot;
  final int count;
  final List<String> unavailable;
  PreparedBackup(Uint8List bytes, this.count, this.unavailable)
    : _bytes = bytes,
      stagedPath = null,
      stagingRoot = null;
  PreparedBackup.staged(
    this.stagedPath,
    this.stagingRoot,
    this.count,
    this.unavailable,
  ) : _bytes = null;
  Future<void> dispose() async {
    if (stagingRoot != null) await staging.disposeStaging(stagingRoot!);
  }
}

class BackupContents {
  final List<BackupNote> notes;
  final List<String> tags;
  final DateTime? createdAt;
  final String? stagingRoot;
  BackupContents(this.notes, this.tags, this.createdAt, {this.stagingRoot});
  Future<void> dispose() async {
    if (stagingRoot != null) await staging.disposeStaging(stagingRoot!);
  }
}

/// Backups contain portable documents, never device-specific library paths.
class NoteBackup {
  static const maxBytes = 512 * 1024 * 1024;
  static const maxNotes = 10000;
  static const inMemoryBytes = 32 * 1024 * 1024;
  static const workingLimits = DocumentLimits(
    compressedBytes: inMemoryBytes,
    xmlBytes: 64 * 1024 * 1024,
    mediaBytes: 32 * 1024 * 1024,
  );
  static bool _restoring = false;

  static Future<XppFile> _read(
    String path, {
    int remaining = 64 * 1024 * 1024,
  }) async => XppFile.fromFilePickerCross(
    await FilePickerCross.fromInternalPath(path: path, maxBytes: inMemoryBytes),
    null,
    (_) async => throw StateError('Allegato mancante'),
    limits: DocumentLimits(
      compressedBytes: inMemoryBytes,
      xmlBytes: remaining,
      mediaBytes: min(32 * 1024 * 1024, remaining),
    ),
  );

  static Future<PreparedBackup> create({
    ValueChanged<String>? onProgress,
    bool staged = false,
    BackupCancellation? cancellation,
  }) async {
    if (staged && staging.supportsDiskStaging)
      return _createStaged(onProgress, cancellation);
    final entries = await RecentDocuments.list();
    final recoveries = await AutosaveStore.list();
    final usedRecoveries = <String>{};
    final notes = <BackupNote>[];
    final unavailable = <String>[];
    var remaining = 64 * 1024 * 1024;
    void reserve(XppFile f) {
      final xml = f.importedXmlBytes > 0
          ? f.importedXmlBytes
          : utf8.encode(f.toXmlString()).length;
      final media = f.importedMediaBytes;
      remaining -= xml + media;
      if (remaining < 0)
        throw StateError(
          'Backup oltre il budget del browser: usare lo staging su dispositivo',
        );
    }

    for (final entry in entries) {
      cancellation?.check();
      final title = entry['name'] as String? ?? 'Appunto';
      onProgress?.call('Preparazione: $title');
      final path = entry['path'] as String?;
      final recovery = recoveries
          .where(
            (r) =>
                (path != null && path.isNotEmpty && r['source'] == path) ||
                (entry['key'] != null && r['key'] == entry['key']),
          )
          .firstOrNull;
      XppFile? saved, recovered;
      if (path != null && path.isNotEmpty) {
        try {
          saved = await _read(path, remaining: remaining);
          reserve(saved);
          saved.sourcePath = path;
          saved.modifiedAt ??= await FilePickerCross.lastModified(path);
        } catch (_) {
          /* A current checkpoint can replace a missing original. */
        }
      }
      if (recovery != null) {
        try {
          final recoveredBytes = await AutosaveStore.readBytes(recovery);
          recovered = await XppFile.fromFilePickerCross(
            FilePickerCross(recoveredBytes),
            null,
            (_) async => throw StateError('Sfondo mancante'),
            limits: DocumentLimits(
              compressedBytes: inMemoryBytes,
              xmlBytes: remaining,
              mediaBytes: min(32 * 1024 * 1024, remaining),
            ),
          );
          reserve(recovered);
          if (recovery['time'] is int) {
            recovered.modifiedAt ??= DateTime.fromMillisecondsSinceEpoch(
              recovery['time'] as int,
              isUtc: true,
            );
          }
          usedRecoveries.add(recovery['key'] as String);
        } catch (_) {
          /* Fall back to the saved note and report lost recovery. */
          unavailable.add('$title: recupero automatico non accessibile');
        }
      }
      // Preserve both candidates unless their serialized content is identical.
      if (saved != null && recovered != null) {
        if (!listEquals(
          await saved.serializeSnapshotAsync(),
          await recovered.serializeSnapshotAsync(),
        )) {
          recovered.title = '$title (recupero)';
          await _makePortable(recovered);
          notes.add(BackupNote(recovered));
        }
      }
      final file = saved ?? recovered;
      if (file == null) {
        unavailable.add('$title: file non accessibile');
        continue;
      }
      file.title = title;
      file.tag = entry['tag'] as String? ?? file.tag;
      try {
        await _makePortable(file);
        if (file.importWarnings.any((e) => !e.startsWith('Recupero locale:')))
          throw StateError('Appunto importato parzialmente');
        notes.add(BackupNote(file, favorite: entry['favorite'] == true));
      } catch (_) {
        unavailable.add('$title: PDF o immagine di sfondo non accessibile');
      }
    }
    for (final recovery in recoveries) {
      cancellation?.check();
      if (usedRecoveries.contains(recovery['key'])) continue;
      final title = recovery['title'] as String? ?? 'Appunto recuperato';
      onProgress?.call('Preparazione: $title');
      try {
        final bytes = await AutosaveStore.readBytes(recovery);
        final file = await XppFile.fromFilePickerCross(
          FilePickerCross(bytes),
          null,
          (_) async => throw StateError('Sfondo mancante'),
          limits: DocumentLimits(
            compressedBytes: inMemoryBytes,
            xmlBytes: remaining,
            mediaBytes: min(32 * 1024 * 1024, remaining),
          ),
        );
        reserve(file);
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
    final expanded = notes.fold<int>(
      0,
      (total, n) => total + n.file.importedXmlBytes + n.file.importedMediaBytes,
    );
    if (expanded > 64 * 1024 * 1024)
      throw StateError(
        'Backup oltre il budget del browser: usare l’app per un backup completo',
      );
    final bytes = await encode(
      notes,
      tags: await NoteTags.load(),
      onProgress: onProgress,
    );
    return PreparedBackup(bytes, notes.length, unavailable);
  }

  static Future<PreparedBackup> _createStaged(
    ValueChanged<String>? progress,
    BackupCancellation? cancel,
  ) async {
    final root = await staging.createStaging();
    final writer = staging.StagedZipWriter(root);
    final records = <Map<String, dynamic>>[], unavailable = <String>[];
    final hashes = <String, String>{};
    try {
      final library = await RecentDocuments.list(),
          recoveries = await AutosaveStore.list();
      final jobs = <Map<String, dynamic>>[
        for (final entry in library) {'entry': entry},
        for (final recovery in recoveries) {'recovery': recovery},
      ];
      for (final job in jobs) {
        cancel?.check();
        final entry = (job['entry'] ?? job['recovery']) as Map<String, dynamic>;
        final recovery = job['recovery'] != null;
        final title =
            (entry[recovery ? 'title' : 'name'] as String?) ?? 'Appunto';
        progress?.call('Preparazione: $title');
        var writing = false;
        try {
          final bytes = recovery
              ? await AutosaveStore.readBytes(entry)
              : (await FilePickerCross.fromInternalPath(
                  path: entry['path'] as String,
                  maxBytes: inMemoryBytes,
                )).toUint8List();
          if (bytes.length > inMemoryBytes)
            throw StateError('Appunto oltre il budget di lavoro di 32 MiB');
          final hash = FilePickerCross(bytes).contentHash;
          final source = entry[recovery ? 'source' : 'path'] as String?;
          if (recovery && source != null && hashes[source] == hash) continue;
          final file = await XppFile.fromFilePickerCross(
            FilePickerCross(bytes),
            null,
            (_) async => throw StateError('Sfondo mancante'),
            limits: workingLimits,
          );
          await _makePortable(file);
          if (file.importWarnings.isNotEmpty)
            unavailable.add(
              '$title: apertura protetta; contenuto originale conservato integralmente',
            );
          if (records.length >= maxNotes) throw StateError('Troppi appunti');
          final name = 'notes/${records.length}.xopp';
          writing = true;
          await writer.add(name, bytes);
          records.add({
            'file': name,
            'title': recovery && source != null && hashes.containsKey(source)
                ? '$title (recupero)'
                : title,
            'tag': entry['tag'] ?? file.tag ?? 'Appunti',
            'favorite': entry['favorite'] == true,
          });
          if (!recovery && source != null) hashes[source] = hash;
        } catch (error) {
          if (writing) rethrow;
          unavailable.add('$title: $error');
        }
      }
      cancel?.check();
      if (records.isEmpty)
        throw StateError('Nessun appunto accessibile per il backup');
      final manifest = utf8.encode(
        jsonEncode({
          'format': 'osipp.notes-backup',
          'version': 1,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'tags': await NoteTags.load(),
          'notes': records,
        }),
      );
      if (manifest.length > 8 * 1024 * 1024)
        throw StateError('Manifesto troppo grande');
      await writer.add('manifest.json', Uint8List.fromList(manifest));
      await writer.close();
      return PreparedBackup.staged(
        writer.path,
        root,
        records.length,
        unavailable,
      );
    } catch (_) {
      await writer.close();
      await staging.disposeStaging(root);
      rethrow;
    }
  }

  static Future<BackupContents> inspectStaged(
    String path, {
    ValueChanged<String>? onProgress,
    BackupCancellation? cancellation,
  }) async {
    final extracted = await staging.inspectArchive(path);
    final root = extracted['root'] as String;
    try {
      cancellation?.check();
      final text = extracted['manifestText'] as String;
      validateDocumentJsonText(text);
      final manifest = jsonDecode(text);
      final paths = extracted['paths'] as Map<String, String>;
      if (manifest is! Map ||
          manifest['format'] != 'osipp.notes-backup' ||
          manifest['version'] != 1 ||
          manifest['notes'] is! List ||
          (manifest['notes'] as List).isEmpty ||
          (manifest['notes'] as List).length != paths.length ||
          manifest['tags'] is! List ||
          (manifest['tags'] as List).any((e) => e is! String))
        throw const FormatException('Manifesto backup invalido');
      final seen = <String>{}, notes = <BackupNote>[];
      var xmlBytes = 0, media = 0, nodes = 0, points = 0, pages = 0, layers = 0;
      for (final record in manifest['notes'] as List) {
        cancellation?.check();
        if (record is! Map ||
            record['file'] is! String ||
            record['title'] is! String ||
            record['tag'] is! String ||
            record['favorite'] is! bool ||
            !seen.add(record['file'] as String) ||
            !paths.containsKey(record['file']))
          throw const FormatException('Indice backup invalido');
        onProgress?.call(
          'Verifica appunto ${notes.length + 1} di ${paths.length}',
        );
        final payload = paths[record['file']]!;
        final file = await XppFile.fromFilePickerCross(
          FilePickerCross(await staging.readStaged(payload)),
          null,
          (_) async => throw StateError('Sfondo mancante'),
          limits: DocumentLimits(
            compressedBytes: inMemoryBytes,
            xmlBytes: min(workingLimits.xmlBytes, maxBytes - xmlBytes),
            mediaBytes: min(
              workingLimits.mediaBytes,
              256 * 1024 * 1024 - media,
            ),
            nodes: min(workingLimits.nodes, 500000 - nodes),
            points: min(workingLimits.points, 2000000 - points),
            pages: min(workingLimits.pages, 20000 - pages),
            layers: min(workingLimits.layers, 100000 - layers),
          ),
        );
        xmlBytes += file.importedXmlBytes;
        media += file.importedMediaBytes;
        nodes += file.importedNodes;
        points += file.importedPoints;
        pages += file.importedPages;
        layers += file.importedLayers;
        await _makePortable(file);
        notes.add(
          BackupNote.staged(
            payload,
            record['title'] as String,
            record['tag'] as String,
            favorite: record['favorite'] == true,
          ),
        );
      }
      return BackupContents(
        notes,
        (manifest['tags'] as List).cast<String>(),
        DateTime.tryParse(manifest['createdAt'] as String? ?? ''),
        stagingRoot: root,
      );
    } catch (_) {
      await staging.disposeStaging(root);
      rethrow;
    }
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
      throw StateError(
        'Seleziona esplicitamente l’allegato di sfondo prima del backup',
      );
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
      if (total > inMemoryBytes)
        throw StateError(
          'Backup in memoria oltre 32 MiB: usare lo staging su dispositivo.',
        );
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
    if (bytes.isEmpty || bytes.length > inMemoryBytes) {
      throw const FormatException('Dimensione del backup non valida.');
    }
    final archive = decodeBoundedZip(
      bytes,
      maxInput: maxBytes + 1024 * 1024,
      maxOutput: maxBytes,
      maxEntries: maxNotes + 1,
      entryLimit: (name) {
        if (name == 'manifest.json') return 8 * 1024 * 1024;
        if (RegExp(r'^notes/[0-9]+\.xopp$').hasMatch(name)) {
          return DocumentLimits.standard.compressedBytes;
        }
        throw const FormatException('Percorso non valido nel backup');
      },
    );
    final manifestFile = archive['manifest.json'];
    if (manifestFile == null) {
      throw const FormatException('Manifest del backup mancante o non valido.');
    }
    final manifestText = utf8.decode(manifestFile);
    validateDocumentJsonText(manifestText);
    final manifest = jsonDecode(manifestText);
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
      final entry = archive[record['file'] as String];
      if (entry == null) {
        throw const FormatException('Un appunto è assente dal backup.');
      }
      payload.add(entry);
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
    var xmlBytes = 0,
        mediaBytes = 0,
        nodes = 0,
        points = 0,
        pages = 0,
        layers = 0;
    final clock = Stopwatch()..start();
    for (final (i, data) in (decoded['payload'] as List<Uint8List>).indexed) {
      if (clock.elapsed > const Duration(minutes: 2)) {
        throw const FormatException('Backup troppo complesso');
      }
      onProgress?.call('Verifica appunto ${i + 1} di ${records.length}');
      final file = await XppFile.fromFilePickerCross(
        FilePickerCross(data),
        null,
        (_) async => throw StateError('Il backup non contiene lo sfondo.'),
        limits: DocumentLimits(
          xmlBytes: min(
            workingLimits.xmlBytes,
            64 * 1024 * 1024 - xmlBytes - mediaBytes,
          ),
          mediaBytes: min(
            32 * 1024 * 1024,
            64 * 1024 * 1024 - xmlBytes - mediaBytes,
          ),
          nodes: min(DocumentLimits.standard.nodes, 500000 - nodes),
          points: min(DocumentLimits.standard.points, 2000000 - points),
          pages: min(DocumentLimits.standard.pages, 20000 - pages),
          layers: min(DocumentLimits.standard.layers, 100000 - layers),
        ),
      );
      xmlBytes += file.importedXmlBytes;
      mediaBytes += file.importedMediaBytes;
      nodes += file.importedNodes;
      points += file.importedPoints;
      pages += file.importedPages;
      layers += file.importedLayers;
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
    BackupCancellation? cancellation,
  }) async {
    if (_restoring) throw StateError('Un ripristino è già in corso.');
    if (backup.notes.isEmpty || backup.notes.length > maxNotes) {
      throw const FormatException('Numero di appunti non valido.');
    }
    _restoring = true;
    RecentDocuments.restoring = true;
    final written = <String>[];
    final restored = <BackupNote>[];
    try {
      for (final (i, note) in backup.notes.indexed) {
        cancellation?.check();
        onProgress?.call(
          'Ripristino appunto ${i + 1} di ${backup.notes.length}',
        );
        final source = await note.load();
        final file = XppFile(
          title: source.title,
          tag: source.tag,
          modifiedAt: source.modifiedAt,
          autoGeneratePages: source.autoGeneratePages,
          previewImage: source.previewImage,
          documentId: note.payloadPath == null ? null : source.documentId,
          pages: source.pages,
          pdfAttachments: Map.of(source.pdfAttachments),
          recordings: Map.of(source.recordings),
          flashcards: Map.of(source.flashcards),
        );
        var destination = 'backup-${file.documentId}.xopp';
        while (await FilePickerCross.exists(destination)) {
          destination =
              'backup-${file.documentId}-${Random.secure().nextInt(1 << 32)}.xopp';
        }
        final data = FilePickerCross(
          note.payloadPath == null
              ? await file.serializeSnapshotAsync()
              : await staging.readStaged(note.payloadPath!),
        );
        final pending =
            (await CriticalData.read('restorePending') as List?) ?? [];
        final resolved = await FilePickerCross.resolvePath(destination);
        await CriticalData.write('restorePending', [
          ...pending,
          {
            'name': file.title,
            'path': resolved,
            'id': file.documentId,
            'key': XppFile.recoveryKeyFor(resolved, file.localId),
            'localId': file.localId,
            'tag': file.tag ?? 'Appunti',
            'favorite': note.favorite,
            'preview': file.previewImage == null
                ? ''
                : base64Encode(file.previewImage!),
          },
        ]);
        file.sourcePath = await data.saveToPath(path: destination);
        written.add(file.sourcePath!);
        restored.add(
          BackupNote(
            XppFile(
              title: file.title,
              tag: file.tag,
              documentId: file.documentId,
              localId: file.localId,
              sourcePath: file.sourcePath,
              modifiedAt: file.modifiedAt,
              previewImage: file.previewImage,
            ),
            favorite: note.favorite,
          ),
        );
      }
      await RecentDocuments.addRestored([
        for (final n in restored) (file: n.file, favorite: n.favorite),
      ], backup.tags);
      return restored.length;
    } catch (_) {
      // Complete staged files survive interruption and are reconciled on reopen.
      rethrow;
    } finally {
      _restoring = false;
      RecentDocuments.restoring = false;
    }
  }
}
