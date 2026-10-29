import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../sky/sky_moon.dart';
import '../../../sky/sky_painter.dart';
import '../../../sky/sky_tokens.dart';

abstract final class SkyTogetherSpot {
  static const Offset moon = Offset(306, 134);
  static const Offset sun = Offset(278, 112);
  static const double hit = 32;
  static const double lineMin = 18;
  static const double lineMax = 372;
  static const Offset cloudRest = Offset(60, -6);
  static const double cloudScale = 0.36;

  static Offset body(bool night) => night ? moon : sun;

  static double ring(bool night) => night ? 22 : 25;

  static const double lineColumn = 180;
  static const double lineGap = 12;
  static const double lineClear = 4;
  static const double lineNarrowest = 140;

  static double lineTop(bool night) => night ? 162 : 148;

  static bool crowded(double? topBarBottom, {required bool night}) =>
      topBarBottom != null && topBarBottom + lineClear > lineTop(night);

  static double lineStart({double? topBarBottom, double? titleEdge, required bool night}) {
    if (!crowded(topBarBottom, night: night)) return lineMin;
    final edge = titleEdge == null ? lineColumn : titleEdge + lineGap;
    return edge.clamp(lineMin, lineMax - lineNarrowest).toDouble();
  }

  static int lineLines(double start) => start > lineMin ? 3 : 2;

  static double lineRoom(double start) => lineMax - start;

  static Rect lineRect(Size text, {required bool night, double start = lineMin}) {
    final b = body(night);
    final left = (b.dx - text.width / 2).clamp(start, math.max(start, lineMax - text.width)).toDouble();
    return Rect.fromLTWH(left, lineTop(night), text.width, text.height);
  }
}

double skyBeatEnvelope(int since) {
  if (since < 0) return 0;
  double lub = 0;
  if (since < 90) {
    lub = since / 90;
  } else if (since < 350) {
    lub = 1 - (since - 90) / 260;
  }
  double dub = 0;
  if (since >= 180 && since < 260) {
    dub = 0.55 * (since - 180) / 80;
  } else if (since >= 260 && since < 600) {
    dub = 0.55 * (1 - (since - 260) / 340);
  }
  return math.max(lub, dub).clamp(0.0, 1.0);
}

@immutable
class SkyThread {
  factory SkyThread(Offset from, Offset to, {required Offset centre, double lift = 0.4}) {
    final mid = (from + to) / 2;
    final d = to - from;
    final length = d.distance;
    var normal = length == 0 ? const Offset(0, -1) : Offset(-d.dy / length, d.dx / length);
    final away = mid - centre;
    if (away.distanceSquared < 1e-6) {
      if (normal.dy > 0) normal = -normal;
    } else if (normal.dx * away.dx + normal.dy * away.dy < 0) {
      normal = -normal;
    }
    return SkyThread._(from, to, mid + normal * (lift * length));
  }

  const SkyThread._(this.from, this.to, this.control);

  final Offset from;
  final Offset to;
  final Offset control;

  Offset at(double t) {
    final u = 1 - t;
    return from * (u * u) + control * (2 * u * t) + to * (t * t);
  }

  Offset get mid => at(0.5);

