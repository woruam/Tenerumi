import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/note_audio_controller.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppLayer.dart';

/// Playback has its own display list; original ink, PDF and input never repaint
/// on audio-clock updates. Nothing is changed in the document or exported image.
class AudioTimelineOverlay extends StatelessWidget {
  final XppPage page;
  final NoteAudioController audio;
  final Offset origin;
  const AudioTimelineOverlay({
    super.key,
    required this.page,
    required this.audio,
    this.origin = Offset.zero,
  });
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: AudioTimelinePainter(page, audio, origin),
      ),
    ),
  );
}

class AudioTimelinePainter extends CustomPainter {
  final XppPage page;
  final NoteAudioController audio;
  final Offset origin;
  AudioTimelinePainter(this.page, this.audio, this.origin)
    : super(repaint: audio.cursor);
  @override
  void paint(Canvas canvas, Size size) {
    final cursor = audio.cursor.value;
    if (cursor.id == null) return;
    final viewport = (origin & size).inflate(12);
    canvas.save();
    canvas.translate(-origin.dx, -origin.dy);
    for (final layer in page.layers ?? const <XppLayer>[]) {
      if (!layer.visible) continue;
      for (final stroke
          in (layer.content ?? const <XppContent?>[]).whereType<XppStroke>()) {
        final link = stroke.audioLink;
        if (link == null ||
            link.recordingId != cursor.id ||
            cursor.milliseconds < link.startMs ||
            cursor.milliseconds > link.endMs)
          continue;
        final bounds = stroke.bounds();
        final points = stroke.points!;
        if (bounds == null || points.isEmpty || !bounds.overlaps(viewport))
          continue;
        var count = 1;
        if (link.samples.length == points.length) {
          var lo = 0, hi = link.samples.length;
          while (lo < hi) {
            final mid = (lo + hi) ~/ 2;
            if (link.samples[mid] <= cursor.milliseconds)
              lo = mid + 1;
            else
              hi = mid;
          }
          count = math.max(1, lo);
        } else {
          final progress =
              (cursor.milliseconds - link.startMs) /
              math.max(1, link.endMs - link.startMs);
          count = (1 + progress * (points.length - 1))
              .round()
              .clamp(1, points.length)
              .toInt();
        }
        final region = bounds.inflate(8).intersect(viewport);
        canvas.saveLayer(region, Paint());
        final path = Path()..moveTo(points.first.x!, points.first.y!);
        for (var i = 1; i < count; i++) {
          path.lineTo(points[i].x!, points[i].y!);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xff00bcd4)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 3,
        );
        canvas.drawCircle(
          points[count - 1].offset,
          4,
          Paint()..color = const Color(0xff00bcd4),
        );
        for (final cut in stroke.erasures) {
          if (cut.bounds.overlaps(region))
            canvas.drawPath(cut.path, Paint()..blendMode = BlendMode.dstOut);
        }
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AudioTimelinePainter old) => true; // Pages are mutable: repaint after edits, including while paused.
}
