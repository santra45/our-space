import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../sky/sky.dart';
import '../sky_sheet_layout.dart';
import 'sky_together_copy.dart';
import 'sky_together_fx.dart';
import 'sky_together_layer.dart';

@immutable
class SkyPanHome {
  const SkyPanHome({required this.constellation, this.moonPhase});

  final SkyConstellation constellation;
  final MoonPhase? moonPhase;

  SkyThread get thread => SkyThread(
    constellation.pointAt(constellation.me),
    constellation.pointAt(constellation.partner),
    centre: constellation.bounds.center,
  );
}

abstract final class SkyPan {
  static const Duration forward = Duration(milliseconds: 1600);
  static const Duration back = Duration(milliseconds: 900);
  static const Duration calm = Duration(milliseconds: 250);
  static const double coverMs = 300;
  static const double panFrom = 300;
  static const double panMs = 1200;
  static const double patchFrom = 1300;
  static const double lineFrom = 150;
  static const double bloomMs = 700;
  static const double travel = 488;
  static const double tilt = 80;

  static double ms(double value) => value * forward.inMilliseconds;

  static double pan(double ms) => SkyMotion.standard.transform(((ms - panFrom) / panMs).clamp(0.0, 1.0));
}

class SkyTogetherRoute<T> extends PageRoute<T> {
  SkyTogetherRoute({required this.builder, required this.home, required this.motion, super.settings});

  static const String routeName = '/sky/together';

  final WidgetBuilder builder;
  final SkyPanHome home;
  final bool motion;

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => motion ? SkyPan.forward : SkyPan.calm;

  @override
  Duration get reverseTransitionDuration => motion ? SkyPan.back : SkyPan.calm;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!motion || !skyMotionAllowed(context)) return FadeTransition(opacity: animation, child: child);
    return Stack(
      fit: StackFit.expand,
      children: [
        FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0, SkyPan.coverMs / 1600, curve: Curves.easeOut),
          ),
          child: SkyPanView(animation: animation, home: home),
        ),
        FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(SkyPan.patchFrom / 1600, 1, curve: Curves.easeOut),
          ),
          child: child,
        ),
      ],
    );
  }
}

class SkyPanView extends StatelessWidget {
  const SkyPanView({super.key, required this.animation, required this.home});

