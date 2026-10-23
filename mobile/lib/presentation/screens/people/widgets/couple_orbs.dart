import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../sky/sky.dart';

class CoupleOrbs extends StatelessWidget {
  const CoupleOrbs({super.key, required this.myName, required this.partnerName, this.size = 58});

  final String myName;
  final String partnerName;
  final double size;

  static String initialOf(String name) => SkyAvatar.initialOf(name, fallback: '');

  @override
  Widget build(BuildContext context) {
    final motion = skyMotionAllowed(context);
    final mine = initialOf(myName);
    final theirs = initialOf(partnerName);
    final overlap = size * 0.18;
    final badge = size * 0.46;
    return ExcludeSemantics(
      child: SizedBox(
        width: size * 2 - overlap,
        height: size + badge * 0.4,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: OrbInitial(initial: mine, style: SkyAvatarStyle.me, size: size, motion: motion),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: OrbInitial(initial: theirs, style: SkyAvatarStyle.partner, size: size, motion: motion),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: HeartBadge(size: badge, beat: motion ? '$mine|$theirs' : null),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OrbInitial extends StatelessWidget {
  const OrbInitial({super.key, required this.initial, required this.style, required this.size, required this.motion});

  final String initial;
  final SkyAvatarStyle style;
  final double size;
  final bool motion;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedSwitcher(
        duration: motion ? SkyMotion.quick : Duration.zero,
        switchInCurve: SkyMotion.standard,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: Tween<double>(begin: 0.86, end: 1).animate(animation), child: child),
        ),
        child: SkyAvatar(
          key: ValueKey<String>('orb-${style.name}-$initial'),
          initial: initial,
          style: style,
          size: size,
        ),
      ),
    );
  }
}

class HeartBadge extends StatelessWidget {
  const HeartBadge({super.key, required this.size, this.beat});

  final double size;
  final String? beat;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final face = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.1),
      decoration: BoxDecoration(color: t.surface, shape: BoxShape.circle),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: t.roseOrbGradient,
          border: Border.all(color: const Color(0x59FFFFFF)),
          boxShadow: [BoxShadow(color: t.rose.withValues(alpha: 0.5), blurRadius: size * 0.45)],
        ),
        alignment: Alignment.center,
        child: SkyIcon(SkyIcons.heart, size: size * 0.42, color: SkyTokens.white),
      ),
    );
    final key = beat;
    if (key == null) return face;
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('beat-$key'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: SkyMotion.slow,
      curve: SkyMotion.gentle,
      builder: (context, value, child) =>
          Transform.scale(scale: 1 + 0.16 * math.sin(math.pi * value), child: child),
      child: face,
    );
  }
}
