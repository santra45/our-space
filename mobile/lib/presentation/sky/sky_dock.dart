import 'dart:math' as math;

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

class SkyDock extends StatefulWidget {
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
  static const Key pillKey = ValueKey<String>('sky-dock-pill');

  static double clearance(BuildContext context) => SkySizes.dockClearance(MediaQuery.viewPaddingOf(context).bottom);

  @override
  State<SkyDock> createState() => _SkyDockState();
}

class _SkyDockState extends State<SkyDock> with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(vsync: this, duration: SkyMotion.dockSlide, value: 1);
  late int _from = widget.selectedIndex;

  @override
  void didUpdateWidget(SkyDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex) return;
    _from = oldWidget.selectedIndex;
    if (skyMotionAllowed(context)) {
      _slide.forward(from: 0);
    } else {
      _slide.value = 1;
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return SizedBox(
      height: SkyDock.height,
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
              child: LayoutBuilder(
                builder: (context, constraints) => AnimatedBuilder(
                  animation: _slide,
                  builder: (context, _) => _DockTrack(
                    items: widget.items,
                    from: _from,
                    to: widget.selectedIndex,
                    progress: _slide.value,
                    width: constraints.maxWidth,
                    onSelect: widget.onSelect,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: SkyLoveButton(onTap: widget.onLove, semanticLabel: widget.loveLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _DockTrack extends StatelessWidget {
  const _DockTrack({
    required this.items,
    required this.from,
    required this.to,
    required this.progress,
    required this.width,
    required this.onSelect,
  });

  final List<SkyDockItem> items;
  final int from;
  final int to;
  final double progress;
  final double width;
  final ValueChanged<int> onSelect;

  static const double padX = 14;
  static const double padY = 9;
  static const double iconGap = 6;
  static const double iconSize = 15;
  static const Curve glide = Curves.easeInOutCubic;
  static const double stretchCap = 26;
  static const double stretchShare = 0.16;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final pills = <double>[];
    var textHeight = 0.0;
    for (final item in items) {
      final painter = TextPainter(
        text: TextSpan(text: item.label, style: SkyType.dockActive),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      pills.add(padX * 2 + iconSize + iconGap + painter.width);
      if (painter.height > textHeight) textHeight = painter.height;
      painter.dispose();
    }
    final pillHeight = padY * 2 + (textHeight > iconSize ? textHeight : iconSize);

    final moving = from != to;
    final shift = SkyMotion.standard.transform(moving ? progress : 1);
    final active = List<double>.generate(items.length, (i) {
      if (i == to) return moving ? shift : 1;
      if (moving && i == from) return 1 - shift;
      return 0;
    });

    final room = (width - SkySizes.dockLoveOuter).clamp(0.0, double.infinity);
    var claimed = 0.0;
    var idleParts = 0.0;
    for (var i = 0; i < items.length; i++) {
      claimed += active[i] * pills[i];
      idleParts += 1 - active[i];
    }
    final idle = idleParts <= 0 ? 0.0 : (room - claimed) / idleParts;
    final widths = [for (var i = 0; i < items.length; i++) active[i] * pills[i] + (1 - active[i]) * idle];

    final lefts = <double>[];
    var x = 0.0;
    for (var i = 0; i < items.length; i++) {
      if (i == 2) x += SkySizes.dockLoveOuter;
      lefts.add(x);
      x += widths[i];
    }

    double pillLeft(int i) => lefts[i] + (widths[i] - pills[i]) / 2;

    var left = pillLeft(to);
    var right = left + pills[to];
    if (moving) {
      final startLeft = pillLeft(from);
      final startRight = startLeft + pills[from];
      final eased = glide.transform(progress);
      final endLeft = left;
      final endRight = right;
      left = _lerp(startLeft, endLeft, eased);
      right = _lerp(startRight, endRight, eased);
      final distance = (endLeft - startLeft).abs();
      final stretch = math.min(stretchCap, distance * stretchShare) * math.sin(math.pi * progress);
      if (to > from) {
        right += stretch;
      } else {
        left -= stretch;
      }
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: left,
          width: (right - left).clamp(0.0, double.infinity),
          top: 0,
          bottom: 0,
          child: Center(
            child: Container(
              key: SkyDock.pillKey,
              height: pillHeight,
              decoration: BoxDecoration(
                color: t.activeBg,
                borderRadius: SkyRadii.all(SkyRadii.pill),
                boxShadow: t.isNight
                    ? [BoxShadow(color: t.activeGlow, offset: const Offset(0, 2), blurRadius: 11.3)]
                    : const [],
              ),
            ),
          ),
        ),
        for (var i = 0; i < items.length; i++)
          Positioned(
            key: ValueKey<String>('sky-dock-${items[i].label}'),
            left: lefts[i],
            width: widths[i],
            top: 0,
            bottom: 0,
            child: _DockSlot(
              item: items[i],
              active: active[i],
              selected: i == to,
              onTap: () => onSelect(i),
            ),
          ),
      ],
    );
  }
}

class _DockSlot extends StatelessWidget {
  const _DockSlot({required this.item, required this.active, required this.selected, required this.onTap});

  final SkyDockItem item;
  final double active;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return SkyPressable(
      onTap: onTap,
      semanticLabel: item.label,
      selected: selected,
      excludeSemantics: true,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (active < 1)
            Opacity(
              opacity: 1 - active,
              child: OverflowBox(
                maxWidth: double.infinity,
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
              ),
            ),
          if (active > 0)
            Opacity(
              opacity: active,
              child: OverflowBox(
                maxWidth: double.infinity,
                child: Transform.scale(
                  scale: 0.9 + 0.1 * active,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SkyIcon(item.icon, size: _DockTrack.iconSize, color: t.activeFg),
                      const SizedBox(width: _DockTrack.iconGap),
                      Text(item.label, maxLines: 1, style: SkyType.dockActive.copyWith(color: t.activeFg)),
                    ],
                  ),
                ),
              ),
            ),
        ],
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
