import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../sky/sky.dart';
import '../../../widgets/app_haptics.dart';

abstract final class LoveShapes {
  static final Path heart = Path()
    ..moveTo(12, 20.5)
    ..lineTo(10.7, 19.3)
    ..cubicTo(5.6, 14.6, 2.5, 11.8, 2.5, 8.4)
    ..arcToPoint(const Offset(7.4, 3.5), radius: const Radius.circular(4.9))
    ..cubicTo(9.1, 3.5, 10.8, 4.3, 12, 5.6)
    ..cubicTo(13.2, 4.3, 14.9, 3.5, 16.6, 3.5)
    ..arcToPoint(const Offset(21.5, 8.4), radius: const Radius.circular(4.9))
    ..cubicTo(21.5, 11.8, 18.4, 14.6, 13.3, 19.3)
    ..close();
}

@immutable
class LoveFloat {
  const LoveFloat(this.x, this.y, this.size, this.turn, this.opacity, this.phase);

  final double x;
  final double y;
  final double size;
  final double turn;
  final double opacity;
  final double phase;
}

@immutable
class LoveSpark {
  const LoveSpark({
    required this.angle,
    required this.distance,
    required this.size,
    required this.heart,
    required this.tone,
    required this.spin,
  });

  final double angle;
  final double distance;
  final double size;
  final bool heart;
  final int tone;
  final double spin;
}

class LoveHeart extends StatefulWidget {
  const LoveHeart({
    super.key,
    required this.semanticLabel,
    this.semanticHint,
    this.enabled = true,
    this.onHoldStart,
    this.onHoldCancel,
    this.onHint,
    this.onSend,
  });

  static const Duration holdDuration = Duration(milliseconds: 900);
  static const double box = 250;
  static const double width = box;
  static const double height = 240;
  static const double target = 170;
  static const double coreRadius = 64;

  static const List<(double, double)> rings = [(85, 0.35), (101, 0.18), (117, 0.08)];

  static const List<LoveFloat> floats = [
    LoveFloat(30, 70, 14, -18, 0.8, 0),
    LoveFloat(212, 52, 11, 14, 0.7, 0.27),
    LoveFloat(222, 168, 16, 20, 0.6, 0.55),
    LoveFloat(26, 186, 10, -10, 0.55, 0.8),
    LoveFloat(120, 6, 9, 0, 0.5, 0.4),
  ];

  static final List<LoveSpark> sparks = List<LoveSpark>.unmodifiable([
    for (var i = 0; i < 26; i++)
      LoveSpark(
        angle: i * 2 * math.pi / 26 + (i.isEven ? 0.07 : -0.1),
        distance: 70.0 + (i * 37) % 64,
        size: i % 3 == 0 ? 10.0 + (i % 4) : 2.2 + (i % 5) * 0.35,
        heart: i % 3 == 0,
        tone: i % 4,
        spin: i.isEven ? 1.4 : -1.2,
      ),
  ]);

  final String semanticLabel;
  final String? semanticHint;
  final bool enabled;
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldCancel;
  final VoidCallback? onHint;
  final VoidCallback? onSend;

  @override
  State<LoveHeart> createState() => _LoveHeartState();
}

