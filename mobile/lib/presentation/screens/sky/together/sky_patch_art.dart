import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../sky/sky_tokens.dart';
import '../../../sky/sky_type.dart';
import 'sky_together_fx.dart';

@immutable
class SkyPatchStar {
  const SkyPatchStar({
    required this.id,
    required this.unit,
    required this.index,
    required this.mine,
    this.scale = 1,
    this.alpha = 1,
    this.rings,
    this.pulse = 0,
  });

  final String id;
  final Offset unit;
  final int index;
  final bool mine;
  final double scale;
  final double alpha;
  final double? rings;
  final double pulse;

  @override
  bool operator ==(Object other) =>
      other is SkyPatchStar &&
      other.id == id &&
      other.unit == unit &&
      other.index == index &&
      other.mine == mine &&
      other.scale == scale &&
      other.alpha == alpha &&
      other.rings == rings &&
      other.pulse == pulse;

  @override
  int get hashCode => Object.hash(id, unit, index, mine, scale, alpha, rings, pulse);
}

@immutable
class SkyPatchLine {
  const SkyPatchLine({required this.a, required this.b, this.grow = 1, this.alpha = 1});

  final Offset a;
  final Offset b;
  final double grow;
  final double alpha;

  @override
  bool operator ==(Object other) =>
      other is SkyPatchLine && other.a == a && other.b == b && other.grow == grow && other.alpha == alpha;

  @override
  int get hashCode => Object.hash(a, b, grow, alpha);
}

@immutable
class SkyPatchPicture {
  const SkyPatchPicture({
    required this.night,
    required this.stars,
    required this.lines,
    this.owners = true,
    this.faint = 1,
  });

  final bool night;
  final List<SkyPatchStar> stars;
  final List<SkyPatchLine> lines;
  final bool owners;
  final double faint;

  bool get isEmpty => stars.isEmpty && lines.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is SkyPatchPicture &&
      other.night == night &&
      other.owners == owners &&
      other.faint == faint &&
      listEquals(other.stars, stars) &&
      listEquals(other.lines, lines);

  @override
  int get hashCode => Object.hash(night, owners, faint, Object.hashAll(stars), Object.hashAll(lines));
}

abstract final class SkyPatchArt {
  static const Color gold = Color(0xFFFFD98A);
  static const Color cream = Color(0xFFFFE8B5);
  static const Color white = Color(0xFFFFFFFF);
  static const Color indigo = SkyTokens.indigo;
  static const Color rose = SkyTokens.roseBase;

  static Offset place(Rect frame, Offset unit) => Offset(frame.left + unit.dx * frame.width, frame.top + unit.dy * frame.height);

  static void paint(Canvas canvas, Rect frame, SkyPatchPicture picture, {required double k, double sigma = 3.2}) {
    if (picture.isEmpty || frame.isEmpty) return;
    for (final line in picture.lines) {
      final a = place(frame, line.a);
      final full = place(frame, line.b);
      final b = Offset.lerp(a, full, line.grow.clamp(0.0, 1.0))!;
      final alpha = line.alpha * picture.faint;
      if (alpha <= 0 || (b - a).distance < 0.5) continue;
      if (picture.night) {
        nightLine(canvas, a, b, k, alpha);
      } else {
        contrail(canvas, a, b, k, alpha);
      }
    }
    for (final star in picture.stars) {
      final p = place(frame, star.unit);
      final alpha = star.alpha * picture.faint;
      if (alpha <= 0) continue;
      final s = star.scale * (1 + 0.25 * math.sin(star.pulse.clamp(0.0, 1.0) * math.pi));
      if (picture.night) {
        nightStar(canvas, p, star.index, k * s, alpha, sigma);
      } else {
        puff(canvas, p, star.index, k * s, alpha);
      }
      if (picture.owners && !star.mine) {
        canvas.drawCircle(
          p,
          (picture.night ? 7.5 : 8.5) * k,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9 * k
            ..color = rose.withValues(alpha: (picture.night ? 0.6 : 0.55) * alpha),
        );
      }
      final rings = star.rings;
      if (rings != null) partnerRings(canvas, p, k, rings);
    }
  }

  static void nightStar(Canvas canvas, Offset p, int i, double k, double alpha, double sigma) {
    final r = (2.4 + ((i * 37) % 10) / 12) * k;
    canvas.drawCircle(p, r + 3.4 * k, Paint()..color = gold.withValues(alpha: 0.2 * alpha));
    final core = gold.withValues(alpha: alpha);
    final glow = Paint()
      ..color = core
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    canvas.drawCircle(p, r, glow);
    canvas.drawCircle(p, r, glow);
    canvas.drawCircle(p, r, Paint()..color = core);
  }