  Path path(double t0, double t1, {int steps = 28}) {
    final path = Path();
    final start = at(t0);
    path.moveTo(start.dx, start.dy);
    for (var i = 1; i <= steps; i++) {
      final p = at(t0 + (t1 - t0) * i / steps);
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  @override
  bool operator ==(Object other) =>
      other is SkyThread && other.from == from && other.to == to && other.control == control;

  @override
  int get hashCode => Object.hash(from, to, control);
}

@immutable
class SkyTogetherPaint {
  const SkyTogetherPaint({
    required this.night,
    required this.motion,
    required this.seconds,
    required this.body,
    required this.me,
    required this.partner,
    required this.thread,
    this.moonPhase,
    this.presence = 0,
    this.cloudShift = Offset.zero,
    this.sun = 0,
    this.sunScale = 1,
    this.hint = 0,
    this.track = 0,
    this.arc = 0,
    this.hot = 0,
    this.bodyScale = 1,
    this.finger = 0,
    this.myRing = 0,
    this.partnerRing = 0,
    this.threadLevel = 0,
    this.threadAlpha = 0,
    this.bright = false,
    this.beat = 0,
    this.sinceLub,
  });

  final bool night;
  final bool motion;
  final double seconds;
  final Offset body;
  final Offset me;
  final Offset partner;
  final SkyThread thread;
  final MoonPhase? moonPhase;
  final double presence;
  final Offset cloudShift;
  final double sun;
  final double sunScale;
  final double hint;
  final double track;
  final double arc;
  final double hot;
  final double bodyScale;
  final double finger;
  final double myRing;
  final double partnerRing;
  final double threadLevel;
  final double threadAlpha;
  final bool bright;
  final double beat;
  final int? sinceLub;

  bool get blank =>
      presence <= 0 &&
      sun <= 0 &&
      hint <= 0 &&
      track <= 0 &&
      hot <= 0 &&
      finger <= 0 &&
      myRing <= 0 &&
      partnerRing <= 0 &&
      (threadLevel <= 0 || threadAlpha <= 0);
}

abstract final class SkyTogetherInk {
  static const Color gold = Color(0xFFFFD98A);
  static const Color goldDay = Color(0xFFE8B04B);
  static const Color cream = Color(0xFFFFE8B5);
  static const Color white = Color(0xFFFFFFFF);
  static const Color indigo = SkyTokens.indigo;
  static const Color rose = SkyTokens.roseBase;
  static const Color moonHot = Color(0xFFFFECD1);
  static const Color sunHalo = Color(0xFFFFF8E2);
  static const Color sunWarm = Color(0xFFFFE7B0);
  static const Color sunCore = Color(0xFFFFF8E4);
  static const Color sunEdge = Color(0xFFFFE6AE);
  static const Color threadNight = Color(0xFFFFF8E7);
  static const Color threadDay = Color(0xFFFFD38A);
  static const Color twinkleCore = Color(0xFFFFF4D6);

  static Paint glow(Color color, double sigma) => Paint()
    ..color = color
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);

  static void glowDot(Canvas canvas, Offset at, double radius, Color color, double sigma) {
    final soft = glow(color, sigma);
    canvas.drawCircle(at, radius, soft);
    canvas.drawCircle(at, radius, Paint()..color = color);
  }

  static void dashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    double dash = 2.2,
    double gap = 2.6,
    double phase = 0,
  }) {
    final ring = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    for (final metric in ring.computeMetrics()) {
      var d = phase % (dash + gap) - (dash + gap);
      while (d < metric.length) {
        final start = math.max(0.0, d);
        final end = math.min(metric.length, d + dash);
        if (end > start) canvas.drawPath(metric.extractPath(start, end), paint);
        d += dash + gap;
      }
    }
  }

  static void cloud(Canvas canvas, Offset center, double s, Paint paint) {
    canvas.drawOval(Rect.fromCenter(center: center + Offset(0, 10) * s, width: 104 * s, height: 28 * s), paint);
    canvas.drawCircle(center + Offset(-18, 2) * s, 16 * s, paint);
    canvas.drawCircle(center + Offset(8, -6) * s, 21 * s, paint);
    canvas.drawCircle(center + Offset(30, 4) * s, 13 * s, paint);
  }

  static void sunDisc(Canvas canvas, Offset c, {double alpha = 1, double scale = 1, double halo = 1}) {
    if (alpha <= 0) return;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(scale);
    final r = 44 * halo;
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          r,
          [
            sunHalo.withValues(alpha: 0.95 * alpha),
            sunWarm.withValues(alpha: 0.45 * alpha),
            sunWarm.withValues(alpha: 0),
          ],
          const [0, 0.4, 1],
        ),
    );
    final ray = Paint()
      ..color = white.withValues(alpha: 0.85 * alpha)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final a = math.pi / 8 + i * math.pi / 4;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(dir * 17, dir * 22.5, ray);
    }
    canvas.drawCircle(Offset.zero, 12.5, glow(sunWarm.withValues(alpha: 0.6 * alpha), 2));
    canvas.drawCircle(
      Offset.zero,
      11.5,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          11.5,
          [white.withValues(alpha: alpha), sunCore.withValues(alpha: alpha), sunEdge.withValues(alpha: alpha)],
          const [0, 0.6, 1],
        ),
    );
    canvas.restore();
  }

  static void thread(
    Canvas canvas,
    SkyThread thread, {
    required bool night,
    required double level,
    double alpha = 1,
    bool bright = false,
    int? sinceLub,
  }) {
    if (level <= 0 || alpha <= 0) return;
    final p = level.clamp(0.0, 1.0);
    final whole = p >= 1;
    final parts = whole ? [(0.0, 1.0)] : [(0.0, p / 2), (1 - p / 2, 1.0)];
    final glowColor = night ? gold : threadDay;
    final coreColor = night ? threadNight : white;
    for (final (t0, t1) in parts) {
      final path = thread.path(t0, t1);
      if (!night) {
        canvas.save();
        canvas.translate(0, 1.2);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.6
            ..strokeCap = StrokeCap.round
            ..color = indigo.withValues(alpha: 0.16 * alpha),
        );
        canvas.restore();
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = bright ? 10 : 7
          ..strokeCap = StrokeCap.round
          ..color = glowColor.withValues(alpha: (bright ? 0.7 : (night ? 0.42 : 0.75)) * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = bright ? 2.4 : 1.8
          ..strokeCap = StrokeCap.round
          ..color = coreColor.withValues(alpha: alpha),
      );
    }
    if (!whole && sinceLub != null && sinceLub < 300) {
      final run = sinceLub / 300;
      final half = p / 2;
      final length = (thread.to - thread.from).distance * 1.15;
      final span = length <= 0 ? 0.0 : 14 / length;
      final shimmer = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = white.withValues(alpha: 0.3 * alpha);
      final headA = half * run;
      canvas.drawPath(thread.path(math.max(0, headA - span), headA, steps: 6), shimmer);
      final headB = 1 - half * run;
      canvas.drawPath(thread.path(headB, math.min(1, headB + span), steps: 6), shimmer);
    }
    if (!whole) {
      for (final h in [thread.at(p / 2), thread.at(1 - p / 2)]) {
        canvas.drawCircle(h, 9, glow(glowColor.withValues(alpha: (night ? 0.45 : 0.9) * alpha), 3.2));
        glowDot(canvas, h, 2.6, white.withValues(alpha: alpha), night ? 3.2 : 2.2);
      }
    }
  }
}

