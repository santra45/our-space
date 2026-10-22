import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import 'live_love_counter.dart';
import 'milestone_copy.dart';

class TogetherHero extends StatelessWidget {
  const TogetherHero({super.key, required this.counter, this.onTap});

  final LiveLoveCounter counter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SkyFeatureCard(
      accent: SkyAccent.gold,
      onTap: onTap,
      semanticLabel: onTap == null ? null : MilestoneCopy.changeDay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SkyLabel(MilestoneCopy.together, icon: SkyIcons.heart, tone: SkyTone.gold),
          const SizedBox(height: 10),
          ListenableBuilder(
            listenable: counter,
            builder: (context, _) => LoveClockFace(duration: counter.value),
          ),
        ],
      ),
    );
  }
}

class LoveClockFace extends StatelessWidget {
  const LoveClockFace({super.key, required this.duration});

  static const List<FontFeature> _figures = [FontFeature.tabularFigures(), FontFeature.liningFigures()];

  final LoveDuration duration;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final motion = skyMotionAllowed(context);
    final digits = SkyType.serif(
      46,
      weight: FontWeight.w500,
      italic: false,
      height: 1,
    ).copyWith(color: t.title, fontFeatures: _figures);
    final days = SkyType.serif(64, weight: FontWeight.w500, height: 1).copyWith(color: t.gold, fontFeatures: _figures);
    final label = SkyType.caps(10, weight: FontWeight.w600, tracking: 0.14, color: t.muted);
    final separator = SkyType.serif(34, italic: false, height: 1).copyWith(color: t.faint);

    Widget unit(Widget value, String name) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          value,
          const SizedBox(height: 7),
          Text(name.toUpperCase(), style: label),
        ],
      );
    }

    Widget sep(String glyph) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 26),
        child: Text(glyph, style: separator),
      );
    }

    return Semantics(
      label: MilestoneCopy.clock(duration.totalDays, duration.hours, duration.minutes),
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            unit(
              DayPop(value: duration.totalDays, child: Text('${duration.totalDays}', style: days)),
              MilestoneCopy.days,
            ),
            sep('·'),
            unit(TickingDigits(value: twoDigitCount(duration.hours), style: digits, motion: motion), MilestoneCopy.hours),
            sep(':'),
            unit(
              TickingDigits(value: twoDigitCount(duration.minutes), style: digits, motion: motion),
              MilestoneCopy.minutes,
            ),
            sep(':'),
            unit(
              TickingDigits(value: twoDigitCount(duration.seconds), style: digits, motion: motion),
              MilestoneCopy.seconds,
            ),
          ],
        ),
      ),
    );
  }
}

class TickingDigits extends StatelessWidget {
  const TickingDigits({super.key, required this.value, required this.style, this.motion = true});

  final String value;
  final TextStyle style;
  final bool motion;

  @override
  Widget build(BuildContext context) {
    final text = Text(value, key: ValueKey<String>(value), style: style);
    if (!motion) return text;
    return AnimatedSwitcher(
      duration: SkyMotion.quick,
      switchInCurve: SkyMotion.standard,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey<String>(value);
        final slide = Tween<Offset>(
          begin: incoming ? const Offset(0, 0.28) : const Offset(0, -0.28),
          end: Offset.zero,
        ).animate(animation);
        return ClipRect(
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          ),
        );
      },
      child: text,
    );
  }
}

class DayPop extends StatefulWidget {
  const DayPop({super.key, required this.value, required this.child});

  final int value;
  final Widget child;

  @override
  State<DayPop> createState() => _DayPopState();
}

class _DayPopState extends State<DayPop> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(vsync: this, duration: SkyMotion.slow, value: 1);
  late final Animation<double> _scale = Tween<double>(
    begin: 0.86,
    end: 1,
  ).animate(CurvedAnimation(parent: _pop, curve: const SkySpringCurve(SkyMotion.popSpring, seconds: 0.5)));

  @override
  void didUpdateWidget(covariant DayPop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && skyMotionAllowed(context)) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}
