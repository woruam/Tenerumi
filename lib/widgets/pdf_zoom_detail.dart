import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:xournalpp/controllers/canvas_controller.dart';

/// A bounded crop at screen resolution, rather than a huge full-page bitmap.
class PdfDetailPlan {
  final Rect region;
  final double scale;
  final int width, height;
  const PdfDetailPlan(this.region, this.scale, this.width, this.height);

  static PdfDetailPlan? create(Size page, Rect visible, double requestedScale) {
    final crop = visible.intersect(Offset.zero & page);
    if (crop.isEmpty || !requestedScale.isFinite || requestedScale <= 0) {
      return null;
    }
    final scale = math.min(
      requestedScale,
      math.min(
        2046 / math.max(crop.width, crop.height),
        math.sqrt(1990000 / (crop.width * crop.height)),
      ),
    );
    // Pixel-aligned bounds match sourceX/sourceY and the displayed crop exactly.
    final left = (crop.left * scale).floor(), top = (crop.top * scale).floor();
    final right = (crop.right * scale).ceil(),
        bottom = (crop.bottom * scale).ceil();
    return PdfDetailPlan(
      Rect.fromLTRB(left / scale, top / scale, right / scale, bottom / scale),
      scale,
      right - left,
      bottom - top,
    );
  }

  bool matches(PdfDetailPlan other) =>
      region == other.region && (scale - other.scale).abs() < .001;
}

class PdfZoomDetail extends StatefulWidget {
  final CanvasController controller;
  final int pageIndex;
  final TransformationController transform;
  final GlobalKey viewportKey;
  const PdfZoomDetail({
    super.key,
    required this.controller,
    required this.pageIndex,
    required this.transform,
    required this.viewportKey,
  });
  @override
  State<PdfZoomDetail> createState() => _PdfZoomDetailState();
}

class _PdfZoomDetailState extends State<PdfZoomDetail>
    with WidgetsBindingObserver {
  Timer? _timer;
  pdfx.PdfDocument? _document;
  pdfx.PdfPageTexture? _texture;
  PdfDetailPlan? _shown;
  final _retired = <pdfx.PdfPageTexture>{};
  Future<void>? _pending, _releasing;
  bool _paused = false;
  bool _again = false, _unsupported = false;
  int _generation = 0;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.transform.addListener(_schedule);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _schedule();
    });
  }

  @override
  void didUpdateWidget(PdfZoomDetail old) {
    super.didUpdateWidget(old);
    if (old.transform != widget.transform) {
      old.transform.removeListener(_schedule);
      widget.transform.addListener(_schedule);
    }
    _schedule();
  }

  void _schedule() {
    if (!_supported || _unsupported || _paused) return;
    _generation++;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 180), _update);
  }

  Future<void> _update() async {
    if (!mounted || _paused || _releasing != null) return;
    if (_pending != null) {
      _again = true;
      return;
    }
    final page = context.findRenderObject() as RenderBox?;
    final viewport =
        widget.viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (page == null ||
        viewport == null ||
        !page.hasSize ||
        !viewport.hasSize) {
      return;
    }
    final origin = page.localToGlobal(Offset.zero);
    final displayScale =
        (page.localToGlobal(const Offset(1, 0)) - origin).distance;
    final viewportRect = (viewport.localToGlobal(Offset.zero) & viewport.size)
        .inflate(24);
    final region = Rect.fromPoints(
      page.globalToLocal(viewportRect.topLeft),
      page.globalToLocal(viewportRect.bottomRight),
    );
    final plan = PdfDetailPlan.create(
      page.size,
      region,
      displayScale * MediaQuery.devicePixelRatioOf(context),
    );
    if (plan == null) return;
    if (_shown?.matches(plan) == true) return;
    final generation = _generation;
    final pending = _render(plan, page.size, generation);
    _pending = pending;
    await pending;
    _pending = null;
    if (mounted && _again) {
      _again = false;
      _schedule();
    }
  }

  Future<void> _render(PdfDetailPlan plan, Size size, int generation) async {
    pdfx.PdfPageTexture? next;
    try {
      final sourcePage = widget.controller.pdfSourcePage(widget.pageIndex);
      final document = _document ??= await widget.controller.openPdfDetail(
        widget.pageIndex,
      );
      if (!mounted || generation != _generation) return;
      final source = await document.getPage(sourcePage);
      try {
        next = await source.createTexture();
      } finally {
        await source.close();
      }
      if (!mounted || generation != _generation) return;
      final success = await next.updateRect(
        documentId: document.id,
        width: plan.width,
        height: plan.height,
        textureWidth: plan.width,
        textureHeight: plan.height,
        sourceX: (plan.region.left * plan.scale).round(),
        sourceY: (plan.region.top * plan.scale).round(),
        fullWidth: size.width * plan.scale,
        fullHeight: size.height * plan.scale,
        backgroundColor: '#FFFFFF',
      );
      if (!success || !mounted || generation != _generation) return;
      final old = _texture;
      setState(() {
        _texture = next;
        _shown = plan;
      });
      next = null;
      if (old != null) {
        _retired.add(old);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_retired.remove(old)) unawaited(_disposeTexture(old));
        });
      }
    } catch (_) {
      // Keep the regular page raster when a platform lacks texture rendering.
      _unsupported = true;
    } finally {
      await _disposeTexture(next);
    }
  }

  Future<void> _disposeTexture(pdfx.PdfPageTexture? texture) async {
    try {
      await texture?.dispose();
    } catch (_) {
      // A failed texture release must not prevent closing its document.
    }
  }

  Future<void> _release() {
    if (_releasing != null) return _releasing!;
    final texture = _texture;
    _texture = null;
    _shown = null;
    return _releasing = () async {
      await _pending;
      await _disposeTexture(texture);
      final retired = _retired.toList();
      _retired.clear();
      for (final old in retired) {
        await _disposeTexture(old);
      }
      final document = _document;
      _document = null;
      try {
        await document?.close();
      } catch (_) {
        // The platform may already have released a document on shutdown.
      } finally {
        _releasing = null;
      }
    }();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _paused = false;
      _unsupported = false;
      unawaited(() async {
        await _releasing;
        if (mounted) _schedule();
      }());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _paused = true;
      _generation++;
      _timer?.cancel();
      final releasing = _release();
      setState(() {});
      unawaited(releasing);
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.transform.removeListener(_schedule);
    unawaited(_release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      children: [
        if (_texture != null && _shown != null)
          Positioned.fromRect(
            rect: _shown!.region,
            child: Texture(
              textureId: _texture!.id,
              filterQuality: FilterQuality.high,
            ),
          ),
      ],
    ),
  );
}
