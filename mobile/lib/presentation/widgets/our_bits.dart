import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';
import 'app_haptics.dart';
import 'app_icons.dart';
import 'css_box.dart';
import 'lucide_icon.dart';

class OurPill extends StatelessWidget {
  const OurPill({
    super.key,
    required this.label,
    this.icon,
    this.iconColor,
    this.iconFill,
    this.background = AppColors.blush100,
    this.foreground = AppColors.blush600,
    this.border,
    this.textStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    this.iconSize = 14,
    this.gap = 6,
    this.shadows = const [],
  });

  factory OurPill.blush({Key? key, required String label, LucideIconData? icon}) => OurPill(
    key: key,
    label: label,
    icon: icon,
    background: AppColors.blush100.withValues(alpha: 0.7),
    foreground: AppColors.blush600,
  );

  factory OurPill.lavender({Key? key, required String label, LucideIconData? icon}) => OurPill(
    key: key,
    label: label,
    icon: icon,
    iconColor: AppColors.lavender500,
    background: AppColors.lavender100,
    foreground: AppColors.lavender700,
  );

  factory OurPill.indigo({Key? key, required String label, LucideIconData? icon}) => OurPill(
    key: key,
    label: label,
    icon: icon,
    iconColor: AppColors.indigo500,
    background: AppColors.indigo50,
    foreground: AppColors.indigo700,
    border: AppColors.indigo100,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    textStyle: Tw.xs.bold,
  );

  factory OurPill.amber({Key? key, required String label, LucideIconData? icon}) => OurPill(
    key: key,
    label: label,
    icon: icon,
    iconColor: AppColors.amber500,
    background: AppColors.amber50,
    foreground: AppColors.amber800,
    border: AppColors.amber200,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    textStyle: Tw.xs.bold,
  );

  factory OurPill.slate({Key? key, required String label, LucideIconData? icon}) => OurPill(
    key: key,
    label: label,
    icon: icon,
    background: AppColors.slate200.withValues(alpha: 0.8),
    foreground: AppColors.slate600,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    textStyle: Tw.px10.bold,
    iconSize: 12,
    gap: 4,
  );

  final String label;
  final LucideIconData? icon;
  final Color? iconColor;
  final Color? iconFill;
  final Color background;
  final Color foreground;
  final Color? border;
  final TextStyle? textStyle;
  final EdgeInsets padding;
  final double iconSize;
  final double gap;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    return CssBox(
      padding: padding,
      color: background,
      border: border == null ? null : Border.all(color: border!),
      borderRadius: AppRadii.all(AppRadii.full),
      shadows: shadows,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            LucideIcon(icon!, size: iconSize, color: iconColor ?? foreground, fill: iconFill),
            SizedBox(width: gap),
          ],
          Flexible(child: Text(label, style: (textStyle ?? Tw.xs.semibold).c(foreground))),
        ],
      ),
    );
  }
}

class OurTag extends StatelessWidget {
  const OurTag(this.label, {super.key, this.background = AppColors.blush100, this.foreground = AppColors.blush500});

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return CssBox(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      color: background,
      borderRadius: AppRadii.all(AppRadii.full),
      child: Text(label.toUpperCase(), style: Tw.px10.bold.trackingWider.c(foreground)),
    );
  }
}

class OurIconCircle extends StatelessWidget {
  const OurIconCircle({
    super.key,
    required this.icon,
    this.size = 32,
    this.iconSize = 16,
    this.background = AppColors.blush100,
    this.foreground = AppColors.blush500,
    this.iconFill,
    this.gradient,
    this.border,
    this.shadows = const [],
    this.radius,
  });

  final LucideIconData icon;
  final double size;
  final double iconSize;
  final Color background;
  final Color foreground;
  final Color? iconFill;
  final Gradient? gradient;
  final Border? border;
  final List<BoxShadow> shadows;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return CssBox(
      width: size,
      height: size,
      color: gradient == null ? background : null,
      gradient: gradient,
      border: border,
      borderRadius: AppRadii.all(radius ?? AppRadii.full),
      shadows: shadows,
      child: Center(child: LucideIcon(icon, size: iconSize, color: foreground, fill: iconFill)),
    );
  }
}

class OurIconButton extends StatelessWidget {
  const OurIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 28,
    this.iconSize = 14,
    this.background,
    this.foreground = AppColors.slate300,
    this.radius = AppRadii.lg,
    this.semanticLabel,
    this.haptic = true,
    this.border,
    this.shadows = const [],
  });

  factory OurIconButton.add({Key? key, required VoidCallback? onPressed, String? semanticLabel}) => OurIconButton(
    key: key,
    icon: AppIcons.plus,
    onPressed: onPressed,
    iconSize: 16,
    background: AppColors.blush100,
    foreground: AppColors.blush600,
    radius: AppRadii.full,
    semanticLabel: semanticLabel,
  );

  factory OurIconButton.edit({Key? key, required VoidCallback? onPressed, String? semanticLabel}) => OurIconButton(
    key: key,
    icon: AppIcons.pencil,
    onPressed: onPressed,
    semanticLabel: semanticLabel,
  );

  factory OurIconButton.delete({Key? key, required VoidCallback? onPressed, String? semanticLabel, double size = 28, double iconSize = 14, double radius = AppRadii.lg}) => OurIconButton(
    key: key,
    icon: AppIcons.trash2,
    onPressed: onPressed,
    size: size,
    iconSize: iconSize,
    radius: radius,
    semanticLabel: semanticLabel,
  );

  final LucideIconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? background;
  final Color foreground;
  final double radius;
  final String? semanticLabel;
  final bool haptic;
  final Border? border;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed == null
            ? null
            : () {
                if (haptic) AppHaptics.tap();
                onPressed!();
              },
        child: Opacity(
          opacity: onPressed == null ? 0.4 : 1,
          child: CssBox(
            width: size,
            height: size,
            color: background,
            border: border,
            shadows: shadows,
            borderRadius: AppRadii.all(radius),
            child: Center(child: LucideIcon(icon, size: iconSize, color: foreground)),
          ),
        ),
      ),
    );
  }
}

