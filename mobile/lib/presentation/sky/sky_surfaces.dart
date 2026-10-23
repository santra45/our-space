import 'package:flutter/material.dart';

import 'sky_controls.dart';
import 'sky_icons.dart';
import 'sky_metrics.dart';
import 'sky_motion.dart';
import 'sky_tokens.dart';
import 'sky_type.dart';

class SkyCard extends StatelessWidget {
  const SkyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = SkyRadii.card,
    this.onTap,
    this.semanticLabel,
    this.borderColor,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Color? borderColor;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient ?? t.cardGradient,
        borderRadius: SkyRadii.all(radius),
        border: Border.all(color: borderColor ?? t.cardBorder),
        boxShadow: t.cardShadow,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return SkyPressable(onTap: onTap, semanticLabel: semanticLabel, pressedScale: 0.98, child: card);
  }
}

enum SkyAccent { rose, gold }

class SkyFeatureCard extends StatelessWidget {
  const SkyFeatureCard({
    super.key,
    required this.child,
    this.accent = SkyAccent.rose,
    this.padding = const EdgeInsets.all(18),
    this.radius = SkyRadii.feature,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final SkyAccent accent;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final String? semanticLabel;

  Color glow(SkyTokens t) {
    if (accent == SkyAccent.rose) return t.isNight ? const Color(0x38FF6B95) : const Color(0x24FF6B95);
    return t.isNight ? const Color(0x2EFFD98A) : const Color(0x38FFB38A);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final tint = glow(t);
    final card = Container(
      decoration: BoxDecoration(
        gradient: t.featureGradient,
        borderRadius: SkyRadii.all(radius),
        border: Border.all(color: t.cardBorder),
        boxShadow: t.isDay ? t.shadow : const [],
      ),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: accent == SkyAccent.rose ? const Alignment(0.6, -1) : const Alignment(0.7, -1),
            radius: 1.2,
            colors: [tint, tint.withValues(alpha: 0)],
            stops: const [0, 0.6],
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (onTap == null) return card;
    return SkyPressable(onTap: onTap, semanticLabel: semanticLabel, pressedScale: 0.98, child: card);
  }
}

class SkyLabel extends StatelessWidget {
  const SkyLabel(this.text, {super.key, this.icon, this.tone = SkyTone.muted, this.center = false});

  final String text;
  final SkyIcons? icon;
  final SkyTone tone;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final color = tone.foreground(context.sky);
    return Row(
      mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        if (icon != null) ...[SkyIcon(icon!, size: 12, color: color), const SizedBox(width: 6)],
        Flexible(
          child: Text(text.toUpperCase(), style: SkyType.label.copyWith(color: color)),
        ),
      ],
    );
  }
}

class SkySectionHeader extends StatelessWidget {
  const SkySectionHeader({super.key, required this.title, this.action, this.onAction, this.trailing});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: SkyType.headlineSmall.copyWith(color: t.text)),
          ),
        ),
        if (trailing != null) trailing!,
        if (action != null)
          SkyPressable(
            onTap: onAction,
            semanticLabel: action,
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                action!,
                style: SkyType.sans(12, weight: FontWeight.w600).copyWith(color: t.rose),
              ),
            ),
          ),
      ],
    );
  }
}

class SkyDivider extends StatelessWidget {
  const SkyDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: SizedBox(height: 1, child: ColoredBox(color: context.sky.hairline)),
    );
  }
}

class SkyNameLabel extends StatelessWidget {
  const SkyNameLabel(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Text(
      name,
      textAlign: TextAlign.center,
      style: SkyType.name.copyWith(
        color: t.label,
        shadows: [Shadow(color: t.nameShadow, offset: const Offset(0, 1), blurRadius: t.isNight ? 6 : 8)],
      ),
    );
  }
}

class SkyHereChip extends StatelessWidget {
  const SkyHereChip({super.key, this.label = 'here now', this.pulse = true});

