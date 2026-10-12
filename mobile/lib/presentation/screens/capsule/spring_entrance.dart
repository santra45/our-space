import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../../widgets/our_widgets.dart';

enum EntranceFade { none, tween, spring }

@immutable
class EntranceSpec {
  const EntranceSpec({
    this.fromScale = 1,
    this.fromDy = 0,
    this.fade = EntranceFade.none,
    this.scaleSpring = AppMotion.framerScaleSpring,
    this.positionSpring = AppMotion.framerPositionSpring,
    this.fadeSpring = AppMotion.framerScaleSpring,
  });

  static const EntranceSpec writeModal = EntranceSpec(fromScale: 0.9, fade: EntranceFade.tween);

  static const EntranceSpec sealedEnvelope = EntranceSpec(fromScale: 0.9, fromDy: 20);

  static const EntranceSpec openLetter = EntranceSpec(
    fromScale: 0.9,
    fromDy: 30,
    fade: EntranceFade.spring,
    scaleSpring: AppMotion.letterSpring,
    positionSpring: AppMotion.letterSpring,
    fadeSpring: AppMotion.letterSpring,
  );

  final double fromScale;
  final double fromDy;
  final EntranceFade fade;
  final SpringDescription scaleSpring;
  final SpringDescription positionSpring;
  final SpringDescription fadeSpring;
}

@immutable
class EntranceFrame {
  const EntranceFrame(this.opacity, this.scale, this.dy);

  static const EntranceFrame rest = EntranceFrame(1, 1, 0);

  final double opacity;
  final double scale;
  final double dy;
}

EntranceFrame entranceAt(EntranceSpec spec, double seconds) {
  double opacity;
  switch (spec.fade) {
    case EntranceFade.none:
      opacity = 1;
    case EntranceFade.tween:
      opacity = AppMotion.framerEase.transform((seconds / 0.3).clamp(0.0, 1.0));
    case EntranceFade.spring:
      opacity = AppMotion.springValue(spec.fadeSpring, 0, 1, seconds);
  }
  final scale = spec.fromScale == 1 ? 1.0 : AppMotion.springValue(spec.scaleSpring, spec.fromScale, 1, seconds);
  final dy = spec.fromDy == 0 ? 0.0 : AppMotion.springValue(spec.positionSpring, spec.fromDy, 0, seconds);
  return EntranceFrame(opacity.clamp(0.0, 1.0), scale, dy);
}

class SpringEntrance extends StatefulWidget {
  const SpringEntrance({super.key, required this.spec, required this.child});

  final EntranceSpec spec;
  final Widget child;

  @override
  State<SpringEntrance> createState() => _SpringEntranceState();
}

class _SpringEntranceState extends State<SpringEntrance> with SingleTickerProviderStateMixin {
  static const Duration _length = Duration(milliseconds: 1200);

  late final AnimationController _clock = AnimationController(vsync: this, duration: _length);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!motionAllowed(context)) {
      _clock.stop();
      _clock.value = 1;
    } else if (_clock.value == 0 && !_clock.isAnimating) {
      _clock.forward();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _clock,
      child: widget.child,
      builder: (context, child) {
        final frame = _clock.value >= 1
            ? EntranceFrame.rest
            : entranceAt(widget.spec, _clock.value * _length.inMicroseconds / 1e6);
        return Opacity(
          opacity: frame.opacity,
          child: Transform.translate(
            offset: Offset(0, frame.dy),
            child: Transform.scale(scale: frame.scale, child: child),
          ),
        );
      },
    );
  }
}

class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, required this.onTap, this.pressedScale = 0.98});

  final Widget child;
  final VoidCallback onTap;
  final double pressedScale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: 1);

  void _springTo(double target) {
    if (!motionAllowed(context)) {
      _scale.value = 1;
      return;
    }
    _scale.animateWith(SpringSimulation(AppMotion.framerScaleSpring, _scale.value, target, _scale.velocity));
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _springTo(widget.pressedScale),
      onTapUp: (details) => _springTo(1),
      onTapCancel: () => _springTo(1),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scale,
        child: widget.child,
        builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
      ),
    );
  }
}