class SkyTogetherFxPainter extends CustomPainter {
  SkyTogetherFxPainter({required this.frame, required this.tokens, this.designWidth = 390}) : super(repaint: frame);

  final ValueListenable<SkyTogetherPaint?> frame;
  final SkyTokens tokens;
  final double designWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame.value;
    if (f == null || f.blank || size.isEmpty) return;
    final k = size.width / designWidth;
    canvas.save();
    canvas.scale(k);
    _presence(canvas, f);
    _body(canvas, f);
    _rings(canvas, f);
    SkyTogetherInk.thread(
      canvas,
      f.thread,
      night: f.night,
      level: f.threadLevel,
      alpha: f.threadAlpha,
      bright: f.bright,
      sinceLub: f.sinceLub,
    );
    canvas.restore();
  }

  void _presence(Canvas canvas, SkyTogetherPaint f) {
    if (f.presence <= 0) return;
    if (f.night) {
      _twinkle(canvas, f);
    } else {
      _cloud(canvas, f);
    }
  }

  void _twinkle(Canvas canvas, SkyTogetherPaint f) {
    final a = f.presence;
    final w = f.motion ? 0.5 + 0.5 * math.sin(f.seconds * 2 * math.pi / 1.6) : 0.0;
    final scale = f.motion ? 0.7 + 0.45 * w : 0.9;
    final diag = f.motion ? 0.25 + 0.45 * w : 0.5;
    final halo = f.motion ? 0.6 + 0.4 * w : 0.8;
    final p = f.partner;
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.drawCircle(
      Offset.zero,
      26,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          26,
          [
            SkyTogetherInk.white.withValues(alpha: 0.45 * halo * a),
            SkyTogetherInk.cream.withValues(alpha: 0.14 * halo * a),
            SkyTogetherInk.cream.withValues(alpha: 0),
          ],
          const [0, 0.45, 1],
        ),
    );
    canvas.save();
    canvas.scale(scale);
    final spike = Path()
      ..moveTo(0, -20)
      ..lineTo(1.4, -1.4)
      ..lineTo(18, 0)
      ..lineTo(1.4, 1.4)
      ..lineTo(0, 20)
      ..lineTo(-1.4, 1.4)
      ..lineTo(-18, 0)
      ..lineTo(-1.4, -1.4)
      ..close();
    final spikeColor = SkyTogetherInk.white.withValues(alpha: 0.95 * a);
    canvas.drawPath(spike, SkyTogetherInk.glow(spikeColor, tokens.glowSigma));
    canvas.drawPath(spike, Paint()..color = spikeColor);
    canvas.rotate(math.pi / 4);
    final small = Path()
      ..moveTo(0, -9)
      ..lineTo(0.9, -0.9)
      ..lineTo(9, 0)
      ..lineTo(0.9, 0.9)
      ..lineTo(0, 9)
      ..lineTo(-0.9, 0.9)
      ..lineTo(-9, 0)
      ..lineTo(-0.9, -0.9)
      ..close();
    canvas.drawPath(small, Paint()..color = SkyTogetherInk.twinkleCore.withValues(alpha: diag * a));
    canvas.restore();
    SkyTogetherInk.glowDot(canvas, Offset.zero, 5.2, SkyTogetherInk.white.withValues(alpha: a), tokens.glowSigma);
    canvas.restore();
  }

  void _cloud(Canvas canvas, SkyTogetherPaint f) {
    final a = f.presence;
    final sway = f.motion
        ? Offset(8 * math.sin(f.seconds * 2 * math.pi / 8), 2 * math.sin(f.seconds * 2 * math.pi / 4.5))
        : Offset.zero;
    final center = f.partner + SkyTogetherSpot.cloudRest + f.cloudShift + sway;
    const s = SkyTogetherSpot.cloudScale;
    SkyTogetherInk.cloud(
      canvas,
      center + const Offset(0, 3.2),
      s,
      SkyTogetherInk.glow(SkyTogetherInk.rose.withValues(alpha: 0.26 * a), 1),
    );
    SkyTogetherInk.cloud(canvas, center, s, Paint()..color = SkyTogetherInk.white.withValues(alpha: 0.97 * a));
  }

  void _body(Canvas canvas, SkyTogetherPaint f) {
    final c = f.body;
    final r = SkyTogetherSpot.ring(f.night);
    final ink = f.night ? SkyTogetherInk.gold : SkyTogetherInk.indigo;
    if (f.night && f.hot > 0) {
      final radius = 46 * f.bodyScale;
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(
            c,
            radius,
            [
              SkyTogetherInk.moonHot.withValues(alpha: 0.6 * f.hot),
              SkyTogetherInk.moonHot.withValues(alpha: 0.2 * f.hot),
              SkyTogetherInk.moonHot.withValues(alpha: 0),
            ],
            const [0, 0.4, 1],
          ),
      );
      final phase = f.moonPhase;
      if (phase != null) SkyShapes.moon(canvas, c, 1, phase, tokens.glowSigma);
    }
    if (!f.night && f.sun > 0) {
      SkyTogetherInk.sunDisc(canvas, c, alpha: f.sun, scale: f.sunScale, halo: f.bodyScale);
    }
    if (f.hint > 0) {
      canvas.drawCircle(
        c,
        r + 5,
        Paint()
          ..color = (f.night ? SkyTogetherInk.gold : SkyTogetherInk.white).withValues(alpha: (f.night ? 0.05 : 0.16) * f.hint),
      );
      SkyTogetherInk.dashedCircle(
        canvas,
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..color = ink.withValues(alpha: (f.night ? 0.8 : 0.42) * f.hint),
        phase: f.motion ? f.seconds * 2.4 : 0,
      );
    }
    if (f.track > 0) {
      canvas.drawCircle(
        c,
        r + 5,
        Paint()..color = (f.night ? SkyTogetherInk.gold : SkyTogetherInk.white).withValues(alpha: (f.night ? 0.07 : 0.2) * f.track),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = ink.withValues(alpha: (f.night ? 0.22 : 0.16) * f.track),
      );
      _arc(canvas, f, c, r);
    }
    if (f.finger > 0) _finger(canvas, c, 32, night: f.night, alpha: f.finger);
    if (f.sinceLub != null && f.motion && f.track > 0) {
      final t = (f.sinceLub! / 900).clamp(0.0, 1.0);
      if (t < 1) {
        final eased = Curves.easeOutCubic.transform(t);
        canvas.drawCircle(
          c,
          r + 10 + 11 * eased,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1
            ..color = (f.night ? SkyTogetherInk.gold : SkyTogetherInk.white).withValues(alpha: (f.night ? 0.42 : 0.75) * (1 - t)),
        );
      }
    }
  }

  void _arc(Canvas canvas, SkyTogetherPaint f, Offset c, double r) {
    final p = f.arc.clamp(0.0, 1.0);
    if (p <= 0) return;
    final ink = (f.night ? SkyTogetherInk.gold : SkyTogetherInk.goldDay).withValues(alpha: f.track);
    final rect = Rect.fromCircle(center: c, radius: r);
    final sigma = tokens.glowSigma;
    if (p >= 1) {
      final full = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = ink;
      canvas.drawCircle(c, r, Paint.from(full)..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma));
      canvas.drawCircle(c, r, full);
      return;
    }
    final sweep = p * math.pi * 2;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = ink;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, Paint.from(arc)..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma));
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
    final a = -math.pi / 2 + sweep;
    SkyTogetherInk.glowDot(
      canvas,
      c + Offset(math.cos(a), math.sin(a)) * r,
      2.4,
      SkyTogetherInk.white.withValues(alpha: f.track),
      sigma,
    );
  }

  static void _finger(Canvas canvas, Offset c, double r, {required bool night, required double alpha}) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          r,
          night
              ? [
                  SkyTogetherInk.cream.withValues(alpha: 0.42 * alpha),
                  SkyTogetherInk.gold.withValues(alpha: 0.14 * alpha),
                  SkyTogetherInk.gold.withValues(alpha: 0),
                ]
              : [
                  SkyTogetherInk.white.withValues(alpha: 0.8 * alpha),
                  SkyTogetherInk.white.withValues(alpha: 0.3 * alpha),
                  SkyTogetherInk.white.withValues(alpha: 0),
                ],
          const [0, 0.55, 1],
        ),
    );
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = (night ? SkyTogetherInk.gold : SkyTogetherInk.indigo).withValues(alpha: (night ? 0.5 : 0.22) * alpha),
    );
  }

  void _rings(Canvas canvas, SkyTogetherPaint f) {
    if (f.beat > 0 && f.motion && f.threadLevel > 0) {
      final glow = (f.night ? SkyTogetherInk.gold : SkyTogetherInk.white).withValues(alpha: (f.night ? 0.22 : 0.4) * f.beat);
      for (final star in [f.me, f.partner]) {
        canvas.drawCircle(star, 15 * (1 + 0.18 * f.beat), Paint()..color = glow.withValues(alpha: glow.a * 0.6));
        canvas.drawCircle(star, 8 * (1 + 0.18 * f.beat), Paint()..color = glow);
      }
    }
    _holding(canvas, f, f.me, f.myRing);
    _holding(canvas, f, f.partner, f.partnerRing);
  }

  void _holding(Canvas canvas, SkyTogetherPaint f, Offset p, double alpha) {
    if (alpha <= 0) return;
    if (!f.night) {
      canvas.drawCircle(
        p,
        20,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..color = SkyTogetherInk.indigo.withValues(alpha: 0.16 * alpha),
      );
    }
    final ink = f.night ? SkyTogetherInk.gold : SkyTogetherInk.white;
    canvas.drawCircle(
      p,
      20,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = ink.withValues(alpha: (f.night ? 0.85 : 1) * alpha),
    );
    final since = f.sinceLub;
    if (since == null || !f.motion) return;
    for (var i = 0; i < 2; i++) {
      final t = ((since - i * 150) / 900).clamp(0.0, 1.0);
      if (t <= 0 || t >= 1) continue;
      final eased = Curves.easeOutCubic.transform(t);
      final base = f.night ? (i == 0 ? 0.40 : 0.16) : (i == 0 ? 0.80 : 0.40);
      canvas.drawCircle(
        p,
        20 + 18 * eased,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 1 : 0.7
          ..color = ink.withValues(alpha: base * (1 - t) * alpha),
      );
    }
  }

  @override
  bool shouldRepaint(SkyTogetherFxPainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.tokens != tokens || oldDelegate.designWidth != designWidth;
}