  final String label;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final dot = Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: t.rose,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: t.rose, blurRadius: 6)],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: t.hereBg,
        borderRadius: SkyRadii.all(SkyRadii.pill),
        border: Border.all(color: t.hereBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pulse && skyMotionAllowed(context) ? SkyPulse(child: dot) : dot,
          const SizedBox(width: 4),
          Text(label, style: SkyType.tiny.copyWith(color: t.hereText)),
        ],
      ),
    );
  }
}

class SkyPulse extends StatefulWidget {
  const SkyPulse({
    super.key,
    required this.child,
    this.period = SkyMotion.presence,
    this.minScale = 0.8,
    this.maxScale = 1.15,
  });

  final Widget child;
  final Duration period;
  final double minScale;
  final double maxScale;

  @override
  State<SkyPulse> createState() => _SkyPulseState();
}

class _SkyPulseState extends State<SkyPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.period ~/ 2)
    ..repeat(reverse: true);
  late final Animation<double> _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!skyMotionAllowed(context)) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: 0.45 + 0.55 * _curve.value,
        child: Transform.scale(
          scale: widget.minScale + (widget.maxScale - widget.minScale) * _curve.value,
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

class SkyTip extends StatelessWidget {
  const SkyTip({super.key, required this.text, this.icon, this.onTap}) : title = null, subtitle = null, arrow = false;

  const SkyTip.two({
    super.key,
    required String this.title,
    required String this.subtitle,
    this.icon,
    this.arrow = true,
    this.onTap,
  }) : text = '';

  final String text;
  final String? title;
  final String? subtitle;
  final SkyIcons? icon;
  final bool arrow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    const shadow = [BoxShadow(color: Color(0x40000000), offset: Offset(0, 8), blurRadius: 18.2)];
    Widget body;
    if (title == null) {
      body = Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: t.tipBg,
          borderRadius: SkyRadii.all(SkyRadii.pill),
          border: Border.all(color: t.tipBorder),
          boxShadow: shadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[SkyIcon(icon!, size: 11, color: t.tipText), const SizedBox(width: 6)],
            Text(text, style: SkyType.tip.copyWith(color: t.tipText)),
          ],
        ),
      );
    } else {
      body = Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: t.tipBg,
              borderRadius: SkyRadii.all(SkyRadii.md),
              border: Border.all(color: t.tipBorder),
              boxShadow: shadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[SkyIcon(icon!, size: 10, color: t.tipText), const SizedBox(width: 5)],
                    Text(
                      title!,
                      style: SkyType.sans(11, weight: FontWeight.w700, height: 1.3).copyWith(color: t.tipText),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle!,
                  style: SkyType.sans(10.5, weight: FontWeight.w700, height: 1.3).copyWith(color: t.rose),
                ),
              ],
            ),
          ),
          if (arrow)
            Positioned(
              left: -4,
              top: 14,
              child: Transform.rotate(
                angle: 0.785398,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: t.tipBg,
                    border: Border(
                      left: BorderSide(color: t.tipBorder),
                      bottom: BorderSide(color: t.tipBorder),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    final label = title == null ? text : '$title, $subtitle';
    if (onTap == null) return Semantics(label: label, excludeSemantics: true, child: body);
    return SkyPressable(onTap: onTap, semanticLabel: label, excludeSemantics: true, child: body);
  }
}

enum SkyNoticeTone { info, warning, error, love }

class SkyNotice extends StatelessWidget {
  const SkyNotice({
    super.key,
    required this.text,
    this.tone = SkyNoticeTone.info,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.dismissLabel = 'Dismiss',
    this.elevated = false,
  });

  final String text;
  final SkyNoticeTone tone;
  final SkyIcons? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;
  final String dismissLabel;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    late final Color accent;
    late final Color bg;
    late final Color border;
    late final SkyIcons glyph;
    switch (tone) {
      case SkyNoticeTone.info:
        accent = t.lavender;
        bg = elevated ? t.surface2 : t.chip;
        border = t.chipBorder;
        glyph = SkyIcons.info;
      case SkyNoticeTone.warning:
        accent = t.gold;
        bg = elevated ? Color.alphaBlend(t.goldSoft, t.surface) : t.goldSoft;
        border = t.gold.withValues(alpha: 0.35);
        glyph = SkyIcons.alert;
      case SkyNoticeTone.error:
        accent = t.rose;
        bg = elevated ? Color.alphaBlend(t.roseSoft, t.surface) : t.roseSoft;
        border = t.roseBorder;
        glyph = SkyIcons.alert;
      case SkyNoticeTone.love:
        accent = t.rose;
        bg = elevated ? Color.alphaBlend(t.roseSoft, t.surface) : t.roseSoft;
        border = t.roseBorder;
        glyph = SkyIcons.heart;
    }
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: SkyRadii.all(SkyRadii.tile),
          border: Border.all(color: border),
          boxShadow: elevated ? t.softShadow : const [],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: SkyIcon(icon ?? glyph, size: 18, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(text, style: SkyType.bodySmall.copyWith(color: t.text)),
                  if (actionLabel != null) ...[
                    const SizedBox(height: 6),
                    SkyPressable(
                      onTap: onAction,
                      semanticLabel: actionLabel,
                      excludeSemantics: true,
                      child: Text(
                        actionLabel!,
                        style: SkyType.sans(12, weight: FontWeight.w700).copyWith(color: accent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onDismiss != null) ...[
              const SizedBox(width: 8),
              SkyPressable(
                onTap: onDismiss,
                semanticLabel: dismissLabel,
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: SkyIcon(SkyIcons.close, size: 16, color: t.muted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SkyEmptyState extends StatelessWidget {
  const SkyEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = SkyIcons.sparkle,
    this.tone = SkyTone.gold,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final SkyIcons icon;
  final SkyTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkyIconTile(icon: icon, tone: tone, size: 56, iconSize: 26),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: SkyType.serif(20, weight: FontWeight.w500).copyWith(color: t.text),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: SkyType.bodySmall.copyWith(color: t.muted),
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            SkyButton(
              label: actionLabel!,
              onPressed: onAction,
              variant: SkyButtonVariant.ghost,
              expand: false,
              height: 44,
            ),
          ],
        ],
      ),
    );
  }
}

class SkyErrorState extends StatelessWidget {
  const SkyErrorState({
    super.key,
    this.title = 'Something went quiet',
    this.message = 'Nothing was lost. Give it another try.',
    this.retryLabel = 'Try again',
    this.onRetry,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return SkyEmptyState(
      title: title,
      message: message,
      icon: SkyIcons.alert,
      tone: SkyTone.rose,
      actionLabel: onRetry == null ? null : retryLabel,
      onAction: onRetry,
    );
  }
}

class SkyListGroup extends StatelessWidget {
  const SkyListGroup({super.key, this.label, required this.children});

  final String? label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: SkyLabel(label!)),
        Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: SkyRadii.all(SkyRadii.card),
            border: Border.all(color: t.cardBorder),
            boxShadow: t.isDay ? t.softShadow : const [],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SkyDivider(), children[i]],
            ],
          ),
        ),
      ],
    );
  }
}

class SkyListRow extends StatelessWidget {
  const SkyListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.tone = SkyTone.rose,
    this.value,
    this.trailing,
    this.onTap,
    this.chevron,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final SkyIcons? icon;
  final SkyTone tone;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool? chevron;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final showChevron = chevron ?? (onTap != null && trailing == null);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          if (icon != null) ...[SkyIconTile(icon: icon!, tone: tone), const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: SkyType.bodyStrong.copyWith(color: t.text)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: SkyType.small.copyWith(color: t.muted)),
                ],
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SkyType.sans(12.5).copyWith(color: t.muted),
              ),
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          if (showChevron) ...[const SizedBox(width: 4), SkyIcon(SkyIcons.chevron, size: 15, color: t.muted)],
        ],
      ),
    );
    if (onTap == null) return row;
    return SkyPressable(onTap: onTap, pressedScale: 0.985, semanticLabel: semanticLabel ?? title, child: row);
  }
}
