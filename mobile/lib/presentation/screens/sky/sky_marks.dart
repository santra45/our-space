import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sky/sky.dart';

class SkyTonightStar extends StatelessWidget {
  const SkyTonightStar({super.key});

  static const double size = 28;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final mark = RepaintBoundary(
      child: CustomPaint(
        size: const Size.square(size),
        painter: _TonightStarPainter(
          glow: t.star.withValues(alpha: t.isNight ? 0.08 : 0.25),
          stroke: t.gapStroke.withValues(alpha: t.isNight ? 0.9 : 0.55),
          plus: t.gapStroke.withValues(alpha: 0.7),
        ),
      ),
    );
    return IgnorePointer(
      child: skyMotionAllowed(context) ? SkyPulse(minScale: 0.9, maxScale: 1.08, child: mark) : mark,
    );
  }
}

class _TonightStarPainter extends CustomPainter {
  const _TonightStarPainter({required this.glow, required this.stroke, required this.plus});

  final Color glow;
  final Color stroke;
  final Color plus;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, 12, Paint()..color = glow);
    final ring = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    const radius = 7.0;
    const dash = 2.2;
    const gap = 2.4;
    final circumference = 2 * math.pi * radius;
    var d = 0.0;
    while (d < circumference) {
      final start = d / radius;
      final sweep = math.min(dash, circumference - d) / radius;
      canvas.drawArc(Rect.fromCircle(center: c, radius: radius), start, sweep, false, ring);
      d += dash + gap;
    }
    final cross = Paint()
      ..color = plus
      ..strokeWidth = 1;
    canvas.drawLine(c - const Offset(0, 3.5), c + const Offset(0, 3.5), cross);
    canvas.drawLine(c - const Offset(3.5, 0), c + const Offset(3.5, 0), cross);
  }

  @override
  bool shouldRepaint(_TonightStarPainter oldDelegate) =>
      oldDelegate.glow != glow || oldDelegate.stroke != stroke || oldDelegate.plus != plus;
}

class SkyPresenceRing extends StatelessWidget {
  const SkyPresenceRing({super.key});

  static const double size = 56;

  @override
  Widget build(BuildContext context) {
    final ring = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: SkyTokens.presence.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Center(
          child: SizedBox.square(
            dimension: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: SkyTokens.presence.withValues(alpha: 0.75), width: 1.2),
              ),
            ),
          ),
        ),
      ),
    );
    return IgnorePointer(
      child: skyMotionAllowed(context) ? SkyPulse(minScale: 0.94, maxScale: 1.06, child: ring) : ring,
    );
  }
}