class OurTextLink extends StatelessWidget {
  const OurTextLink({
    super.key,
    required this.text,
    required this.onTap,
    this.style,
    this.color = AppColors.slate400,
    this.underline = true,
    this.icon,
    this.iconSize = 14,
    this.textAlign = TextAlign.center,
  });

  final String text;
  final VoidCallback? onTap;
  final TextStyle? style;
  final Color color;
  final bool underline;
  final LucideIconData? icon;
  final double iconSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    var resolved = (style ?? Tw.xs).c(color);
    if (underline) resolved = resolved.underline;
    final label = Text(text, textAlign: textAlign, style: resolved);
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                AppHaptics.tick();
                onTap!();
              },
        child: icon == null
            ? label
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LucideIcon(icon!, size: iconSize, color: color),
                  const SizedBox(width: 6),
                  Flexible(child: label),
                ],
              ),
      ),
    );
  }
}

class OurSectionHeader extends StatelessWidget {
  const OurSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = AppIcons.sparkles,
    this.iconColor = AppColors.amber500,
    this.trailing,
    this.centered = false,
  });

  final String title;
  final String? subtitle;
  final LucideIconData? icon;
  final Color iconColor;
  final Widget? trailing;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final titleStyle = (centered ? Tw.x2l : Tw.xl).extrabold.trackingTight.c(AppColors.slate800);
    final titleRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(title, style: titleStyle, textAlign: centered ? TextAlign.center : TextAlign.start)),
        if (icon != null) ...[
          const SizedBox(width: 8),
          LucideIcon(icon!, size: centered ? 20 : 16, color: iconColor),
        ],
      ],
    );
    final column = Column(
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        titleRow,
        if (subtitle != null) ...[
          if (centered) const SizedBox(height: 2),
          Text(subtitle!, textAlign: centered ? TextAlign.center : TextAlign.start, style: Tw.xs.c(AppColors.slate500)),
        ],
      ],
    );
    if (centered) return Center(child: column);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(child: column),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class OurProgressBar extends StatefulWidget {
  const OurProgressBar({super.key, required this.value});

  final double value;

  @override
  State<OurProgressBar> createState() => _OurProgressBarState();
}

class _OurProgressBarState extends State<OurProgressBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(vsync: this, value: 0);

  @override
  void initState() {
    super.initState();
    _animateTo(widget.value);
  }

  void _animateTo(double target) {
    _controller.animateWith(
      SpringSimulation(AppMotion.progressSpring, _controller.value, target.clamp(0.0, 1.0), _controller.velocity),
    );
  }

  @override
  void didUpdateWidget(covariant OurProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _animateTo(widget.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: '${(widget.value.clamp(0.0, 1.0) * 100).round()}%',
      child: Stack(
        children: [
          CssBox(
            height: 12,
            padding: const EdgeInsets.all(2),
            color: AppColors.white,
            border: Border.all(color: AppColors.blush200.withValues(alpha: 0.8)),
            borderRadius: AppRadii.all(AppRadii.full),
            clipContent: true,
            child: LayoutBuilder(
              builder: (context, constraints) => AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final width = constraints.maxWidth * math.max(0.0, _controller.value);
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: CssBox(
                      width: width,
                      height: double.infinity,
                      gradient: AppGradients.progress,
                      borderRadius: AppRadii.all(AppRadii.full),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: InsetShadowPainter(
                  borderRadius: AppRadii.all(AppRadii.full),
                  color: const Color(0x0D000000),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WashiTape extends StatelessWidget {
  const WashiTape({super.key});

  static const double width = 72;
  static const double height = 22;
  static const double overhang = 12;

  static Widget over({Key? key, required Widget child}) {
    return Stack(
      key: key,
      clipBehavior: Clip.none,
      children: [
        child,
        const Positioned(top: -overhang, left: 0, right: 0, child: Center(child: WashiTape())),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: -1.5 * math.pi / 180,
        child: CustomPaint(
          foregroundPainter: _WashiEdgesPainter(),
          child: CssBox(
            width: width,
            height: height,
            color: const Color(0xBFFFEBF0),
            backdropBlur: 2,
            shadows: [AppShadows.css(const Color(0x0F000000), y: 1, blur: 3)],
          ),
        ),
      ),
    );
  }
}

class _WashiEdgesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x80FFB6C1)
      ..strokeWidth = 2;
    for (final x in [1.0, size.width - 1]) {
      var y = 0.0;
      while (y < size.height) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(size.height, y + 6)), paint);
        y += 12;
      }
    }
  }

  @override
  bool shouldRepaint(_WashiEdgesPainter oldDelegate) => false;
}

class OurDivider extends StatelessWidget {
  const OurDivider({super.key, this.color = AppColors.slate100, this.top = 0, this.bottom = 0});

  final Color color;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: SizedBox(height: 1, width: double.infinity, child: ColoredBox(color: color)),
    );
  }
}
