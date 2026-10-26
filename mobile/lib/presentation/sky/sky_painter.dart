import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'sky_constellation.dart';
import 'sky_scene.dart';
import 'sky_tokens.dart';

class SkyTime extends ChangeNotifier {
  double _seconds = 0;
  double _burst = 1;
  double _streak = 1;

  double get seconds => _seconds;
  double get burst => _burst;
  double get streak => _streak;
  bool get still => _seconds == 0;

  void set({double? seconds, double? burst, double? streak}) {
    var changed = false;
    if (seconds != null && seconds != _seconds) {
      _seconds = seconds;
      changed = true;
    }
    if (burst != null && burst != _burst) {
      _burst = burst;
      changed = true;
    }
    if (streak != null && streak != _streak) {
      _streak = streak;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}

abstract final class SkyShapes {
  static final Path moon = () {
    final path = Path()
      ..moveTo(8.2, 5)
      ..arcToPoint(const Offset(-2, -9.4), radius: const Radius.circular(9.6), largeArc: true)
      ..arcToPoint(const Offset(8.2, 5), radius: const Radius.circular(7.4), clockwise: false)
      ..close();
    final rotation = Matrix4.rotationZ(-14 * math.pi / 180);
    return path.transform(rotation.storage);
  }();

  static const String _skyline =
      'M0 Y58 L0 Y22 L22 Y22 L28 Y14 L36 Y22 L52 Y22 C58 Y16 64 Y8 72 Y8 C80 Y8 85 Y18 92 Y18 L108 Y18 L116 Y8 L124 Y18 '
      'L142 Y18 L148 Y4 L156 Y4 L162 Y18 L178 Y18 C186 Y10 194 Y10 202 Y18 L216 Y18 L224 Y0 L232 Y18 L246 Y18 C252 Y12 '
      '260 Y4 268 Y4 C276 Y4 282 Y14 288 Y14 L304 Y14 L312 Y6 L320 Y14 L336 Y14 L344 Y0 L350 Y0 L356 Y14 L370 Y14 '
      'C376 Y10 384 Y10 390 Y16 L390 Y58 Z';

  static const List<Offset> skylineWindows = [Offset(116, 13), Offset(228, 11), Offset(312, 10), Offset(152, 12)];

  static final RegExp _token = RegExp(r'[MLCZ]|Y?-?\d+(?:\.\d+)?');

  static Path skyline(double top, {double? bottom}) {
    final tokens = [for (final m in _token.allMatches(_skyline)) m.group(0)!];
    final path = Path();
    var i = 0;
    double read() {
      final raw = tokens[i++];
      if (raw.startsWith('Y')) {
        final dy = double.parse(raw.substring(1));
        if (dy == 58 && bottom != null) return math.max(top + 58, bottom);
        return top + dy;
      }
      return double.parse(raw);
    }

    var command = 'M';
    while (i < tokens.length) {
      final token = tokens[i];
      if (token == 'M' || token == 'L' || token == 'C' || token == 'Z') {
        command = token;
        i++;
        if (command == 'Z') {
          path.close();
          continue;
        }
      }
      switch (command) {
        case 'M':
          path.moveTo(read(), read());
        case 'C':
          path.cubicTo(read(), read(), read(), read(), read(), read());
        default:
          path.lineTo(read(), read());
      }
    }
    return path;
  }

  static void cloud(Canvas canvas, SkyCloud cloud, double k) {
    final center = Offset(cloud.x, cloud.y) * k;
    final s = cloud.scale * k;
    final bounds = Rect.fromCenter(center: center, width: 160 * s, height: 80 * s);
    canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(255, 255, 255, cloud.opacity));
    final white = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawOval(Rect.fromCenter(center: center + Offset(0, 10) * s, width: 104 * s, height: 28 * s), white);
    canvas.drawCircle(center + Offset(-18, 2) * s, 16 * s, white);
    canvas.drawCircle(center + Offset(8, -6) * s, 21 * s, white);
    canvas.drawCircle(center + Offset(30, 4) * s, 13 * s, white);
    canvas.restore();
  }
}

void _glow(
  Canvas canvas,
  Offset center,
  double radius,
  Color color,
  double sigma, {
  double opacity = 1,
  int passes = 2,
}) {
  if (opacity <= 0) return;
  final paint = Paint()
    ..color = color.withValues(alpha: (color.a * opacity).clamp(0.0, 1.0))
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
  for (var i = 0; i < passes; i++) {
    canvas.drawCircle(center, radius, paint);
  }
  canvas.drawCircle(center, radius, Paint()..color = paint.color);
}

class SkyBackdropPainter extends CustomPainter {
  SkyBackdropPainter({required this.scene, required this.tokens, this.field});

