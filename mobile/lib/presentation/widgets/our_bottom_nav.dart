import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';
import 'app_haptics.dart';
import 'css_box.dart';
import 'lucide_icon.dart';

@immutable
class OurNavItem {
  const OurNavItem({required this.label, required this.icon});

  final String label;
  final LucideIconData icon;
}

class OurBottomNav extends StatefulWidget {
  const OurBottomNav({super.key, required this.items, required this.selectedIndex, required this.onSelect});

  final List<OurNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  static const double itemHeight = 47;
  static final Color background = AppColors.white.withValues(alpha: 0.85);
  static const double backdropBlur = 16;

  static double heightFor(double safeBottom) =>
      AppLayout.navTopPadding + itemHeight + AppLayout.navBottomPadding + safeBottom + 1;

  @override
  State<OurBottomNav> createState() => _OurBottomNavState();
}

class _OurBottomNavState extends State<OurBottomNav> with SingleTickerProviderStateMixin {
  late final AnimationController _pill = AnimationController.unbounded(vsync: this, value: 1);
  Rect? _from;
  Rect? _current;

  @override
  void didUpdateWidget(covariant OurBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _from = _current;
      _pill.value = 0;
      _pill.animateWith(SpringSimulation(AppMotion.navPillSpring, 0, 1, 0));
    }
  }

  @override
  void dispose() {
    _pill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return CssBox(
      padding: EdgeInsets.fromLTRB(
        AppLayout.navSidePadding,
        AppLayout.navTopPadding,
        AppLayout.navSidePadding,
        AppLayout.navBottomPadding + safeBottom,
      ),
      color: OurBottomNav.background,
      border: const Border(top: BorderSide(color: AppColors.blush100)),
      shadows: AppShadows.bottomNav,
      backdropBlur: OurBottomNav.backdropBlur,
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthMd),
          child: CustomMultiChildLayout(
            delegate: _NavLayout(
              count: widget.items.length,
              selected: widget.selectedIndex,
              progress: _pill,
              from: _from,
              onPill: (rect) => _current = rect,
            ),
            children: [
              LayoutId(
                id: _NavLayout.pillId,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: AppColors.blush100, borderRadius: AppRadii.all(AppRadii.x2l)),
                ),
              ),
              for (var i = 0; i < widget.items.length; i++)
                LayoutId(
                  id: i,
                  child: _NavButton(
                    item: widget.items[i],
                    active: i == widget.selectedIndex,
                    onTap: () {
                      AppHaptics.tick();
                      widget.onSelect(i);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavLayout extends MultiChildLayoutDelegate {
  _NavLayout({
    required this.count,
    required this.selected,
    required this.progress,
    required this.from,
    required this.onPill,
  }) : super(relayout: progress);

  static const Object pillId = 'pill';

  final int count;
  final int selected;
  final Animation<double> progress;
  final Rect? from;
  final ValueChanged<Rect> onPill;

  @override
  Size getSize(BoxConstraints constraints) {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 360.0;
    return constraints.constrain(Size(width, OurBottomNav.itemHeight));
  }

  @override
  void performLayout(Size size) {
    final sizes = <Size>[];
    for (var i = 0; i < count; i++) {
      sizes.add(layoutChild(i, BoxConstraints.loose(size)));
    }
    final used = sizes.fold<double>(0, (sum, s) => sum + s.width);
    final gap = count == 0 ? 0.0 : (size.width - used) / count;
    final rects = <Rect>[];
    var x = gap / 2;
    for (var i = 0; i < count; i++) {
      final s = sizes[i];
      final rect = Offset(x, (size.height - s.height) / 2) & s;
      positionChild(i, rect.topLeft);
      rects.add(rect);
      x += s.width + gap;
    }
    if (count == 0 || selected < 0 || selected >= count) {
      layoutChild(pillId, BoxConstraints.tight(Size.zero));
      positionChild(pillId, Offset.zero);
      return;
    }
    final target = rects[selected];
    final t = progress.value;
    final start = from ?? target;
    final rect = Rect.fromLTRB(
      start.left + (target.left - start.left) * t,
      start.top + (target.top - start.top) * t,
      start.right + (target.right - start.right) * t,
      start.bottom + (target.bottom - start.bottom) * t,
    );
    final safe = Rect.fromLTWH(rect.left, rect.top, rect.width.clamp(0, double.infinity), rect.height.clamp(0, double.infinity));
    layoutChild(pillId, BoxConstraints.tight(safe.size));
    positionChild(pillId, safe.topLeft);
    onPill(safe);
  }

  @override
  bool shouldRelayout(_NavLayout oldDelegate) {
    return oldDelegate.count != count || oldDelegate.selected != selected || oldDelegate.from != from;
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.onTap});

  static final SpringCurve _iconCurve = SpringCurve(stiffness: 350, damping: 20);

  final OurNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: active ? 1 : 0),
                duration: _iconCurve.duration,
                curve: _iconCurve,
                builder: (context, t, child) => Transform.translate(
                  offset: Offset(0, -2 * t),
                  child: Transform.scale(scale: 1 + 0.15 * t, child: child),
                ),
                child: LucideIcon(
                  item.icon,
                  size: 20,
                  color: active ? AppColors.blush500 : AppColors.slate400,
                  fill: active ? AppColors.blush200 : null,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: DefaultTextStyle.of(context).style.merge(Tw.px10.semibold.c(active ? AppColors.blush600 : AppColors.slate400)),
                child: Text(item.label, maxLines: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
