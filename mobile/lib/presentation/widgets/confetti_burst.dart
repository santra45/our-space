import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import 'tw_animations.dart';

enum ConfettiShape { square, circle, heart }

@immutable
class ConfettiOptions {
  const ConfettiOptions({
    this.particleCount = 50,
    this.angle = 90,
    this.spread = 45,
    this.startVelocity = 45,
    this.decay = 0.9,
    this.gravity = 1,
    this.drift = 0,
    this.ticks = 200,
    this.originX = 0.5,
    this.originY = 0.5,
    this.shapes = const [ConfettiShape.square, ConfettiShape.circle],
    this.colors = const [
      Color(0xFF26CCFF),
      Color(0xFFA25AFD),
      Color(0xFFFF5E7E),
      Color(0xFF88FF5A),
      Color(0xFFFCFF42),
      Color(0xFFFFA62D),
      Color(0xFFFF36FF),
    ],
    this.scalar = 1,
    this.flat = false,
  });

  final int particleCount;
  final double angle;
  final double spread;
  final double startVelocity;
  final double decay;
  final double gravity;
  final double drift;
  final int ticks;
  final double originX;
  final double originY;
  final List<ConfettiShape> shapes;
  final List<Color> colors;
  final double scalar;
  final bool flat;

  ConfettiOptions copyWith({
    int? particleCount,
    double? spread,
    double? startVelocity,
    double? decay,
    double? scalar,
  }) {
    return ConfettiOptions(
      particleCount: particleCount ?? this.particleCount,
      angle: angle,
      spread: spread ?? this.spread,
      startVelocity: startVelocity ?? this.startVelocity,
      decay: decay ?? this.decay,
      gravity: gravity,
      drift: drift,
      ticks: ticks,
      originX: originX,
      originY: originY,
      shapes: shapes,
      colors: colors,
      scalar: scalar ?? this.scalar,
      flat: flat,
    );
  }
}

abstract final class ConfettiPresets {
  static const List<Color> heartColors = [
    AppColors.blush400,
    AppColors.blush500,
    AppColors.blush200,
    AppColors.lavender300,
    AppColors.cream200,
  ];

  static const List<Color> celebrationColors = [
    AppColors.blush400,
    AppColors.blush500,
    AppColors.lavender400,
    AppColors.matcha200,
    AppColors.blush200,
  ];

  static const ConfettiOptions heart = ConfettiOptions(
    shapes: [ConfettiShape.heart, ConfettiShape.circle],
    particleCount: 50,
    spread: 70,
    originY: 0.7,
    colors: heartColors,
    scalar: 1.2,
  );

  static const ConfettiOptions _celebrationBase = ConfettiOptions(originY: 0.7, colors: celebrationColors);

  static List<ConfettiOptions> get celebration {
    const count = 150;
    ConfettiOptions part(double ratio, ConfettiOptions o) => o.copyWith(particleCount: (count * ratio).floor());
    return [
      part(0.25, _celebrationBase.copyWith(spread: 26, startVelocity: 55)),
      part(0.2, _celebrationBase.copyWith(spread: 60)),
      part(0.35, _celebrationBase.copyWith(spread: 100, decay: 0.91, scalar: 0.8)),
      part(0.1, _celebrationBase.copyWith(spread: 120, startVelocity: 25, decay: 0.92, scalar: 1.2)),
      part(0.1, _celebrationBase.copyWith(spread: 120, startVelocity: 45)),
    ];
  }
}

class ConfettiParticle {
  ConfettiParticle._({
    required this.x,
    required this.y,
    required this.wobble,
    required this.wobbleSpeed,
    required this.velocity,
    required this.angle2D,
    required this.tiltAngle,
    required this.color,
    required this.shape,
    required this.totalTicks,
    required this.decay,
    required this.drift,
    required this.random,
    required this.gravity,
    required this.scalar,
    required this.flat,
  });

