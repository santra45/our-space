import 'package:flutter/material.dart';

import '../../sky/sky.dart';

@immutable
class SkyStat {
  const SkyStat({
    required this.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.valueColor,
    this.iconColor,
    this.onTap,
  });

  final Key key;
  final SkyIcons icon;
  final String value;
  final String label;
  final Color valueColor;
  final Color? iconColor;
  final VoidCallback? onTap;
}

class SkyStatsRow extends StatelessWidget {
  const SkyStatsRow({super.key, required this.stats});

  final List<SkyStat> stats;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final children = <Widget>[];
    for (var i = 0; i < stats.length; i++) {
      if (i > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SizedBox(width: 1, child: ColoredBox(color: t.muted.withValues(alpha: 0.22))),
          ),
        );
      }
      children.add(Expanded(child: _StatCell(stat: stats[i])));
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.surface2.withValues(alpha: 0.6), t.surface),
        borderRadius: SkyRadii.all(SkyRadii.tile),
        border: Border.all(color: t.chipBorder),
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.stat});

  final SkyStat stat;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final motion = skyMotionAllowed(context);
    final value = Row(
      key: ValueKey<String>(stat.value),
      mainAxisSize: MainAxisSize.min,
      children: [
        SkyIcon(stat.icon, size: 14, color: stat.iconColor ?? stat.valueColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            stat.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SkyType.stat.copyWith(color: stat.valueColor),
          ),
        ),
      ],
    );
    return SkyPressable(
      key: stat.key,
      onTap: stat.onTap,
      pressedScale: 0.94,
      semanticLabel: '${stat.value} ${stat.label}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (motion)
              AnimatedSwitcher(
                duration: SkyMotion.base,
                switchInCurve: SkyMotion.standard,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                child: value,
              )
            else
              value,
            const SizedBox(height: 2),
            Text(
              stat.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: SkyType.sans(10.5, height: 1.3).copyWith(color: t.muted),
            ),
          ],
        ),
      ),
    );
  }
}
