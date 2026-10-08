import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';

import 'layers_panel.dart';

class DocumentNavigator extends StatelessWidget {
  final CanvasController controller;
  final VoidCallback onClose;
  const DocumentNavigator({
    super.key,
    required this.controller,
    required this.onClose,
  });
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 4,
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: TabBar(
                  tabs: [
                    Tab(text: 'Livelli'),
                    Tab(text: 'Pagine'),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Chiudi pannello',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                LayersPanel(controller: controller),
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => ListView.builder(
                    itemCount: controller.file?.pages?.length ?? 0,
                    itemBuilder: (context, index) => PageThumbnail(
                      key: ObjectKey(controller.file!.pages![index]),
                      controller: controller,
                      index: index,
                    ),
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

/// Only mounted rows render; debounce edits and release each thumbnail with its row.
class PageThumbnail extends StatefulWidget {
  final CanvasController controller;
  final int index;
  const PageThumbnail({
    super.key,
    required this.controller,
    required this.index,
  });
  @override
  State<PageThumbnail> createState() => _PageThumbnailState();
}

class _PageThumbnailState extends State<PageThumbnail> {
  Timer? _timer;
  Uint8List? _bytes;
  bool _busy = false, _again = false;
  int _generation = 0;
  int _revision = -1;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(PageThumbnail old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_schedule);
      widget.controller.addListener(_schedule);
    }
    if (old.index != widget.index || old.controller != widget.controller) {
      _generation++;
      _revision = -1;
      _schedule();
    }
  }

  void _schedule() {
    if (_bytes != null && _revision == widget.controller.pluginRevision) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 650), _render);
  }

  void _release(Uint8List? bytes) {
    if (bytes != null)
      unawaited(
        ResizeImage.resizeIfNeeded(180, null, MemoryImage(bytes)).evict(),
      );
  }

  Future<void> _render() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    final generation = _generation;
    final revision = widget.controller.pluginRevision;
    try {
      final bytes = await widget.controller.buildPageThumbnail(widget.index);
      if (mounted && generation == _generation)
        setState(() {
          _release(_bytes);
          _bytes = bytes;
          _revision = revision;
        });
    } catch (_) {
      /* Keep the last usable preview; no unhandled PDF error. */
    } finally {
      _busy = false;
      if (mounted && _again) {
        _again = false;
        _schedule();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _release(_bytes);
    _bytes = null;
    _timer?.cancel();
    widget.controller.removeListener(_schedule);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: InkWell(
      onTap: () => widget.controller.goToPage(widget.index),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(
            color: widget.controller.activePageIndex == widget.index
                ? Theme.of(context).colorScheme.primary
                : Colors.white24,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 165,
              child: _bytes == null
                  ? const Center(child: Icon(Icons.description_outlined))
                  : Image.memory(
                      _bytes!,
                      cacheWidth: 180,
                      gaplessPlayback: true,
                    ),
            ),
            Text('Pagina ${widget.index + 1}'),
          ],
        ),
      ),
    ),
  );
}
