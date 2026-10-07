import 'package:xournalpp/src/app_appearance.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xournalpp/src/library_metadata.dart';

String documentModifiedLabel(Object? value) {
  final date = value is String ? DateTime.tryParse(value) : null;
  return date == null
      ? 'Data non disponibile'
      : 'Modificato il ${DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal())}';
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
      : Image.memory(
          _bytes!,
          fit: BoxFit.contain,
          cacheWidth: 320,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _fallback(),
          excludeFromSemantics: true,
        );
}

class DocumentLibraryCard extends StatefulWidget {
  final Map<String, dynamic> entry;
  final VoidCallback onTap;
  final IconData fallbackIcon;
  final LibraryMetadataLoader? metadataLoader;
  const DocumentLibraryCard({
    super.key,
    required this.entry,
    required this.onTap,
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
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    color: AppAppearance.panel,
    shape: AppAppearance.panelShape,
    child: InkWell(
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              color: AppAppearance.raised,
              child: RepaintBoundary(
                child: DocumentPreviewImage(
                  encoded: _data['preview'] is String
                      ? _data['preview'] as String
                      : null,
                  fallbackIcon: widget.fallbackIcon,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _data['name'] as String? ?? 'Senza titolo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Text(
                  _data['tag'] as String? ?? 'Appunti',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  documentModifiedLabel(_data['modifiedAt']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
