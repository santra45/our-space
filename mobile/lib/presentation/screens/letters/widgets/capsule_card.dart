import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../sky/sky.dart';
import '../letters_copy.dart';

class CapsuleCard extends StatelessWidget {
  const CapsuleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.opens,
    required this.progress,
    this.onTap,
    this.onMore,
  });

  final String title;
  final String subtitle;
  final String opens;
  final double progress;
  final VoidCallback? onTap;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return SkyPressable(
      onTap: onTap,
      onLongPress: onMore,
      pressedScale: 0.98,
      semanticLabel: title,
      child: SkyCard(
        child: Row(
          children: [
            MoonRing(progress: progress),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SkyType.serif(17, weight: FontWeight.w500, height: 1.25).copyWith(color: t.text),
                  ),
                  const SizedBox(height: SkySpace.xxs),
                  Text(subtitle, style: SkyType.sans(12, height: 1.4).copyWith(color: t.muted)),
                  const SizedBox(height: SkySpace.sm),
                  SkyChip(label: opens, icon: SkyIcons.lock, dense: true),
                ],
              ),
            ),
            if (onMore != null) ...[
              const SizedBox(width: SkySpace.sm),
              SkyIconButton(
                icon: SkyIcons.dots,
                tone: SkyIconButtonTone.ghost,
                size: 32,
                iconSize: 16,
                semanticLabel: LettersCopy.moreFor,
                onPressed: onMore,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MoonRing extends StatelessWidget {
  const MoonRing({super.key, required this.progress, this.size = 62});

  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final target = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: skyMotionAllowed(context) ? 0 : target, end: target),
        duration: skyMotionAllowed(context) ? const Duration(milliseconds: 700) : Duration.zero,
        curve: SkyMotion.standard,
        builder: (context, value, child) => CustomPaint(
          painter: MoonRingPainter(progress: value, track: t.toggleOff, arc: t.gold),
          child: child,
        ),
        child: Center(child: SkyIcon(SkyIcons.moon, size: size * 24 / 62, color: t.gold)),
      ),
    );
  }
}

class MoonRingPainter extends CustomPainter {
  const MoonRingPainter({required this.progress, required this.track, required this.arc});

  final double progress;
  final Color track;
  final Color arc;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 28 / 62;
    final stroke = size.shortestSide * 3 / 62;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..color = arc
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant MoonRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.track != track || oldDelegate.arc != arc;
}
