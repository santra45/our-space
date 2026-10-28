import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../us/us_copy.dart';
import '../us/us_keys.dart';
import 'live_love_counter.dart';
import 'milestone_copy.dart';

class TogetherHero extends StatelessWidget {
  const TogetherHero({super.key, required this.counter, required this.since, this.onTap});

  final LiveLoveCounter counter;
  final DateTime since;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final note = SkyType.bodySmall.copyWith(color: t.muted);
    return SkyFeatureCard(
      accent: SkyAccent.gold,
      onTap: onTap,
      semanticLabel: onTap == null ? null : MilestoneCopy.changeDay,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SkyLabel(MilestoneCopy.together, icon: SkyIcons.heart, tone: SkyTone.gold),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: counter,
                  builder: (context, _) => LoveClockFace(duration: counter.value),
                ),
              ],
            ),
          ),
          DecoratedBox(
            key: UsKeys.since,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: t.cardBorder))),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 13, 18, 14),
              child: Row(
                children: [
                  SkyIcon(SkyIcons.moon, size: 14, color: t.gold),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: '${UsCopy.since} '),
                          TextSpan(
                            text: UsDates.full(since),
                            style: TextStyle(color: t.text, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      style: note,
                    ),
                  ),
                ],
              ),
            ),
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
    final days = SkyType.serif(
      76,
      weight: FontWeight.w500,
      height: 1,
    ).copyWith(color: t.gold, fontFeatures: const [FontFeature.liningFigures()]);
    final daysWord = SkyType.serif(28, height: 1).copyWith(color: t.title);
    final and = SkyType.serif(15, height: 1).copyWith(color: t.muted);
    final digits = SkyType.serif(
      24,
      weight: FontWeight.w500,
      italic: false,
      height: 1,
    ).copyWith(color: t.title, fontFeatures: _figures);
    final label = SkyType.caps(9.5, weight: FontWeight.w600, tracking: 0.14, color: t.muted);

    Widget unit(String value, String name) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          TickingDigits(value: value, style: digits, motion: motion),
          const SizedBox(width: 4),
          Text(name.toUpperCase(), style: label),
        ],
      );
    }

    return Semantics(
      label: MilestoneCopy.clock(duration.totalDays, duration.hours, duration.minutes),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                DayPop(
                  value: duration.totalDays,
                  child: Text('${duration.totalDays}', style: days),
                ),
                const SizedBox(width: 10),
                Text(MilestoneCopy.dayWord(duration.totalDays), style: daysWord),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(MilestoneCopy.and, style: and),
                const SizedBox(width: 14),
                unit(twoDigitCount(duration.hours), MilestoneCopy.hours),
                const SizedBox(width: 14),
                unit(twoDigitCount(duration.minutes), MilestoneCopy.minutes),
                const SizedBox(width: 14),
                unit(twoDigitCount(duration.seconds), MilestoneCopy.seconds),
              ],
            ),
          ),
        ],
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
