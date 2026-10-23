import 'package:flutter/material.dart';

import '../../../sky/sky.dart';

class PersonChoice extends StatelessWidget {
  const PersonChoice({
    super.key,
    required this.name,
    required this.initial,
    this.detail,
    this.style = SkyAvatarStyle.me,
    this.onTap,
    this.enabled = true,
    this.busy = false,
  });

  final String name;
  final String initial;
  final String? detail;
  final SkyAvatarStyle style;
  final VoidCallback? onTap;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final motion = skyMotionAllowed(context);
    return SkyPressable(
      onTap: onTap,
      enabled: enabled,
      pressedScale: 0.97,
      semanticLabel: name,
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: enabled || busy ? 1 : 0.55,
        duration: motion ? SkyMotion.fast : Duration.zero,
        child: AnimatedContainer(
          duration: motion ? SkyMotion.quick : Duration.zero,
          curve: SkyMotion.standard,
          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
          decoration: BoxDecoration(
            gradient: t.cardGradient,
            borderRadius: SkyRadii.all(SkyRadii.tile),
            border: Border.all(color: busy ? t.roseBorder : t.cardBorder),
            boxShadow: t.cardShadow,
          ),
          child: Row(
            children: [
              SkyAvatar(initial: initial, style: style, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SkyType.serif(20, weight: FontWeight.w500, height: 1.2).copyWith(color: t.text),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(detail!, style: SkyType.small.copyWith(color: t.muted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (busy)
                SkySpinner(size: 18, color: t.rose)
              else
                SkyIcon(SkyIcons.chevron, size: 16, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }
}
