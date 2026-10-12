import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_shadows.dart';
import 'css_box.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = AppRadii.x3l,
    this.onTap,
    this.opacity = 1,
    this.clipContent = false,
    this.blur,
    this.semanticLabel,
  });

  static bool blurByDefault = true;

  static final Color fill = AppColors.white.withValues(alpha: 0.72);
  static final Color edge = AppColors.white.withValues(alpha: 0.85);
  static const double backdropBlur = 16;

  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;
  final VoidCallback? onTap;
  final double opacity;
  final bool clipContent;
  final bool? blur;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget card = CssBox(
      padding: padding,
      color: fill,
      border: Border.all(color: edge),
      borderRadius: AppRadii.all(borderRadius),
      shadows: AppShadows.glassPanel,
      backdropBlur: (blur ?? blurByDefault) ? backdropBlur : 0,
      clipContent: clipContent,
      opacity: opacity,
      child: child,
    );
    if (onTap != null) {
      card = Semantics(
        button: true,
        label: semanticLabel,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: card),
      );
    }
    return card;
  }
}
