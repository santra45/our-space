import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_motion.dart';

bool motionAllowed(BuildContext context) {
  return !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
}

abstract class TwLoopingAnimation extends StatefulWidget {
  const TwLoopingAnimation({super.key, required this.child, required this.period, this.enabled = true});

  final Widget child;
  final Duration period;
  final bool enabled;

  Widget buildFrame(BuildContext context, double t, Widget child);

  @override
  State<TwLoopingAnimation> createState() => _LoopingState();
}

class _LoopingState extends State<TwLoopingAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.period);

  void _sync(bool allowed) {
    final run = widget.enabled && allowed;
    if (run && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!run && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(motionAllowed(context));
  }

  @override
  void didUpdateWidget(covariant TwLoopingAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) _controller.duration = widget.period;
    _sync(motionAllowed(context));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => widget.buildFrame(context, _controller.value, child!),
      child: widget.child,
    );
  }
}

class TwPulse extends TwLoopingAnimation {
  const TwPulse({super.key, required super.child, super.enabled}) : super(period: AppMotion.pulse);

  static double opacityAt(double t) {
    const curve = AppMotion.pulseCurve;
    if (t <= 0.5) return 1 - 0.5 * curve.transform(t / 0.5);
    return 0.5 + 0.5 * curve.transform((t - 0.5) / 0.5);
  }

  @override
  Widget buildFrame(BuildContext context, double t, Widget child) {
    return Opacity(opacity: opacityAt(t), child: child);
  }
}

class TwPing extends TwLoopingAnimation {
  const TwPing({super.key, required super.child, super.enabled}) : super(period: AppMotion.ping);

  static (double scale, double opacity) frameAt(double t) {
    if (t >= 0.75) return (2, 0);
    final p = AppMotion.pingCurve.transform(t / 0.75);
    return (1 + p, 1 - p);
  }

  @override
  Widget buildFrame(BuildContext context, double t, Widget child) {
    final (scale, opacity) = frameAt(t);
    return Opacity(opacity: opacity, child: Transform.scale(scale: scale, child: child));
  }
}

class TwBounce extends TwLoopingAnimation {
  const TwBounce({super.key, required super.child, super.enabled}) : super(period: AppMotion.bounce);

  static const Curve _down = Cubic(0.8, 0, 1, 1);
  static const Curve _up = Cubic(0, 0, 0.2, 1);

  static double liftAt(double t) {
    if (t <= 0.5) return 1 - _down.transform(t / 0.5);
    return _up.transform((t - 0.5) / 0.5);
  }

  @override
  Widget buildFrame(BuildContext context, double t, Widget child) {
    return FractionalTranslation(translation: Offset(0, -0.25 * liftAt(t)), child: child);
  }
}

class TwSpin extends TwLoopingAnimation {
  const TwSpin({super.key, required super.child, super.enabled}) : super(period: AppMotion.spin);

  @override
  Widget buildFrame(BuildContext context, double t, Widget child) {
    return Transform.rotate(angle: t * 2 * math.pi, child: child);
  }
}
