import 'package:flutter/material.dart';

import 'sky_icons.dart';
import 'sky_metrics.dart';
import 'sky_motion.dart';
import 'sky_tokens.dart';
import 'sky_type.dart';

@immutable
class SkyDockItem {
  const SkyDockItem({required this.label, required this.icon});

  final String label;
  final SkyIcons icon;
}

class SkyDock extends StatelessWidget {
  const SkyDock({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    this.onLove,
    this.loveLabel = 'Send love',
  }) : assert(items.length == 4);

  final List<SkyDockItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback? onLove;
  final String loveLabel;

  static const double lift = SkySizes.dockLoveLift;
  static const double height = SkySizes.dockHeight + lift;

  static double clearance(BuildContext context) => SkySizes.dockClearance(MediaQuery.viewPaddingOf(context).bottom);

  Widget _slot(BuildContext context, int index) {
    final item = items[index];
    final active = index == selectedIndex;
    return Flexible(
      key: ValueKey<String>('sky-dock-${item.label}'),
      flex: active ? 0 : 1,
      fit: FlexFit.tight,
      child: _DockSlot(item: item, active: active, onTap: () => onSelect(index)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: SkySizes.dockHeight,
            child: Container(
              decoration: BoxDecoration(
                color: t.dock,
                borderRadius: SkyRadii.all(SkyRadii.pill),
                border: Border.all(color: t.dockBorder),
                boxShadow: t.dockShadow,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _slot(context, 0),
                  _slot(context, 1),
                  const SizedBox(width: SkySizes.dockLoveOuter),
                  _slot(context, 2),
                  _slot(context, 3),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: SkyLoveButton(onTap: onLove, semanticLabel: loveLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _DockSlot extends StatelessWidget {
  const _DockSlot({required this.item, required this.active, required this.onTap});

  final SkyDockItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final motion = skyMotionAllowed(context);
    final Widget face = active
        ? Container(
            key: const ValueKey<String>('active'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: t.activeBg,
              borderRadius: SkyRadii.all(SkyRadii.pill),
              boxShadow: t.isNight
                  ? [BoxShadow(color: t.activeGlow, offset: const Offset(0, 2), blurRadius: 11.3)]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SkyIcon(item.icon, size: 15, color: t.activeFg),
                const SizedBox(width: 6),
                Text(item.label, maxLines: 1, style: SkyType.dockActive.copyWith(color: t.activeFg)),
              ],
            ),
          )
        : SizedBox(
            key: const ValueKey<String>('idle'),
            width: SkySizes.dockSlotWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SkyIcon(item.icon, size: 21, color: t.dockIcon),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: SkyType.dock.copyWith(color: t.dockIcon),
                ),
              ],
            ),
          );
    return SkyPressable(
      onTap: onTap,
      semanticLabel: item.label,
      selected: active,
      excludeSemantics: true,
      child: Center(
        child: !motion
            ? face
            : AnimatedSize(
                duration: SkyMotion.base,
                curve: SkyMotion.standard,
                clipBehavior: Clip.none,
                child: AnimatedSwitcher(
                  duration: SkyMotion.quick,
                  switchInCurve: SkyMotion.standard,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: Tween<double>(begin: 0.86, end: 1).animate(animation), child: child),
                  ),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      for (final child in previous)
                        Positioned.fill(
                          child: OverflowBox(maxWidth: double.infinity, maxHeight: double.infinity, child: child),
                        ),
                      ?current,
                    ],
                  ),
                  child: face,
                ),
              ),
      ),
    );
  }
}

class SkyLoveButton extends StatelessWidget {
  const SkyLoveButton({super.key, this.onTap, this.semanticLabel = 'Send love', this.size = SkySizes.dockLoveOuter});

  final VoidCallback? onTap;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final inner = size * SkySizes.dockLoveInner / SkySizes.dockLoveOuter;
    return SkyPressable(
      onTap: onTap,
      pressedScale: 0.9,
      semanticLabel: semanticLabel,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: t.surface,
          shape: BoxShape.circle,
          boxShadow: t.isNight
              ? const [BoxShadow(color: Color(0x40000000), offset: Offset(0, 10), blurRadius: 18.2)]
              : const [
                  BoxShadow(color: Color(0x40FF6B95), blurRadius: 14, spreadRadius: 2),
                  BoxShadow(color: Color(0x1F000000), offset: Offset(0, 10), blurRadius: 18.2),
                ],
        ),
        alignment: Alignment.center,
        child: Container(
          width: inner,
          height: inner,
          decoration: BoxDecoration(
            gradient: t.roseOrbGradient,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x59FFFFFF)),
            boxShadow: const [BoxShadow(color: Color(0x99FF6B95), blurRadius: 14.7)],
          ),
          alignment: Alignment.center,
          child: SkyIcon(SkyIcons.heart, size: inner * 22 / 48, color: SkyTokens.white),
        ),
      ),
    );
  }
}
