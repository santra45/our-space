import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import 'bucket_copy.dart';

class DreamRow extends StatelessWidget {
  const DreamRow({super.key, required this.item, required this.onToggle, required this.onOpen});

  final BucketListRecord item;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  String? get category {
    final value = item.fields['category'];
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final done = item.completed;
    final duration = skyMotionAllowed(context) ? SkyMotion.quick : Duration.zero;
    final tag = category;
    final main = SkyPressable(
      onTap: onToggle,
      onLongPress: onOpen,
      pressedScale: 0.98,
      selected: done,
      semanticLabel: done ? BucketCopy.done(item.text) : item.text,
      excludeSemantics: true,
      child: SkyTapTarget(
        child: Row(
          children: [
            DreamCheck(done: done),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: duration,
                curve: SkyMotion.standard,
                style: SkyType.sans(14, height: 1.35).copyWith(
                  color: done ? t.muted : t.text,
                  decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
                  decorationColor: t.faint,
                ),
                child: Text(item.text),
              ),
            ),
            if (tag != null) ...[const SizedBox(width: 8), DreamTag(label: dreamCategoryLabel(tag))],
          ],
        ),
      ),
    );
    return Row(
      children: [
        Expanded(child: main),
        SkyPressable(
          onTap: onOpen,
          semanticLabel: BucketCopy.change,
          excludeSemantics: true,
          child: SkyTapTarget.square(
            alignment: Alignment.centerRight,
            child: SkyIcon(SkyIcons.dots, size: 18, color: t.faint),
          ),
        ),
      ],
    );
  }
}

class DreamTag extends StatelessWidget {
  const DreamTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: t.roseSoft, borderRadius: SkyRadii.all(SkyRadii.pill)),
      child: Text(label, style: SkyType.sans(10, weight: FontWeight.w700, height: 1.3).copyWith(color: t.rose)),
    );
  }
}

class DreamCheck extends StatefulWidget {
  const DreamCheck({super.key, required this.done});

  static const double size = 26;
  static const Color ink = Color(0xFF1B1838);
  static const Color sunset = Color(0xFFF2A65A);

  final bool done;

  @override
  State<DreamCheck> createState() => _DreamCheckState();
}

class _DreamCheckState extends State<DreamCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(vsync: this, duration: SkyMotion.slow, value: 1);
  late final Animation<double> _scale = Tween<double>(
    begin: 0.3,
    end: 1,
  ).animate(CurvedAnimation(parent: _pop, curve: const SkySpringCurve(SkyMotion.popSpring, seconds: 0.5)));

  @override
  void didUpdateWidget(covariant DreamCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.done && widget.done && skyMotionAllowed(context)) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final done = widget.done;
    return AnimatedContainer(
      duration: skyMotionAllowed(context) ? SkyMotion.quick : Duration.zero,
      curve: SkyMotion.standard,
      width: DreamCheck.size,
      height: DreamCheck.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: done
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [t.gold, DreamCheck.sunset],
              )
            : null,
        border: Border.all(color: done ? t.gold.withValues(alpha: 0) : t.faint, width: 1.5),
        boxShadow: done && t.isNight ? [BoxShadow(color: t.gold.withValues(alpha: 0.35), blurRadius: 10)] : const [],
      ),
      alignment: Alignment.center,
      child: done
          ? ScaleTransition(
              scale: _scale,
              child: const SkyIcon(SkyIcons.check, size: 14, color: DreamCheck.ink),
            )
          : null,
    );
  }
}
