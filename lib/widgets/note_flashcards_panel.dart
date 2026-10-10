import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'bounded_image.dart';

import 'package:provider/provider.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/plugins/plugin_controller.dart';
import 'package:xournalpp/src/compat/file_picker_cross.dart';
import 'package:xournalpp/src/document_export.dart';
import 'package:xournalpp/src/editing_tool.dart';
import 'package:xournalpp/src/note_flashcards.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/content_snapshot.dart';

Future<void> captureFlashcardSelection(
  BuildContext context,
  CanvasController ctrl,
  int pageIndex,
  Rect region,
) async {
  final plugins = context.read<PluginController?>();
  if (plugins?.ankiEnabled != true ||
      ctrl.capturingFlashcard ||
      ctrl.savingFile ||
      region.width < 3 ||
      region.height < 3) {
    return;
  }
  final file = ctrl.file;
  final generation = ctrl.flashcardGeneration;
  final revision = ctrl.pluginRevision;
  if (file == null || pageIndex >= file.pages!.length) return;
  ctrl.capturingFlashcard = true;
  ctrl.refreshFlashcardTool();
  try {
    final page = file.pages![pageIndex];
    final texts =
        [
          for (final layer in page.layers!.where((l) => l.visible))
            for (final text in (layer.content ?? []).whereType<XppText>())
              if (text.bounds()?.overlaps(region) == true) text,
        ]..sort((a, b) {
          final dy = a.offset!.dy.compareTo(b.offset!.dy);
          return dy != 0 ? dy : a.offset!.dx.compareTo(b.offset!.dx);
        });
    final bytes = await rasterizeExportPage(
      XppPage(
        pageSize: page.pageSize,
        background: page.background,
        layers: [
          for (final l in page.layers!)
            XppLayer(
              name: l.name,
              visible: l.visible,
              locked: l.locked,
              content: cloneContents(l.content ?? []),
            ),
        ],
        infinite: false,
      ),
      backgroundBytes: await ctrl.flashcardBackground(pageIndex),
      region: region,
      clipToPage: !page.infinite,
    );
    if (!context.mounted ||
        !ctrl.acceptsPluginEdits ||
        !identical(ctrl.file, file) ||
        ctrl.flashcardGeneration != generation ||
        ctrl.pluginRevision != revision ||
        plugins?.ankiEnabled != true ||
        ctrl.toolData[PointerDeviceKind.stylus] != EditingTool.FLASHCARD) {
      return;
    }
    final side = FlashcardSide(
      text:
          page.background is XppBackgroundPdf ||
              page.layers!
                  .where((l) => l.visible)
                  .any(
                    (l) => (l.content ?? []).any(
                      (c) =>
                          c != null &&
                          c is! XppText &&
                          c.bounds()?.overlaps(region) == true,
                    ),
                  )
          ? ''
          : texts.map((t) => t.text ?? '').join('\n'),
      image: bytes,
      page: pageIndex,
    );
    final front = ctrl.flashcardFront;
    if (front == null) {
      ctrl.flashcardFront = side;
    } else {
      final edited = await editFlashcard(
        context,
        NoteFlashcard(front: front, back: side),
      );
      if (edited != null &&
          ctrl.acceptsPluginEdits &&
          ctrl.flashcardGeneration == generation &&
          identical(ctrl.file, file) &&
          plugins?.ankiEnabled == true) {
        ctrl.saveFlashcard(edited);
      }
      if (ctrl.flashcardGeneration == generation) ctrl.flashcardFront = null;
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  } finally {
    ctrl.capturingFlashcard = false;
    ctrl.refreshFlashcardTool();
  }
}

Future<NoteFlashcard?> editFlashcard(
  BuildContext context,
  NoteFlashcard card,
) => showDialog<NoteFlashcard>(
  context: context,
  builder: (_) => _FlashcardEditor(card: card),
);

class _FlashcardEditor extends StatefulWidget {
  final NoteFlashcard card;
  const _FlashcardEditor({required this.card});
  @override
  State<_FlashcardEditor> createState() => _FlashcardEditorState();
}

class _FlashcardEditorState extends State<_FlashcardEditor> {
  late final front = TextEditingController(text: widget.card.front.text);
  late final back = TextEditingController(text: widget.card.back.text);
  bool frontImage = true, backImage = true;
  String? error;
  @override
  void dispose() {
    front.dispose();
    back.dispose();
    super.dispose();
  }

  Widget _side(
    String label,
    FlashcardSide side,
    TextEditingController text,
    bool keepImage,
    ValueChanged<bool> changed,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: text,
        minLines: 1,
        maxLines: 5,
        decoration: InputDecoration(
          labelText: label,
          helperText: 'Con testo vuoto viene usata l’immagine selezionata.',
        ),
      ),
      if (side.image != null) ...[
        const SizedBox(height: 8),
        BoundedImage(side.image!, height: 110, fit: BoxFit.contain),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Conserva immagine'),
          value: keepImage,
          onChanged: (v) => changed(v!),
        ),
      ],
    ],
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Modifica flashcard'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _side(
              'Titolo / fronte',
              widget.card.front,
              front,
              frontImage,
              (v) => setState(() => frontImage = v),
            ),
            const SizedBox(height: 20),
            _side(
              'Risposta / retro',
              widget.card.back,
              back,
              backImage,
              (v) => setState(() => backImage = v),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        onPressed: () {
          if ((front.text.trim().isEmpty &&
                  (!frontImage || widget.card.front.image == null)) ||
              (back.text.trim().isEmpty &&
                  (!backImage || widget.card.back.image == null))) {
            setState(
              () => error = 'Ogni lato richiede un testo o un’immagine.',
            );
            return;
          }
          Navigator.pop(
            context,
            NoteFlashcard(
              id: widget.card.id,
              front: FlashcardSide(
                text: front.text.trim(),
                page: widget.card.front.page,
                image: frontImage ? widget.card.front.image : null,
              ),
              back: FlashcardSide(
                text: back.text.trim(),
                page: widget.card.back.page,
                image: backImage ? widget.card.back.image : null,
              ),
            ),
          );
        },
        child: const Text('Salva'),
      ),
    ],
  );
}