  static void nightLine(Canvas canvas, Offset a, Offset b, double k, double alpha) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = 4 * k
        ..strokeCap = StrokeCap.round
        ..color = gold.withValues(alpha: 0.1 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = 1 * k
        ..strokeCap = StrokeCap.round
        ..color = gold.withValues(alpha: 0.55 * alpha),
    );
  }

  static void puff(Canvas canvas, Offset p, int i, double k, double alpha) {
    canvas.drawCircle(p + Offset(0, 1 * k), 6.4 * k, Paint()..color = indigo.withValues(alpha: 0.09 * alpha));
    final soft = Paint()
      ..color = white.withValues(alpha: 0.95 * alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(((i * 47) % 360) * math.pi / 180);
    for (final (x, y, r) in const [(0.0, 0.0, 3.8), (-3.0, 1.0, 2.8), (3.0, 1.3, 2.6), (0.4, -2.7, 2.6)]) {
      canvas.drawCircle(Offset(x, y) * k, r * k, soft);
    }
    canvas.restore();
    canvas.drawCircle(p, 2.1 * k, Paint()..color = white.withValues(alpha: alpha));
  }

  static void contrail(Canvas canvas, Offset a, Offset b, double k, double alpha) {
    canvas.drawLine(
      a + Offset(0, 1.2 * k),
      b + Offset(0, 1.2 * k),
      Paint()
        ..strokeWidth = 5 * k
        ..strokeCap = StrokeCap.round
        ..color = indigo.withValues(alpha: 0.08 * alpha),
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = 6 * k
        ..strokeCap = StrokeCap.round
        ..color = white.withValues(alpha: 0.6 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    final length = (b - a).distance;
    final step = 8 * k;
    if (length > 0 && step > 0) {
      final dot = Paint()
        ..color = white.withValues(alpha: 0.36 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
      var n = 0;
      for (var s = step / 2; s < length; s += step) {
        canvas.drawCircle(Offset.lerp(a, b, s / length)!, (2.1 + (n % 3) * 0.5) * k, dot);
        n++;
      }
    }
    canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = 1.5 * k
        ..strokeCap = StrokeCap.round
        ..color = white.withValues(alpha: 0.95 * alpha),
    );
  }

  static void partnerRings(Canvas canvas, Offset p, double k, double t) {
    if (t <= 0 || t >= 1) return;
    const grow = 500 / 800;
    final g = (t / grow).clamp(0.0, 1.0);
    final fade = t <= grow ? 1.0 : 1 - (t - grow) / (1 - grow);
    canvas.drawCircle(
      p,
      (4 + 11 * g) * k,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * k
        ..color = rose.withValues(alpha: (0.6 - 0.25 * g) * fade),
    );
    canvas.drawCircle(
      p,
      22 * k,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7 * k
        ..color = rose.withValues(alpha: 0.16 * fade * g),
    );
  }

  static void finger(Canvas canvas, Offset c, double r, {required bool night}) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          r,
          night
              ? [cream.withValues(alpha: 0.42), gold.withValues(alpha: 0.14), gold.withValues(alpha: 0)]
              : [white.withValues(alpha: 0.8), white.withValues(alpha: 0.3), white.withValues(alpha: 0)],
          const [0, 0.55, 1],
        ),
    );
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = night ? gold.withValues(alpha: 0.5) : indigo.withValues(alpha: 0.22),
    );
  }

  static void dashed(Canvas canvas, Offset a, Offset b, Paint paint, double dash, double gap) {
    final length = (b - a).distance;
    if (length <= 0) return;
    final dir = (b - a) / length;
    var d = 0.0;
    while (d < length) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, length), paint);
      d += dash + gap;
    }
  }
}

class SkyPatchPainter extends CustomPainter {
  SkyPatchPainter({required this.picture, required this.frameOf, required this.k, required this.sigma})
    : super(repaint: picture);

  final ValueListenable<SkyPatchPicture> picture;
  final Rect Function(Size size) frameOf;
  final double k;
  final double sigma;

  @override
  void paint(Canvas canvas, Size size) {
    SkyPatchArt.paint(canvas, frameOf(size), picture.value, k: k, sigma: sigma);
  }

  @override
  bool shouldRepaint(SkyPatchPainter oldDelegate) =>
      oldDelegate.picture != picture || oldDelegate.k != k || oldDelegate.sigma != sigma;
}

@immutable
class SkyCometPoint {
  const SkyCometPoint(this.at, this.seconds);

  final Offset at;
  final double seconds;
}

@immutable
class SkyPatchLive {
  const SkyPatchLive({
    required this.night,
    required this.k,
    required this.motion,
    this.tail = const [],
    this.head,
    this.cometAlpha = 0,
    this.name,
    this.finger,
    this.lineFrom,
    this.lineTo,
    this.snapped = false,
    this.snapAt,
  });

  static const SkyPatchLive none = SkyPatchLive(night: true, k: 1, motion: false);

  final bool night;
  final double k;
  final bool motion;
  final List<SkyCometPoint> tail;
  final Offset? head;
  final double cometAlpha;
  final String? name;
  final Offset? finger;
  final Offset? lineFrom;
  final Offset? lineTo;
  final bool snapped;
  final Offset? snapAt;
}

class SkyPatchLivePainter extends CustomPainter {
  SkyPatchLivePainter({required this.live, required this.tokens}) : super(repaint: live);

  final ValueListenable<SkyPatchLive> live;
  final SkyTokens tokens;