  final Animation<double> animation;
  final SkyPanHome home;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final width = math.min(box.maxWidth, SkySizes.maxContentWidth);
          final k = width / SkyPageFrame.designWidth;
          final left = (box.maxWidth - width) / 2;
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final ms = SkyPan.ms(animation.value);
              final forward = animation.status != AnimationStatus.reverse;
              final pan = SkyPan.pan(ms);
              final line = forward ? ((ms - SkyPan.lineFrom) / 200).clamp(0.0, 1.0) * (1 - pan) : 0.0;
              final mid = home.thread.mid;
              return Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: SkyPanPainter(home: home, tokens: t, ms: ms, forward: forward, left: left, k: k),
                    ),
                  ),
                  if (line > 0)
                    Positioned(
                      left: left + (mid.dx - SkyPan.travel * pan) * k - 160,
                      width: 320,
                      top: (262 + SkyPan.tilt * pan) * k,
                      child: Opacity(
                        opacity: line,
                        child: Text(
                          SkyTogetherCopy.intoPatch,
                          textAlign: TextAlign.center,
                          style: SkyTogetherLine.style(t, size: 20),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class SkyPanPainter extends CustomPainter {
  SkyPanPainter({
    required this.home,
    required this.tokens,
    required this.ms,
    required this.forward,
    required this.left,
    required this.k,
  });

  static final SkyTime _still = SkyTime();

  final SkyPanHome home;
  final SkyTokens tokens;
  final double ms;
  final bool forward;
  final double left;
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || k <= 0) return;
    final night = tokens.isNight;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = tokens.skyGradient.createShader(rect));
    final h = size.height / k;
    final pan = SkyPan.pan(ms);
    final dx = -SkyPan.travel * pan;
    final dy = SkyPan.tilt * pan;
    canvas.save();
    canvas.translate(left, 0);
    canvas.scale(k);

    final scene = SkyScene.home.copyWith(moonPhase: home.moonPhase);
    final field = SkyField.build(scene, night: night, designHeight: h);
    canvas.save();
    canvas.translate(dx * 0.5, dy * 0.5);
    if (!night) {
      for (final cloud in scene.clouds) {
        SkyShapes.cloud(canvas, cloud, 1);
      }
    }
    for (final star in field.stars) {
      canvas.drawCircle(star.position, star.radius, Paint()..color = star.color.withValues(alpha: star.opacity));
    }
    canvas.restore();

    final fade = 1 - pan;
    if (fade > 0) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, fade));
      canvas.translate(dx * 0.2, dy * 0.2);
      if (night) {
        SkyShapes.moon(canvas, SkyTogetherSpot.moon, 1, home.moonPhase ?? MoonPhase.resting, tokens.glowSigma);
      } else {
        SkyTogetherInk.sunDisc(canvas, SkyTogetherSpot.sun);
      }
      canvas.restore();
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, fade));
      canvas.translate(dx, dy);
      canvas.drawPath(
        SkyShapes.skyline(scene.skyline ?? 416, bottom: h),
        Paint()..color = tokens.skyline.withValues(alpha: tokens.skyline.a * tokens.skylineOpacity),
      );
      canvas.restore();
    }

    canvas.save();
    canvas.translate(dx, dy);
    SkyLivePainter(
      scene: SkyScene(
        stars: 0,
        dayStars: 0,
        sun: false,
        clouds: const [],
        haze: false,
        twinkle: false,
        constellation: home.constellation,
      ),
      tokens: tokens,
      time: _still,
    ).paint(canvas, Size(SkyPageFrame.designWidth, h));
    if (forward) {
      final thread = home.thread;
      SkyTogetherInk.thread(canvas, thread, night: night, level: 1, bright: true);
      _burst(canvas, thread.mid, night);
    }
    canvas.restore();
    canvas.restore();
  }

  void _burst(Canvas canvas, Offset c, bool night) {
    final bloom = (ms / SkyPan.bloomMs).clamp(0.0, 1.0);
    if (bloom < 1) {
      final r = 120 * Curves.easeOutCubic.transform(bloom);
      final a = 1 - bloom;
      if (r > 0) {
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = ui.Gradient.radial(
              c,
              r,
              night
                  ? [
                      const Color(0xFFFFF4D6).withValues(alpha: 0.85 * a),
                      const Color(0xFFFFD98A).withValues(alpha: 0.3 * a),
                      const Color(0x00FFD98A),
                    ]
                  : [
                      SkyTogetherInk.white.withValues(alpha: 0.95 * a),
                      SkyTogetherInk.white.withValues(alpha: 0.5 * a),
                      SkyTogetherInk.white.withValues(alpha: 0),
                    ],
              const [0, 0.4, 1],
            ),
        );
      }
    }
    final b = (ms / SkyMotion.burst.inMilliseconds).clamp(0.0, 1.0);
    if (b >= 1) return;
    final reach = Curves.easeOutCubic.transform((b * 1.3).clamp(0.0, 1.0));
    final flash = 1 - b;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * math.pi * 2 + (1 - reach) * 0.4;
      const r1 = 12.0;
      final r2 = i.isOdd ? 28.0 : 44.0;
      final end = r1 + (r2 - r1) * reach;
      canvas.drawLine(
        Offset(math.cos(a) * r1, math.sin(a) * r1),
        Offset(math.cos(a) * end, math.sin(a) * end),
        Paint()
          ..color = tokens.burstRay.withValues(alpha: 0.9 * flash)
          ..strokeWidth = i.isOdd ? 1 : 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
    final core = Paint()
      ..color = SkyTogetherInk.white.withValues(alpha: flash)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2);
    final radius = 7 * (1 + 0.8 * flash);
    canvas.drawCircle(Offset.zero, radius, core);
    canvas.drawCircle(Offset.zero, radius, core);
    canvas.drawCircle(Offset.zero, radius * 0.6, Paint()..color = SkyTogetherInk.white.withValues(alpha: flash));
    canvas.restore();
  }

  @override
  bool shouldRepaint(SkyPanPainter oldDelegate) =>
      oldDelegate.ms != ms ||
      oldDelegate.forward != forward ||
      oldDelegate.home != home ||
      oldDelegate.tokens != tokens ||
      oldDelegate.left != left ||
      oldDelegate.k != k;
}