  factory ConfettiParticle.spawn(ConfettiOptions o, Size canvas, Color color, ConfettiShape shape, math.Random rng) {
    final radAngle = o.angle * math.pi / 180;
    final radSpread = o.spread * math.pi / 180;
    return ConfettiParticle._(
      x: canvas.width * o.originX,
      y: canvas.height * o.originY,
      wobble: rng.nextDouble() * 10,
      wobbleSpeed: math.min(0.11, rng.nextDouble() * 0.1 + 0.05),
      velocity: o.startVelocity * 0.5 + rng.nextDouble() * o.startVelocity,
      angle2D: -radAngle + (0.5 * radSpread - rng.nextDouble() * radSpread),
      tiltAngle: (rng.nextDouble() * (0.75 - 0.25) + 0.25) * math.pi,
      color: color,
      shape: shape,
      totalTicks: o.ticks,
      decay: o.decay,
      drift: o.drift,
      random: rng.nextDouble() + 2,
      gravity: o.gravity * 3,
      scalar: o.scalar,
      flat: o.flat,
    );
  }

  double x;
  double y;
  double wobble;
  final double wobbleSpeed;
  double velocity;
  final double angle2D;
  double tiltAngle;
  final Color color;
  final ConfettiShape shape;
  int tick = 0;
  final int totalTicks;
  final double decay;
  final double drift;
  double random;
  final double gravity;
  final double scalar;
  final bool flat;
  double tiltSin = 0;
  double tiltCos = 0;
  double wobbleX = 0;
  double wobbleY = 0;
  double progress = 0;

  static const double ovalScalar = 0.6;

  bool step(math.Random rng) {
    x += math.cos(angle2D) * velocity + drift;
    y += math.sin(angle2D) * velocity + gravity;
    velocity *= decay;
    if (flat) {
      wobble = 0;
      wobbleX = x + 10 * scalar;
      wobbleY = y + 10 * scalar;
      tiltSin = 0;
      tiltCos = 0;
      random = 1;
    } else {
      wobble += wobbleSpeed;
      wobbleX = x + 10 * scalar * math.cos(wobble);
      wobbleY = y + 10 * scalar * math.sin(wobble);
      tiltAngle += 0.1;
      tiltSin = math.sin(tiltAngle);
      tiltCos = math.cos(tiltAngle);
      random = rng.nextDouble() + 2;
    }
    progress = tick / totalTicks;
    tick += 1;
    return tick < totalTicks;
  }

  double get x1 => x + random * tiltCos;
  double get y1 => y + random * tiltSin;
  double get x2 => wobbleX + random * tiltCos;
  double get y2 => wobbleY + random * tiltSin;
}

final Path _heartPath = () {
  const s = 10 / 302;
  final p = Path()
    ..moveTo(167, 72)
    ..cubicTo(186, 34, 204, 16, 242, 16)
    ..cubicTo(284, 16, 318, 49, 318, 91)
    ..cubicTo(318, 167, 242, 242, 167, 318)
    ..cubicTo(91, 242, 16, 167, 16, 91)
    ..cubicTo(16, 49, 49, 16, 92, 16)
    ..cubicTo(130, 16, 149, 34, 167, 72)
    ..close();
  final m = Matrix4.identity()
    ..translateByDouble(-167 * s, -167 * s, 0, 1)
    ..scaleByDouble(s, s, 1, 1);
  return p.transform(m.storage);
}();

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, Listenable repaint) : super(repaint: repaint);

  final List<ConfettiParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final f in particles) {
      if (f.tick == 0) continue;
      paint.color = f.color.withValues(alpha: (1 - f.progress).clamp(0.0, 1.0));
      final rotation = math.pi / 10 * f.wobble;
      switch (f.shape) {
        case ConfettiShape.heart:
          final sx = (f.x2 - f.x1).abs() * 0.1;
          final sy = (f.y2 - f.y1).abs() * 0.1;
          final c = math.cos(rotation);
          final s = math.sin(rotation);
          final storage = Matrix4(
            c * sx, s * sx, 0, 0,
            -s * sy, c * sy, 0, 0,
            0, 0, 1, 0,
            f.x, f.y, 0, 1,
          ).storage;
          canvas.drawPath(_heartPath.transform(storage), paint);
        case ConfettiShape.circle:
          final rx = (f.x2 - f.x1).abs() * ConfettiParticle.ovalScalar;
          final ry = (f.y2 - f.y1).abs() * ConfettiParticle.ovalScalar;
          canvas.save();
          canvas.translate(f.x, f.y);
          canvas.rotate(rotation);
          canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), paint);
          canvas.restore();
        case ConfettiShape.square:
          final path = Path()
            ..moveTo(f.x.floorToDouble(), f.y.floorToDouble())
            ..lineTo(f.wobbleX.floorToDouble(), f.y1.floorToDouble())
            ..lineTo(f.x2.floorToDouble(), f.y2.floorToDouble())
            ..lineTo(f.x1.floorToDouble(), f.wobbleY.floorToDouble())
            ..close();
          canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => true;
}