class _LoveHeartState extends State<LoveHeart> with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(vsync: this, duration: SkyMotion.twinkle);
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: LoveHeart.holdDuration,
    animationBehavior: AnimationBehavior.preserve,
  )..addStatusListener(_onHold);
  late final AnimationController _press = AnimationController.unbounded(vsync: this);
  late final AnimationController _burst = AnimationController(vsync: this, duration: SkyMotion.burst);
  late final AnimationController _nudge = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  bool? _motion;
  int? _pointer;
  Offset _origin = Offset.zero;

  bool get _live => _motion ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = skyMotionAllowed(context);
    if (motion == _motion) return;
    _motion = motion;
    if (motion) {
      _idle.repeat();
    } else {
      _idle
        ..stop()
        ..value = 0;
      _burst
        ..stop()
        ..value = 0;
      _nudge
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant LoveHeart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pointer != null) _letGo(hint: false, report: false);
  }

  @override
  void dispose() {
    _idle.dispose();
    _hold.dispose();
    _press.dispose();
    _burst.dispose();
    _nudge.dispose();
    super.dispose();
  }

  void _onHold(AnimationStatus status) {
    if (status != AnimationStatus.completed || _pointer == null) return;
    _pointer = null;
    _releasePress();
    _fire();
  }

  void _fire() {
    if (_live) {
      _hold.animateBack(0, duration: SkyMotion.medium, curve: Curves.easeOut);
      _burst.forward(from: 0);
    } else {
      _hold.value = 0;
    }
    widget.onSend?.call();
  }

  void _accessibleSend() {
    if (!widget.enabled || _pointer != null) return;
    _fire();
  }

  void _pressDown() {
    if (_live) {
      _press.animateTo(1, duration: SkyMotion.instant, curve: Curves.easeOut);
    } else {
      _press.value = 1;
    }
  }

  void _releasePress() {
    if (_live) {
      _press.animateWith(SpringSimulation(SkyMotion.pressSpring, _press.value, 0, _press.velocity));
    } else {
      _press.value = 0;
    }
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    if (event.kind == PointerDeviceKind.mouse && event.buttons != kPrimaryButton) return;
    _pointer = event.pointer;
    _origin = event.position;
    _nudge
      ..stop()
      ..value = 0;
    AppHaptics.tick();
    _pressDown();
    widget.onHoldStart?.call();
    _hold.forward();
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    if ((event.position - _origin).distance > kTouchSlop) _letGo(hint: false);
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _letGo(hint: true);
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _letGo(hint: false);
  }

  void _letGo({required bool hint, bool report = true}) {
    _pointer = null;
    _releasePress();
    if (_live) {
      _hold.animateBack(0, duration: SkyMotion.base, curve: Curves.easeOut);
    } else {
      _hold.value = 0;
    }
    if (!report) return;
    if (hint) {
      if (_live) _nudge.forward(from: 0);
      widget.onHint?.call();
    } else {
      widget.onHoldCancel?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    const inset = (LoveHeart.box - LoveHeart.target) / 2;
    return SizedBox(
      width: LoveHeart.width,
      height: LoveHeart.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: LoveHeart.box,
            height: LoveHeart.box,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: LoveHeartPainter(
                    tokens: context.sky,
                    live: _live,
                    idle: _idle,
                    hold: _hold,
                    press: _press,
                    burst: _burst,
                    nudge: _nudge,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: inset,
            top: inset,
            width: LoveHeart.target,
            height: LoveHeart.target,
            child: Semantics(
              container: true,
              button: true,
              enabled: widget.enabled,
              label: widget.semanticLabel,
              hint: widget.semanticHint,
              onTap: widget.enabled ? _accessibleSend : null,
              onLongPress: widget.enabled ? _accessibleSend : null,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _cancel,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoveHeartPainter extends CustomPainter {
  LoveHeartPainter({
    required this.tokens,
    required this.live,
    required this.idle,
    required this.hold,
    required this.press,
    required this.burst,
    required this.nudge,
  }) : super(repaint: Listenable.merge([idle, hold, press, burst, nudge]));

  static const Color blush = Color(0xFFFFA2BE);
  static const Color shade = Color(0x00780A32);
  static const Color shadeDeep = Color(0x52780A32);

  final SkyTokens tokens;
  final bool live;
  final Animation<double> idle;
  final Animation<double> hold;
  final Animation<double> press;
  final Animation<double> burst;
  final Animation<double> nudge;

  static double _wave(double t, double phase) => math.sin((t + phase) * 2 * math.pi);

  @override
  void paint(Canvas canvas, Size size) {
    const box = LoveHeart.box;
    final center = Offset(size.width / 2, box / 2);
    final origin = center - const Offset(box / 2, box / 2);
    final t = live ? idle.value : 0.0;
    final h = hold.value.clamp(0.0, 1.0);
    final b = burst.value;
    final bursting = live && b > 0 && b < 1;

    _paintGlow(canvas, center, h, bursting ? b : null);
    _paintRings(canvas, center, t, h);
    if (bursting) _paintRipples(canvas, center, b);
    _paintArc(canvas, center, h);
    final scale = _coreScale(h, bursting ? b : null);
    _paintCore(canvas, center, LoveHeart.coreRadius * scale, t, h);
    _paintGlyph(canvas, center, scale, h);
    _paintFloats(canvas, center, origin, t, h, bursting ? b : null);
    if (bursting) _paintSparks(canvas, center, b);
  }

  double _coreScale(double h, double? b) {
    var scale = 1 - 0.04 * press.value + 0.07 * Curves.easeOut.transform(h);
    if (b != null) scale += 0.1 * math.sin(math.min(b / 0.3, 1) * math.pi);
    final n = nudge.value;
    if (live && n > 0 && n < 1) scale += 0.05 * math.sin(n * 2 * math.pi).abs();
    return scale;
  }

  void _paintGlow(Canvas canvas, Offset center, double h, double? b) {
    var alpha = 0.55 + 0.2 * h;
    if (b != null) alpha += 0.25 * (1 - b);
    alpha = alpha.clamp(0.0, 1.0);
    const radius = LoveHeart.coreRadius + 54;
    final rose = tokens.rose;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            rose.withValues(alpha: alpha * 0.5),
            rose.withValues(alpha: alpha * 0.5),
            rose.withValues(alpha: alpha * 0.15),
            rose.withValues(alpha: 0),
          ],
          stops: const [0, 0.54, 0.75, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void _paintRings(Canvas canvas, Offset center, double t, double h) {
    final squeeze = 1 - 0.035 * Curves.easeOut.transform(h);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < LoveHeart.rings.length; i++) {
      final (base, opacity) = LoveHeart.rings[i];
      final breathe = live ? _wave(t, i * 0.18) : 0.0;
      final radius = base * squeeze * (1 + 0.012 * breathe);
      final alpha = (opacity * (1 + 0.25 * breathe) + 0.22 * h * (1 - i * 0.3)).clamp(0.0, 1.0);
      canvas.drawCircle(center, radius, stroke..color = tokens.rose.withValues(alpha: alpha));
    }
  }

  void _paintRipples(Canvas canvas, Offset center, double b) {
    for (var k = 0; k < 2; k++) {
      final p = ((b - k * 0.14) / 0.7).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final eased = Curves.easeOutCubic.transform(p);
      canvas.drawCircle(
        center,
        LoveHeart.coreRadius + 104 * eased,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6 + 2.4 * (1 - p)
          ..color = (k == 0 ? tokens.rose : tokens.gold).withValues(alpha: 0.65 * (1 - p)),
      );
    }
  }

  void _paintArc(Canvas canvas, Offset center, double h) {
    if (h <= 0) return;
    final radius = LoveHeart.rings.first.$1 * (1 - 0.035 * Curves.easeOut.transform(h));
    final sweep = 2 * math.pi * h;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = tokens.rose,
    );
    final head = center + Offset(math.cos(sweep - math.pi / 2), math.sin(sweep - math.pi / 2)) * radius;
    canvas.drawCircle(head, 3.2, Paint()..color = tokens.gold.withValues(alpha: 0.9));
  }

  void _paintCore(Canvas canvas, Offset center, double radius, double t, double h) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.955,
          colors: [blush, tokens.roseDeep],
          stops: const [0, 0.7],
        ).createShader(rect),
    );
    if (h > 0) {
      canvas.save();
      canvas.clipPath(Path()..addOval(rect));
      final level = rect.bottom - rect.height * Curves.easeInOut.transform(h);
      final fill = Path()..moveTo(rect.left, level);
      const steps = 16;
      for (var i = 0; i <= steps; i++) {
        final x = rect.left + rect.width * i / steps;
        final ripple = live ? 2.6 * math.sin(i / steps * 3 * math.pi + t * 6 * math.pi) : 0.0;
        fill.lineTo(x, level + ripple);
      }
      fill
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.left, rect.bottom)
        ..close();
      canvas.drawPath(fill, Paint()..color = SkyTokens.white.withValues(alpha: 0.18));
      canvas.restore();
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [shade, shade, shadeDeep],
          stops: [0, 0.68, 1],
        ).createShader(rect),
    );
  }

  void _paintGlyph(Canvas canvas, Offset center, double scale, double h) {
    final unit = 58 / 24 * scale * (1 + 0.05 * h);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(unit);
    canvas.translate(-12, -12);
    canvas.drawPath(LoveShapes.heart, Paint()..color = SkyTokens.white.withValues(alpha: 0.35 + 0.65 * h));
    canvas.drawPath(
      LoveShapes.heart,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.9
        ..strokeJoin = StrokeJoin.round
        ..color = SkyTokens.white,
    );
    canvas.restore();
  }

  void _paintFloats(Canvas canvas, Offset center, Offset origin, double t, double h, double? b) {
    var fade = 1.0;
    if (b != null) fade = math.max(1 - b / 0.22, (b - 0.62) / 0.38).clamp(0.0, 1.0);
    if (fade <= 0) return;
    final pull = 0.16 * Curves.easeOut.transform(h);
    final paint = Paint();
    for (final f in LoveHeart.floats) {
      final wave = live ? _wave(t, f.phase) : 0.0;
      final drift = live ? _wave(t * 0.5, f.phase + 0.25) : 0.0;
      final corner = origin + Offset(f.x, f.y + 4 * wave);
      final mid = corner + Offset(f.size / 2, f.size / 2);
      final at = corner + (center - mid) * pull;
      final glow = live ? 0.85 + 0.15 * _wave(t, f.phase + 0.5) : 1.0;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate((f.turn + 6 * drift) * math.pi / 180);
      canvas.scale(f.size / 24);
      canvas.drawPath(LoveShapes.heart, paint..color = tokens.rose.withValues(alpha: f.opacity * glow * fade));
      canvas.restore();
    }
  }

  void _paintSparks(Canvas canvas, Offset center, double b) {
    final travel = Curves.easeOutCubic.transform(b);
    final alpha = b < 0.55 ? 1.0 : (1 - (b - 0.55) / 0.45).clamp(0.0, 1.0);
    final palette = [tokens.rose, SkyTokens.roseLight, tokens.gold, tokens.lavender];
    final paint = Paint();
    for (final s in LoveHeart.sparks) {
      final direction = Offset(math.cos(s.angle), math.sin(s.angle));
      final at = center + direction * (LoveHeart.coreRadius * 0.8 + s.distance * travel);
      paint.color = palette[s.tone].withValues(alpha: alpha);
      if (s.heart) {
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(s.angle + math.pi / 2 + b * s.spin);
        canvas.scale(s.size / 24);
        canvas.translate(-12, -12);
        canvas.drawPath(LoveShapes.heart, paint);
        canvas.restore();
      } else {
        canvas.drawCircle(at, s.size * (1 - 0.45 * b), paint);
      }
    }
  }

  @override
  bool shouldRepaint(LoveHeartPainter oldDelegate) =>
      oldDelegate.tokens != tokens ||
      oldDelegate.live != live ||
      oldDelegate.idle != idle ||
      oldDelegate.hold != hold ||
      oldDelegate.press != press ||
      oldDelegate.burst != burst ||
      oldDelegate.nudge != nudge;
}