  TextPainter? _tag;
  String? _tagText;
  bool? _tagNight;

  @override
  void paint(Canvas canvas, Size size) {
    final f = live.value;
    final k = f.k;
    final finger = f.finger;
    if (finger != null) SkyPatchArt.finger(canvas, finger, 34 * k, night: f.night);
    _line(canvas, f);
    _comet(canvas, size, f);
  }

  void _line(Canvas canvas, SkyPatchLive f) {
    final a = f.lineFrom;
    final b = f.lineTo;
    if (a == null || b == null) return;
    final k = f.k;
    if (f.snapped) {
      if (f.night) {
        canvas.drawLine(
          a,
          b,
          Paint()
            ..strokeWidth = 4 * k
            ..strokeCap = StrokeCap.round
            ..color = SkyPatchArt.cream.withValues(alpha: 0.16)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
        canvas.drawLine(
          a,
          b,
          Paint()
            ..strokeWidth = 1.3 * k
            ..strokeCap = StrokeCap.round
            ..color = SkyPatchArt.cream.withValues(alpha: 0.95),
        );
      } else {
        SkyPatchArt.contrail(canvas, a, b, k, 1);
      }
    } else if (f.night) {
      SkyPatchArt.dashed(
        canvas,
        a,
        b,
        Paint()
          ..strokeWidth = 1 * k
          ..strokeCap = StrokeCap.round
          ..color = SkyPatchArt.cream.withValues(alpha: 0.7),
        3 * k,
        3 * k,
      );
    } else {
      SkyPatchArt.dashed(
        canvas,
        a + Offset(0, k),
        b + Offset(0, k),
        Paint()
          ..strokeWidth = 2 * k
          ..strokeCap = StrokeCap.round
          ..color = SkyPatchArt.indigo.withValues(alpha: 0.1),
        3 * k,
        3 * k,
      );
      SkyPatchArt.dashed(
        canvas,
        a,
        b,
        Paint()
          ..strokeWidth = 2 * k
          ..strokeCap = StrokeCap.round
          ..color = SkyPatchArt.white,
        3 * k,
        3 * k,
      );
    }
    final snap = f.snapAt;
    if (snap != null) {
      canvas.drawCircle(
        snap,
        12 * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * k
          ..color = f.night ? SkyPatchArt.gold.withValues(alpha: 0.85) : SkyPatchArt.indigo.withValues(alpha: 0.4),
      );
    }
  }

  void _comet(Canvas canvas, Size size, SkyPatchLive f) {
    final head = f.head;
    final alpha = f.cometAlpha;
    if (head == null || alpha <= 0) return;
    final k = f.k;
    final points = [for (final p in f.tail) p.at];
    if (f.motion && points.length > 1) {
      for (var i = 1; i < points.length; i++) {
        final t = i / (points.length - 1);
        final a = points[i - 1];
        final b = points[i];
        if (!f.night) {
          canvas.drawLine(
            a + Offset(0, k),
            b + Offset(0, k),
            Paint()
              ..strokeWidth = (0.6 + 3.4 * t) * k
              ..strokeCap = StrokeCap.round
              ..color = SkyPatchArt.indigo.withValues(alpha: 0.07 * t * alpha),
          );
        }
        canvas.drawLine(
          a,
          b,
          Paint()
            ..strokeWidth = (0.5 + 3.6 * t) * k
            ..strokeCap = StrokeCap.round
            ..color = (f.night ? const Color(0xFFFFC9D8) : const Color(0xFFFF7FA3))
                .withValues(alpha: 0.9 * math.pow(t, 1.6).toDouble() * alpha),
        );
      }
    }
    final halo = 14 * k;
    canvas.drawCircle(
      head,
      halo,
      Paint()
        ..shader = ui.Gradient.radial(head, halo, [
          SkyPatchArt.rose.withValues(alpha: (f.night ? 0.5 : 0.38) * alpha),
          SkyPatchArt.rose.withValues(alpha: 0),
        ]),
    );
    SkyTogetherInk.glowDot(canvas, head, 3.4 * k, SkyPatchArt.white.withValues(alpha: alpha), tokens.glowSigma);
    final name = f.name;
    if (name == null || name.isEmpty) return;
    if (_tag == null || _tagText != name || _tagNight != f.night) {
      _tag?.dispose();
      _tag = TextPainter(
        text: TextSpan(
          text: name,
          style: SkyType.serif(13, weight: FontWeight.w500, height: 1.2).copyWith(
            color: tokens.hereText,
            shadows: [Shadow(color: tokens.nameShadow, offset: const Offset(0, 1), blurRadius: f.night ? 6 : 8)],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      _tagText = name;
      _tagNight = f.night;
    }
    final tag = _tag!;
    final flip = head.dx > size.width - 70 * k;
    final offset = flip ? Offset(-12 * k - tag.width, -22 * k) : Offset(12 * k, -22 * k);
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0)));
    tag.paint(canvas, head + offset);
    canvas.restore();
  }

  @override
  bool shouldRepaint(SkyPatchLivePainter oldDelegate) => oldDelegate.live != live || oldDelegate.tokens != tokens;
}