  final SkyScene scene;
  final SkyTokens tokens;
  final SkyField? field;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final k = scene.scaleFor(size);
    final h = scene.designHeightFor(size);
    final rect = Offset.zero & size;
    final night = tokens.isNight;
    canvas.drawRect(rect, Paint()..shader = tokens.skyGradient.createShader(rect));

    if (scene.haze) {
      canvas.save();
      canvas.translate(200 * k, 150 * k);
      canvas.rotate(-20 * math.pi / 180);
      canvas.scale(1, 110 / 280);
      final radius = 280 * k;
      canvas.drawCircle(
        Offset.zero,
        radius,
        Paint()..shader = ui.Gradient.radial(Offset.zero, radius, [tokens.haze, tokens.haze.withValues(alpha: 0)]),
      );
      canvas.restore();
    }

    if (scene.horizonGlow) {
      final center = Offset(size.width / 2, size.height);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      final rx = size.width * 0.6;
      final ry = 160 * k;
      canvas.scale(1, ry / rx);
      canvas.drawCircle(
        Offset.zero,
        rx,
        Paint()..shader = ui.Gradient.radial(Offset.zero, rx, [tokens.horizon, tokens.horizon.withValues(alpha: 0)]),
      );
      canvas.restore();
    }

    final stars = (field ?? SkyField.build(scene, night: night, designHeight: h)).stars;

    if (night) {
      for (final star in stars) {
        if (star.twinkles) continue;
        canvas.drawCircle(
          star.position * k,
          star.radius * k,
          Paint()..color = star.color.withValues(alpha: star.opacity),
        );
      }
      final moon = scene.moon;
      if (moon != null) {
        final center = moon * k;
        final haloRadius = 46 * k;
        canvas.drawCircle(
          center,
          haloRadius,
          Paint()
            ..shader = ui.Gradient.radial(
              center,
              haloRadius,
              const [Color(0x59FFECD1), Color(0x1AFFECD1), Color(0x00FFECD1)],
              const [0, 0.45, 1],
            ),
        );
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.scale(k);
        final moonPaint = Paint()..color = const Color(0xFFFFF2DC);
        final blur = Paint()
          ..color = const Color(0xFFFFF2DC)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, tokens.glowSigma);
        canvas.drawPath(SkyShapes.moon, blur);
        canvas.drawPath(SkyShapes.moon, blur);
        canvas.drawPath(SkyShapes.moon, moonPaint);
        canvas.restore();
      }
    } else {
      if (scene.sun) {
        final at = (scene.sunAt ?? Offset(40, h - 56)) * k;
        final radius = 150 * k;
        canvas.drawCircle(
          at,
          radius,
          Paint()
            ..shader = ui.Gradient.radial(
              at,
              radius,
              const [Color(0xF2FFF6D9), Color(0x8CFFD9A8), Color(0x00FFD9A8)],
              const [0, 0.35, 1],
            ),
        );
      }
      for (final cloud in scene.clouds) {
        SkyShapes.cloud(canvas, cloud, k);
      }
      for (final star in stars) {
        if (star.twinkles) continue;
        canvas.drawCircle(
          star.position * k,
          star.radius * k,
          Paint()..color = star.color.withValues(alpha: star.opacity),
        );
      }
    }

