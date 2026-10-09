import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';
import 'app_haptics.dart';
import 'css_box.dart';
import 'lucide_icon.dart';

enum BouncyVariant { primary, secondary, matcha, lavender, ghost }

class BouncyStyle {
  const BouncyStyle({
    required this.foreground,
    this.color,
    this.gradient,
    this.border,
    this.shadows = const [],
  });

  final Color foreground;
  final Color? color;
  final Gradient? gradient;
  final Border? border;
  final List<BoxShadow> shadows;

  static BouncyStyle of(BouncyVariant variant) {
    switch (variant) {
      case BouncyVariant.primary:
        return BouncyStyle(
          foreground: AppColors.white,
          gradient: AppGradients.buttonPrimary,
          shadows: AppShadows.primaryButton,
        );
      case BouncyVariant.secondary:
        return BouncyStyle(
          foreground: AppColors.blush600,
          color: AppColors.white.withValues(alpha: 0.8),
          border: Border.all(color: AppColors.blush200),
          shadows: AppShadows.sm,
        );
      case BouncyVariant.matcha:
        return BouncyStyle(
          foreground: AppColors.emerald800,
          gradient: AppGradients.buttonMatcha,
          shadows: AppShadows.sm,
        );
      case BouncyVariant.lavender:
        return BouncyStyle(
          foreground: AppColors.indigo900,
          gradient: AppGradients.buttonLavender,
          shadows: AppShadows.sm,
        );
      case BouncyVariant.ghost:
        return const BouncyStyle(foreground: AppColors.slate600);
    }
  }
}

class BouncyButton extends StatefulWidget {
  const BouncyButton({
    super.key,
    required this.onPressed,
    this.child,
    this.label,
    this.icon,
    this.trailingIcon,
    this.variant = BouncyVariant.primary,
    this.small = false,
    this.pill = false,
    this.expand = false,
    this.padding = defaultPadding,
    this.gap = 6,
    this.iconSize = 16,
    this.textStyle,
    this.shadows,
    this.enabled = true,
    this.haptic = true,
    this.semanticLabel,
  }) : assert(child != null || label != null || icon != null);

  static const EdgeInsets defaultPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 12);

  final VoidCallback? onPressed;
  final Widget? child;
  final String? label;
  final LucideIconData? icon;
  final LucideIconData? trailingIcon;
  final BouncyVariant variant;
  final bool small;
  final bool pill;
  final bool expand;
  final EdgeInsets padding;
  final double gap;
  final double iconSize;
  final TextStyle? textStyle;
  final List<BoxShadow>? shadows;
  final bool enabled;
  final bool haptic;
  final String? semanticLabel;

  bool get isEnabled => enabled && onPressed != null;

  @override
  State<BouncyButton> createState() => _BouncyButtonState();
}

class _BouncyButtonState extends State<BouncyButton> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: 1);
  bool _pressed = false;

  void _springTo(double target) {
    _scale.animateWith(SpringSimulation(AppMotion.buttonSpring, _scale.value, target, _scale.velocity));
  }

  void _down() {
    if (!widget.isEnabled) return;
    setState(() => _pressed = true);
    _springTo(0.94);
  }

  void _up() {
    if (_pressed) setState(() => _pressed = false);
    _springTo(1);
  }

  void _tap() {
    if (!widget.isEnabled) return;
    if (widget.haptic) AppHaptics.tick();
    widget.onPressed?.call();
  }

  @override
  void didUpdateWidget(covariant BouncyButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isEnabled && (_pressed || _scale.value != 1)) {
      _pressed = false;
      _scale.stop();
      _scale.value = 1;
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = BouncyStyle.of(widget.variant);
    final radius = AppRadii.all(widget.pill ? AppRadii.full : AppRadii.x2l);
    final base = (widget.small ? Tw.xs : Tw.sm).semibold.c(style.foreground).merge(widget.textStyle);
    final fg = base.color ?? style.foreground;

    final parts = <Widget>[
      if (widget.icon != null) LucideIcon(widget.icon!, size: widget.iconSize, color: fg),
      if (widget.label != null)
        widget.expand
            ? Flexible(child: Text(widget.label!, style: base, textAlign: TextAlign.center))
            : Text(widget.label!, style: base, textAlign: TextAlign.center),
      if (widget.child != null) widget.child!,
      if (widget.trailingIcon != null) LucideIcon(widget.trailingIcon!, size: widget.iconSize, color: fg),
    ];

    final row = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) SizedBox(width: widget.gap),
          parts[i],
        ],
      ],
    );

    Widget body = CssBox(
      padding: widget.padding,
      color: style.color,
      gradient: style.gradient,
      border: style.border,
      borderRadius: radius,
      shadows: _pressed ? const [] : (widget.shadows ?? style.shadows),
      child: DefaultTextStyle.merge(
        style: base,
        child: IconTheme.merge(data: IconThemeData(color: fg, size: widget.iconSize), child: row),
      ),
    );

    if (_pressed) {
      body = CustomPaint(
        foregroundPainter: InsetShadowPainter(borderRadius: radius, color: const Color(0x0D000000)),
        child: body,
      );
    }

    if (widget.expand) {
      body = SizedBox(width: double.infinity, child: body);
    }

    return Semantics(
      container: true,
      button: true,
      enabled: widget.isEnabled,
      label: widget.semanticLabel,
      child: Opacity(
        opacity: widget.isEnabled ? 1 : 0.5,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _down(),
          onTapUp: (_) => _up(),
          onTapCancel: _up,
          onTap: widget.isEnabled ? _tap : null,
          child: AnimatedBuilder(
            animation: _scale,
            builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
            child: body,
          ),
        ),
      ),
    );
  }
}
