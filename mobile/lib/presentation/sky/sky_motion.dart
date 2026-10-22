import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../widgets/app_haptics.dart';
import 'sky_tokens.dart';

abstract final class SkyMotion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration quick = Duration(milliseconds: 200);
  static const Duration base = Duration(milliseconds: 250);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 350);
  static const Duration sheet = Duration(milliseconds: 420);
  static const Duration streak = Duration(milliseconds: 900);
  static const Duration burst = Duration(milliseconds: 1200);
  static const Duration celebration = Duration(milliseconds: 1600);
  static const Duration twinkle = Duration(milliseconds: 3200);
  static const Duration presence = Duration(milliseconds: 2200);
  static const Duration staggerStep = Duration(milliseconds: 45);
  static const int staggerCap = 8;

  static const Curve standard = Cubic(0.2, 0, 0, 1);
  static const Curve enter = Cubic(0.05, 0.7, 0.1, 1);
  static const Curve exit = Cubic(0.3, 0, 0.8, 0.15);
  static const Curve gentle = Curves.easeOutCubic;

  static const double pressScale = 0.96;
  static const double entranceOffset = 14;

  static const SpringDescription pressSpring = SpringDescription(mass: 1, stiffness: 520, damping: 22);
  static const SpringDescription sheetSpring = SpringDescription(mass: 1, stiffness: 380, damping: 32);
  static const SpringDescription popSpring = SpringDescription(mass: 1, stiffness: 420, damping: 20);

  static Duration staggerDelay(int index) => staggerStep * index.clamp(0, staggerCap);
}

bool skyMotionAllowed(BuildContext context) => !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

class SkySpringCurve extends Curve {
  const SkySpringCurve(this.spring, {this.seconds = 0.6});

  final SpringDescription spring;
  final double seconds;

  @override
  double transformInternal(double t) => SpringSimulation(spring, 0, 1, 0).x(t * seconds);
}

class SkyPressable extends StatefulWidget {
  const SkyPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = SkyMotion.pressScale,
    this.haptic = true,
    this.enabled = true,
    this.semanticLabel,
    this.button = true,
    this.selected,
    this.behavior = HitTestBehavior.opaque,
    this.excludeSemantics = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final bool haptic;
  final bool enabled;
  final String? semanticLabel;
  final bool button;
  final bool? selected;
  final HitTestBehavior behavior;
  final bool excludeSemantics;

  @override
  State<SkyPressable> createState() => _SkyPressableState();
}

class _SkyPressableState extends State<SkyPressable> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: 1);

  bool get _active => widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _down(TapDownDetails _) {
    if (!_active || !skyMotionAllowed(context)) return;
    _scale.animateTo(widget.pressedScale, duration: SkyMotion.instant, curve: Curves.easeOut);
  }

  void _release() {
    if (!mounted) return;
    if (!skyMotionAllowed(context)) {
      _scale.value = 1;
      return;
    }
    _scale.animateWith(SpringSimulation(SkyMotion.pressSpring, _scale.value, 1, _scale.velocity));
  }

  void _tap() {
    if (!_active) return;
    _release();
    if (widget.haptic) AppHaptics.tick();
    widget.onTap?.call();
  }

  void _longPress() {
    if (!_active) return;
    _release();
    if (widget.haptic) AppHaptics.tap();
    widget.onLongPress?.call();
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.button,
      enabled: widget.enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      excludeSemantics: widget.excludeSemantics,
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: _active ? _down : null,
        onTapCancel: _active ? _release : null,
        onTap: _active && widget.onTap != null ? _tap : null,
        onLongPress: _active && widget.onLongPress != null ? _longPress : null,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
          child: widget.child,
        ),
      ),
    );
  }
}

class SkyEntrance extends StatelessWidget {
  const SkyEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = Duration.zero,
    this.duration = SkyMotion.medium,
    this.offset = const Offset(0, SkyMotion.entranceOffset),
  });

  final Widget child;
  final int index;
  final Duration delay;
  final Duration duration;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    if (!skyMotionAllowed(context)) {
      return child.animate().fadeIn(duration: SkyMotion.fast);
    }
    final wait = delay + SkyMotion.staggerDelay(index);
    return child
        .animate()
        .fadeIn(delay: wait, duration: duration, curve: SkyMotion.gentle)
        .move(begin: offset, end: Offset.zero, delay: wait, duration: duration, curve: SkyMotion.standard);
  }
}

List<Widget> skyStaggered(List<Widget> children, {int startIndex = 0, Offset? offset}) {
  return [
    for (var i = 0; i < children.length; i++)
      SkyEntrance(
        index: startIndex + i,
        offset: offset ?? const Offset(0, SkyMotion.entranceOffset),
        child: children[i],
      ),
  ];
}

class SkyFadeThroughSwitcher extends StatelessWidget {
  const SkyFadeThroughSwitcher({super.key, required this.child, this.duration = SkyMotion.medium, this.fillColor});

  final Widget child;
  final Duration duration;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    if (!skyMotionAllowed(context)) return child;
    return PageTransitionSwitcher(
      duration: duration,
      layoutBuilder: (entries) => Stack(fit: StackFit.expand, children: entries),
      transitionBuilder: (child, primary, secondary) => FadeThroughTransition(
        animation: primary,
        secondaryAnimation: secondary,
        fillColor: fillColor ?? const Color(0x00000000),
        child: child,
      ),
      child: child,
    );
  }
}

class SkySharedAxisSwitcher extends StatelessWidget {
  const SkySharedAxisSwitcher({
    super.key,
    required this.child,
    this.axis = SharedAxisTransitionType.horizontal,
    this.reverse = false,
    this.duration = SkyMotion.medium,
  });

  final Widget child;
  final SharedAxisTransitionType axis;
  final bool reverse;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (!skyMotionAllowed(context)) return child;
    return PageTransitionSwitcher(
      duration: duration,
      reverse: reverse,
      layoutBuilder: (entries) => Stack(alignment: Alignment.topCenter, children: entries),
      transitionBuilder: (child, primary, secondary) => SharedAxisTransition(
        animation: primary,
        secondaryAnimation: secondary,
        transitionType: axis,
        fillColor: const Color(0x00000000),
        child: child,
      ),
      child: child,
    );
  }
}

class SkyPageRoute<T> extends PageRoute<T> {
  SkyPageRoute({
    required this.builder,
    super.settings,
    this.axis = SharedAxisTransitionType.horizontal,
    this.maintainState = true,
    super.fullscreenDialog,
  });

  final WidgetBuilder builder;
  final SharedAxisTransitionType axis;

  @override
  final bool maintainState;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => true;

  @override
  Duration get transitionDuration => SkyMotion.slow;

  @override
  Duration get reverseTransitionDuration => SkyMotion.base;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!skyMotionAllowed(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    return SharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      transitionType: axis,
      fillColor: context.sky.page,
      child: child,
    );
  }
}

Future<T?> skyPush<T>(BuildContext context, WidgetBuilder builder, {RouteSettings? settings}) {
  return Navigator.of(context).push<T>(SkyPageRoute<T>(builder: builder, settings: settings));
}