    final skyline = scene.skyline;
    if (skyline != null) {
      canvas.save();
      canvas.scale(k);
      canvas.drawPath(
        SkyShapes.skyline(skyline, bottom: h),
        Paint()..color = tokens.skyline.withValues(alpha: tokens.skyline.a * tokens.skylineOpacity),
      );
      if (night) {
        final window = Paint()..color = tokens.window;
        for (final w in SkyShapes.skylineWindows) {
          canvas.drawRect(Rect.fromLTWH(w.dx, skyline + w.dy, 2, 2), window);
        }
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(SkyBackdropPainter oldDelegate) => oldDelegate.scene != scene || oldDelegate.tokens != tokens;
}

class SkyLivePainter extends CustomPainter {
  SkyLivePainter({required this.scene, required this.tokens, required this.time}) : super(repaint: time);

  final SkyScene scene;
  final SkyTokens tokens;
  final SkyTime time;

  SkyField? _field;
  Size? _fieldSize;
  bool? _fieldNight;

  SkyField _fieldFor(Size size) {
    if (_field == null || _fieldSize != size || _fieldNight != tokens.isNight) {
      _field = SkyField.build(scene, night: tokens.isNight, designHeight: scene.designHeightFor(size));
      _fieldSize = size;
      _fieldNight = tokens.isNight;
    }
    return _field!;
  }

  double _wave(double phase, double period) {
    if (time.still) return 1;
    return 0.5 + 0.5 * math.sin(time.seconds * 2 * math.pi / period + phase);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final k = scene.scaleFor(size);
    final field = _fieldFor(size);
    canvas.save();
    canvas.scale(k);
    for (final star in field.stars) {
      if (!star.twinkles) continue;
      final w = _wave(star.phase, star.period);
      final opacity = time.still ? star.opacity : star.opacity * (0.35 + 0.95 * w);
      canvas.drawCircle(
        star.position,
        star.radius * (time.still ? 1 : 0.85 + 0.3 * w),
        Paint()..color = star.color.withValues(alpha: opacity.clamp(0.0, 1.0)),
      );
    }
    final shooting = scene.shootingStar;
    if (shooting != null) _paintShootingStar(canvas, shooting);
    final constellation = scene.constellation;
    if (constellation != null) _paintConstellation(canvas, constellation, field);
    canvas.restore();
  }

  void _paintShootingStar(Canvas canvas, SkyShootingStar star) {
    final night = tokens.isNight;
    final progress = Curves.easeOutCubic.transform(time.streak.clamp(0.0, 1.0));
    if (progress <= 0) return;
    const steps = 24;
    final trail = Path()..moveTo(star.from.dx, star.from.dy);
    for (var i = 1; i <= steps; i++) {
      final p = star.pointAt(progress * i / steps);
      trail.lineTo(p.dx, p.dy);
    }
    final bounds = Rect.fromPoints(star.from, star.to);
    final tint = night ? const Color(0xFFFFD98A) : const Color(0xFFFFFFFF);
    canvas.drawPath(
      trail,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          bounds.topLeft,
          Offset(bounds.right, bounds.top + bounds.height * 0.35),
          [tint.withValues(alpha: 0), tint.withValues(alpha: 0.75), const Color(0xFFFFFFFF)],
          const [0, 0.7, 1],
        ),
    );
    if (!star.envelope) return;
    final at = star.pointAt(progress);
    final head = at + const Offset(-4, -9);
    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(star.angle * math.pi / 180);
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 22, 15), const Radius.circular(3));
    final paper = tokens.envelope;
    canvas.drawRRect(
      body,
      Paint()
        ..color = paper
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, tokens.glowSigma),
    );
    canvas.drawRRect(body, Paint()..color = paper);
    if (!night) {
      canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFE6E9F7),
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(1, 1.5)
        ..lineTo(11, 9)
        ..lineTo(21, 1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = const Color(0xFFC99A4A),
    );
    canvas.drawCircle(const Offset(11, 8.6), 3.2, Paint()..color = SkyTokens.roseDark);
    canvas.restore();
  }

  void _paintConstellation(Canvas canvas, SkyConstellation figure, SkyField field) {
    final night = tokens.isNight;
    final pts = figure.points;
    const n = SkyConstellation.count;
    final gap = figure.gap;
    final sigma = tokens.glowSigma;
    final burst = figure.burst && figure.complete && gap != null;
    final b = burst ? time.burst.clamp(0.0, 1.0) : 1.0;

    final layer = figure.dim < 1;
    if (layer) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, figure.dim));
    }

    final under = Paint()
      ..color = tokens.lineUnder
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final touchesGap = gap != null && (i == gap || j == gap);
      if (!figure.complete && touchesGap) continue;
      if (figure.unlit.contains(i) || figure.unlit.contains(j)) continue;
      var a = pts[i];
      var c = pts[j];
      if (burst && touchesGap && b < 1) {
        final grow = Curves.easeOutCubic.transform((b * 1.6).clamp(0.0, 1.0));
        if (i == gap) {
          a = Offset.lerp(c, a, grow)!;
        } else {
          c = Offset.lerp(a, c, grow)!;
        }
      }
      if (!night) canvas.drawLine(a, c, under);
      final width = !night ? 1.3 : (figure.complete && touchesGap ? 1.6 : 0.9);
      canvas.drawLine(
        a,
        c,
        Paint()
          ..color = tokens.line
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    if (figure.hasOpenGap && figure.gapGuide) {
      final g = pts[gap!];
      final before = pts[(gap - 1 + n) % n];
      final after = pts[(gap + 1) % n];
      final dotted = Paint()
        ..color = tokens.line.withValues(alpha: tokens.line.a * 0.55)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round;
      for (final pair in [(before, g), (g, after)]) {
        _dashedLine(canvas, pair.$1, pair.$2, dotted, dash: 1.5, gapLength: 4);
      }
    }

    for (var i = 0; i < n; i++) {
      final p = pts[i];
      if (figure.hasOpenGap && i == gap) {
        _paintGap(canvas, p, plus: figure.gapGuide);
        continue;
      }
      if (figure.unlit.contains(i)) {
        canvas.drawCircle(p, 1.3, Paint()..color = tokens.star.withValues(alpha: night ? 0.22 : 0.4));
        continue;
      }
      final big = figure.isBig(i);
      if (!night) canvas.drawCircle(p, big ? 9 : 4.6, Paint()..color = tokens.pointUnder);
      if (burst && i == gap) {
        _paintBurst(canvas, p, b, field);
        continue;
      }
      if (big) {
        final w = _wave(i * 0.9, 3.6);
        canvas.drawCircle(
          p,
          15,
          Paint()..color = tokens.star.withValues(alpha: (night ? 0.16 : 0.35) * (0.85 + 0.15 * w)),
        );
        canvas.drawCircle(p, 8, Paint()..color = tokens.star.withValues(alpha: night ? 0.32 : 0.55));
        _glow(canvas, p, 4.6, tokens.starCore, sigma);
        final cross = Paint()
          ..color = tokens.starCore.withValues(alpha: 0.85 * (0.8 + 0.2 * w))
          ..strokeWidth = 0.8;
        canvas.drawLine(p - const Offset(11, 0), p + const Offset(11, 0), cross);
        canvas.drawLine(p - const Offset(0, 11), p + const Offset(0, 11), cross);
        if (i == figure.partner && figure.presence) _paintPresence(canvas, p);
      } else {
        final r = figure.smallRadius(i);
        final w = _wave(i * 1.7, 2.6 + (i % 5) * 0.35);
        canvas.drawCircle(
          p,
          r + 2.5,
          Paint()..color = tokens.star.withValues(alpha: (night ? 0.18 : 0.35) * (time.still ? 1 : 0.6 + 0.4 * w)),
        );
        _glow(canvas, p, r, tokens.star, sigma, opacity: time.still ? 0.95 : 0.75 + 0.25 * w);
      }
    }

    if (layer) canvas.restore();
  }

  void _paintGap(Canvas canvas, Offset p, {required bool plus}) {
    final night = tokens.isNight;
    final breathe = time.still ? 1.0 : 0.85 + 0.3 * _wave(0, 2.4);
    canvas.drawCircle(p, 12 * breathe, Paint()..color = tokens.star.withValues(alpha: night ? 0.08 : 0.25));
    final stroke = Paint()
      ..color = tokens.gapStroke.withValues(alpha: night ? 0.9 : 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final ring = Path()..addOval(Rect.fromCircle(center: p, radius: 7));
    for (final metric in ring.computeMetrics()) {
      var d = time.still ? 0.0 : (time.seconds * 2.4) % 4.6;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 2.2, metric.length)), stroke);
        d += 4.6;
      }
    }
    if (!plus) return;
    final cross = Paint()
      ..color = tokens.gapStroke.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    canvas.drawLine(p - const Offset(0, 3.5), p + const Offset(0, 3.5), cross);
    canvas.drawLine(p - const Offset(3.5, 0), p + const Offset(3.5, 0), cross);
  }

  void _paintPresence(Canvas canvas, Offset p) {
    final rose = SkyTokens.presence;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = rose.withValues(alpha: 0.75)
      ..strokeWidth = 1.2;
    canvas.drawCircle(p, 20, ring);
    canvas.drawCircle(
      p,
      27,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = rose.withValues(alpha: 0.3)
        ..strokeWidth = 0.8,
    );
    if (time.still) return;
    final t = (time.seconds % 2.2) / 2.2;
    final eased = Curves.easeOutCubic.transform(t);
    canvas.drawCircle(
      p,
      20 + 16 * eased,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = rose.withValues(alpha: 0.55 * (1 - t))
        ..strokeWidth = 1.2 * (1 - 0.5 * t),
    );
  }

  void _paintBurst(Canvas canvas, Offset p, double b, SkyField field) {
    final night = tokens.isNight;
    final pop = Curves.easeOutBack.transform(b);
    final flash = b < 1 ? (1 - b) : 0.0;
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.drawCircle(
      Offset.zero,
      42 * pop,
      Paint()..color = tokens.star.withValues(alpha: (night ? 0.14 : 0.35) + 0.2 * flash),
    );
    canvas.drawCircle(
      Offset.zero,
      24 * pop,
      Paint()..color = tokens.star.withValues(alpha: (night ? 0.25 : 0.5) + 0.2 * flash),
    );
    final reach = Curves.easeOutCubic.transform((b * 1.3).clamp(0.0, 1.0));
    for (var k = 0; k < 12; k++) {
      final a = k / 12 * math.pi * 2 + (1 - reach) * 0.4;
      const r1 = 14.0;
      final r2 = k.isOdd ? 30.0 : 46.0;
      final end = r1 + (r2 - r1) * reach;
      canvas.drawLine(
        Offset(math.cos(a) * r1, math.sin(a) * r1),
        Offset(math.cos(a) * end, math.sin(a) * end),
        Paint()
          ..color = tokens.burstRay.withValues(alpha: 0.85)
          ..strokeWidth = k.isOdd ? 1 : 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
    final core = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    final coreRadius = 7 * (1 + 0.8 * flash);
    canvas.drawCircle(Offset.zero, coreRadius, core);
    canvas.drawCircle(Offset.zero, coreRadius, core);
    canvas.drawCircle(Offset.zero, coreRadius, Paint()..color = const Color(0xFFFFFFFF));
    final drift = Curves.easeOutCubic.transform(b);
    for (final s in field.sparkles) {
      canvas.drawCircle(
        s.offset * drift,
        s.radius,
        Paint()..color = tokens.sparkle.withValues(alpha: 0.9 * math.min(1, b * 2)),
      );
    }
    canvas.restore();
  }

  static void _dashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    required double dash,
    required double gapLength,
  }) {
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d += dash + gapLength;
    }
  }

  @override
  bool shouldRepaint(SkyLivePainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.tokens != tokens || oldDelegate.time != time;
}