Future<void> showNoteFlashcards(BuildContext context, CanvasController ctrl) =>
    showDialog<void>(
      context: context,
      builder: (_) => _FlashcardSet(
        canvas: ctrl,
        plugins: context.read<PluginController?>(),
      ),
    );

class _FlashcardSet extends StatelessWidget {
  final CanvasController canvas;
  final PluginController? plugins;
  const _FlashcardSet({required this.canvas, this.plugins});
  Future<void> _export(BuildContext context, bool json) async {
    try {
      final file = canvas.file!;
      final cards = file.flashcards.values.toList();
      final deck = file.title ?? 'OSIpp';
      final data = json
          ? Uint8List.fromList(utf8.encode(flashcardsJson(cards, deck)))
          : flashcardsAnkiBundle(cards, deck);
      await FilePickerCross(
        data,
        path: json ? 'flashcard.json' : 'flashcard-anki.zip',
      ).exportToStorage();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: canvas,
    builder: (context, _) {
      final cards = canvas.file!.flashcards.values.toList();
      return AlertDialog(
        title: Text('Flashcard · ${canvas.file!.title ?? 'Appunti'}'),
        content: SizedBox(
          width: 600,
          height: 420,
          child: Column(
            children: [
              const Text(
                'Seleziona prima il titolo, poi la risposta. '
                'Le flashcard vengono salvate insieme a questo appunto.',
              ),
              if (plugins?.legacyAnkiCards.isNotEmpty == true)
                TextButton(
                  onPressed: canvas.savingFile
                      ? null
                      : () {
                          for (final (i, c)
                              in plugins!.legacyAnkiCards.indexed) {
                            // Deterministic IDs prevent duplicate imports into this note.
                            if (canvas.file!.flashcards.containsKey(
                              'legacy-anki-$i',
                            )) {
                              continue;
                            }
                            canvas.saveFlashcard(
                              NoteFlashcard(
                                id: 'legacy-anki-$i',
                                front: FlashcardSide(
                                  text: c['front'] as String,
                                ),
                                back: FlashcardSide(text: c['back'] as String),
                              ),
                            );
                          }
                        },
                  child: const Text('Copia qui le carte del vecchio plugin'),
                ),
              Expanded(
                child: cards.isEmpty
                    ? const Center(
                        child: Text('Nessuna flashcard in questo appunto.'),
                      )
                    : ListView.builder(
                        itemCount: cards.length,
                        itemBuilder: (_, i) {
                          final card = cards[i];
                          return Card(
                            child: ListTile(
                              title: Text(
                                card.front.text.isEmpty
                                    ? 'Titolo selezionato ${i + 1}'
                                    : card.front.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                card.back.text.isEmpty
                                    ? 'Risposta come immagine'
                                    : card.back.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: canvas.savingFile
                                  ? null
                                  : () async {
                                      final edited = await editFlashcard(
                                        context,
                                        card,
                                      );
                                      if (edited != null &&
                                          canvas.acceptsPluginEdits) {
                                        canvas.saveFlashcard(edited);
                                      }
                                    },
                              trailing: IconButton(
                                tooltip: 'Elimina flashcard',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: canvas.savingFile
                                    ? null
                                    : () => canvas.deleteFlashcard(card.id),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
          TextButton(
            onPressed: cards.isEmpty ? null : () => _export(context, true),
            child: const Text('Esporta JSON'),
          ),
          TextButton(
            onPressed: cards.isEmpty ? null : () => _export(context, false),
            child: const Text('Esporta per Anki'),
          ),
          FilledButton(
            onPressed: canvas.savingFile
                ? null
                : () {
                    canvas.beginFlashcard();
                    Navigator.pop(context);
                  },
            child: const Text('Doppia selezione'),
          ),
        ],
      );
    },
  );
}
