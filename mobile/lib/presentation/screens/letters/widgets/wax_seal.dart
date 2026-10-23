import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../sky/sky.dart';

abstract final class LetterInk {
  static const Color sealLight = Color(0xFFFF7FA4);
  static const Color sealDeep = Color(0xFFC42F5E);
  static const Color sealGlyph = Color(0xFFFFE2EC);
  static const Color sealShadow = Color(0x73780A32);
  static const Color sealShade = Color(0x33000000);
  static const Color envelopeLight = Color(0xFFFFF6E4);
  static const Color envelopeDeep = Color(0xFFF4E2C2);
  static const Color envelopeFlap = Color(0x47D9BE8E);
  static const Color envelopeEdge = Color(0xFFD9BE8E);
  static const Color envelopeShadow = Color(0x47000000);
  static const Color readLine = Color(0x1A8C78AA);
  static const Color writeLine = Color(0x1F8C78AA);
  static const Color paperShadow = Color(0x59000000);
  static const Color waxLight = Color(0xFFFFFFFF);
  static const Color waxBlush = Color(0xFFFFD0DE);
}

class WaxSeal extends StatelessWidget {
  const WaxSeal({super.key, this.size = 46, this.split = 0, this.iconSize});

  final double size;
  final double split;
  final double? iconSize;

  Widget _face() {
    final k = size / 46;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          radius: 0.955,
          colors: [LetterInk.sealLight, LetterInk.sealDeep],
          stops: [0, 0.7],
        ),
        boxShadow: [BoxShadow(color: LetterInk.sealShadow, offset: Offset(0, 4 * k), blurRadius: 7.8 * k)],
      ),
      foregroundDecoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), LetterInk.sealShade],
          stops: [0.62, 1],
        ),
      ),
      child: SkyIcon(SkyIcons.heart, size: iconSize ?? size * 0.43, color: LetterInk.sealGlyph),
    );
  }

  @override
  Widget build(BuildContext context) {
    final face = _face();
    if (split <= 0) return SizedBox(width: size, height: size, child: face);
    final k = size / 52;
    Widget half({required bool left}) {
      final angle = (left ? -12 : 10) * math.pi / 180 * split;
      final shift = left ? Offset(-4 * k, 2 * k) : Offset(4 * k, 3 * k);
      return Transform.rotate(
        angle: angle,
        child: Transform.translate(
          offset: shift * split,
          child: ClipRect(
            child: OverflowBox(
              alignment: left ? Alignment.centerLeft : Alignment.centerRight,
              minWidth: size,
              maxWidth: size,
              child: face,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, top: 0, width: size / 2, height: size, child: half(left: true)),
          Positioned(right: 0, top: 0, width: size / 2, height: size, child: half(left: false)),
        ],
      ),
    );
  }
}

class BreakingWaxSeal extends StatefulWidget {
  const BreakingWaxSeal({super.key, this.size = 52, this.play = false});

  final double size;
  final bool play;

  @override
  State<BreakingWaxSeal> createState() => _BreakingWaxSealState();
}

class _BreakingWaxSealState extends State<BreakingWaxSeal> with SingleTickerProviderStateMixin {
  static const Duration _length = Duration(milliseconds: 720);

  late final AnimationController _controller = AnimationController(vsync: this, duration: _length, value: 1);
  late final Animation<double> _split = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.45, 1, curve: SkySpringCurve(SkyMotion.popSpring, seconds: 0.5)),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.play && skyMotionAllowed(context)) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _split,
      builder: (context, _) => WaxSeal(size: widget.size, split: _controller.value >= 1 ? 1 : _split.value.clamp(0.0, 1.3)),
    );
  }
}

class BreathingSeal extends StatefulWidget {
  const BreathingSeal({super.key, required this.child});

  final Widget child;

  @override
  State<BreathingSeal> createState() => _BreathingSealState();
}

class _BreathingSealState extends State<BreathingSeal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: SkyMotion.presence ~/ 2);
  late final Animation<double> _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (skyMotionAllowed(context)) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!skyMotionAllowed(context)) return widget.child;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Transform.scale(scale: 1 + 0.05 * _curve.value, child: child),
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}
