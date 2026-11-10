import 'package:xournalpp/src/app_appearance.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xournalpp/src/library_metadata.dart';

import 'bounded_image.dart';

String documentModifiedLabel(Object? value) {
  final date = value is String ? DateTime.tryParse(value)?.toLocal() : null;
  if (date == null) return 'Data non disponibile';
  // This fixed numeric format needs no locale data. In particular, library
  // cards must also build during a cold start and after metadata is loaded.
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return 'Modificato il ${twoDigits(date.day)}/${twoDigits(date.month)}/'
      '${date.year.toString().padLeft(4, '0')} '
      '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
}

class DocumentPreviewImage extends StatefulWidget {
  final String? encoded;
  final IconData fallbackIcon;
  const DocumentPreviewImage({
    super.key,
    this.encoded,
    required this.fallbackIcon,
  });
  @override
  State<DocumentPreviewImage> createState() => _DocumentPreviewImageState();
}

class _DocumentPreviewImageState extends State<DocumentPreviewImage> {
  Uint8List? _bytes;
  void _decode() {
    try {
      if ((widget.encoded?.length ?? 0) > 512 * 1024)
        throw const FormatException('Anteprima troppo grande');
      final bytes = base64Decode(widget.encoded ?? '');
      _bytes = bytes.isEmpty || listEquals(bytes, kTransparentImage)
          ? null
          : bytes;
    } catch (_) {
      _bytes = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(DocumentPreviewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.encoded != widget.encoded) _decode();
  }

  Widget _fallback() => Icon(
    widget.fallbackIcon,
    size: 48,
    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .3),
  );
  @override
  Widget build(BuildContext context) => _bytes == null
      ? _fallback()
      : BoundedImage(_bytes!, fit: BoxFit.contain, fallback: _fallback());
}

class DocumentLibraryCard extends StatefulWidget {
  final Map<String, dynamic> entry;
  final VoidCallback onTap;
  final VoidCallback? onTagEdit;
  final VoidCallback? onLongPress;
  final IconData fallbackIcon;
  final LibraryMetadataLoader? metadataLoader;
  const DocumentLibraryCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.onTagEdit,
    this.onLongPress,
    required this.fallbackIcon,
    this.metadataLoader,
  });
  @override
  State<DocumentLibraryCard> createState() => _DocumentLibraryCardState();
}

class _DocumentLibraryCardState extends State<DocumentLibraryCard> {
  late Map<String, dynamic> _data;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(DocumentLibraryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (const [
      'path',
      'name',
      'tag',
      'preview',
      'modifiedAt',
    ].any((key) => oldWidget.entry[key] != widget.entry[key])) {
      _sync();
    }
  }

  void _sync() {
    _data = Map.of(widget.entry);
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _generation) return;
      final path = _data['path'];
      if (path is! String || path.isEmpty) return;
      if (_data['modifiedAt'] != null &&
          _data['preview'] is String &&
          _data['preview'] != '' &&
          _data['preview'] != base64Encode(kTransparentImage)) {
        return;
      }
      final loader = widget.metadataLoader ?? LibraryMetadata.load;
      try {
        final metadata = await loader(
          Map.of(_data),
          () => mounted && generation == _generation,
        );
        if (mounted && generation == _generation && metadata != null) {
          setState(() => _data.addAll(metadata));
        }
      } catch (_) {
        /* Missing files must not prevent the library from opening. */
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tagName = _data['tag'] as String? ?? 'Appunti';
    final title = _data['name'] as String? ?? 'Senza titolo';
    final modified = documentModifiedLabel(_data['modifiedAt']);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppAppearance.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppAppearance.border, width: 1),
      ),
      elevation: 0,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress ?? widget.onTagEdit,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: AppAppearance.raised,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: DocumentPreviewImage(
                        encoded: _data['preview'] is String
                            ? _data['preview'] as String
                            : null,
                        fallbackIcon: widget.fallbackIcon,
                      ),
                    ),
                    if (widget.onTagEdit != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: IconButton.filledTonal(
                          tooltip: 'Cambia tag',
                          style: IconButton.styleFrom(
                            backgroundColor:
                                AppAppearance.panel.withValues(alpha: 0.88),
                            foregroundColor: cs.onSurfaceVariant,
                            minimumSize: const Size(30, 30),
                            padding: const EdgeInsets.all(5),
                            shape: const CircleBorder(
                              side: BorderSide(
                                color: AppAppearance.border,
                                width: 0.8,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.sell_outlined, size: 15),
                          onPressed: widget.onTagEdit,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tagName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    modified,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