class ConfettiCanvas extends StatefulWidget {
  const ConfettiCanvas({super.key, required this.controller});

  final ConfettiCanvasController controller;

  @override
  State<ConfettiCanvas> createState() => _ConfettiCanvasState();
}

class ConfettiCanvasController extends ChangeNotifier {
  ConfettiCanvasController({math.Random? random}) : _rng = random ?? math.Random();

  final math.Random _rng;
  final List<ConfettiParticle> particles = [];
  final List<ConfettiOptions> _pending = [];
  VoidCallback? onIdle;

  bool get isActive => particles.isNotEmpty || _pending.isNotEmpty;

  void fire(ConfettiOptions options) {
    _pending.add(options);
    notifyListeners();
  }

  void spawnPending(Size canvas) {
    if (_pending.isEmpty || canvas.isEmpty) return;
    for (final o in _pending) {
      for (var temp = o.particleCount - 1; temp >= 0; temp--) {
        final color = o.colors[temp % o.colors.length];
        final shape = o.shapes[_rng.nextInt(o.shapes.length)];
        particles.add(ConfettiParticle.spawn(o, canvas, color, shape, _rng));
      }
    }
    _pending.clear();
  }

  void stepFrame() {
    particles.removeWhere((f) => !f.step(_rng));
    notifyListeners();
    if (!isActive) onIdle?.call();
  }
}

class _ConfettiCanvasState extends State<ConfettiCanvas> with SingleTickerProviderStateMixin {
  static const Duration _frame = Duration(microseconds: 16667);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  Duration _carry = Duration.zero;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_ensureRunning);
    _ensureRunning();
  }

  void _ensureRunning() {
    if (widget.controller.isActive && !_ticker.isActive) {
      _last = Duration.zero;
      _carry = _frame;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final controller = widget.controller;
    controller.spawnPending(_size);
    _carry += elapsed - _last;
    _last = elapsed;
    var steps = 0;
    while (_carry >= _frame && steps < 4) {
      _carry -= _frame;
      steps += 1;
      controller.stepFrame();
    }
    if (_carry > _frame * 4) _carry = Duration.zero;
    if (!controller.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_ensureRunning);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _size = constraints.biggest;
          return CustomPaint(
            size: constraints.biggest,
            painter: _ConfettiPainter(widget.controller.particles, widget.controller),
          );
        },
      ),
    );
  }
}

abstract final class ConfettiBurst {
  static ConfettiCanvasController? _controller;
  static OverlayEntry? _entry;
  static math.Random? debugRandom;

  static ConfettiCanvasController? get activeController => _controller;

  static void fire(BuildContext context, List<ConfettiOptions> bursts) {
    if (!motionAllowed(context)) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    if (_controller == null || _entry == null || !_entry!.mounted) {
      final controller = ConfettiCanvasController(random: debugRandom);
      final entry = OverlayEntry(builder: (_) => Positioned.fill(child: ConfettiCanvas(controller: controller)));
      controller.onIdle = () {
        if (identical(_controller, controller)) {
          _controller = null;
          _entry = null;
        }
        if (entry.mounted) entry.remove();
        SchedulerBinding.instance.addPostFrameCallback((_) {
          entry.dispose();
          controller.dispose();
        });
      };
      _controller = controller;
      _entry = entry;
      overlay.insert(entry);
    }
    for (final b in bursts) {
      _controller!.fire(b);
    }
  }
}

void fireHeartConfetti(BuildContext context) => ConfettiBurst.fire(context, const [ConfettiPresets.heart]);

void fireCelebrationBurst(BuildContext context) => ConfettiBurst.fire(context, ConfettiPresets.celebration);
