import 'package:flutter/material.dart';

import '../../../sky/sky.dart';

class SettingsRow extends StatelessWidget {
  const SettingsRow({
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

  static const double valueShare = 0.48;

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
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
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
                    AnimatedSwitcher(
                      duration: skyMotionAllowed(context) ? SkyMotion.quick : Duration.zero,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: AlignmentDirectional.topStart,
                        children: [...previous, if (current != null) current],
                      ),
                      child: Text(
                        subtitle!,
                        key: ValueKey<String>(subtitle!),
                        style: SkyType.small.copyWith(color: t.muted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: SkySpace.sm),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth * valueShare),
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: SkyType.sans(12.5).copyWith(color: t.muted),
                ),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            if (showChevron) ...[const SizedBox(width: 4), SkyIcon(SkyIcons.chevron, size: 15, color: t.muted)],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return SkyPressable(onTap: onTap, pressedScale: 0.985, semanticLabel: semanticLabel ?? title, child: row);
  }
}
