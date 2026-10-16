import 'package:flutter/material.dart';

/// A tomato that fills from bottom to top as the current timer elapses.
class PomodoroProgressIcon extends StatelessWidget {
  final ValueNotifier<double>? progress;
  const PomodoroProgressIcon({super.key, this.progress});

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.white;
    Widget tomato(double value) => Semantics(
      label: 'Pomodoro ${(value * 100).round()}%',
      child: CustomPaint(
        size: const Size(24, 24),
        painter: _TomatoPainter(value, color),
      ),
    );
    return progress == null
        ? tomato(0)
        : ValueListenableBuilder<double>(
            valueListenable: progress!,
            builder: (_, value, _) => tomato(value.clamp(0, 1)),
          );
  }
}

class _TomatoPainter extends CustomPainter {
  final double progress;
  final Color color;
  _TomatoPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final body = Path()
      ..moveTo(12, 7)
      ..cubicTo(0, 1, -1, 23, 12, 22)
      ..cubicTo(25, 23, 24, 1, 12, 7)
      ..close();
    canvas.save();
    canvas.clipPath(body);
    canvas.drawRect(
      Rect.fromLTRB(0, 23 - 19 * progress, 24, 24),
      Paint()..color = Colors.redAccent,
    );
    canvas.restore();
    canvas.drawPath(
      body,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawPath(
      Path()
        ..moveTo(8, 4)
        ..lineTo(12, 7)
        ..lineTo(16, 4)
        ..moveTo(12, 7)
        ..lineTo(12, 1),
      Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  @override
  bool shouldRepaint(_TomatoPainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
