import 'package:flutter/material.dart';

import '../../../sky/sky.dart';

class CoupleHeader extends StatelessWidget {
  const CoupleHeader({super.key, required this.myInitial, this.partnerInitial, this.title, this.subtitle});

  static const double avatarSize = 72;
  static const double overlap = 14;
  static const double badgeSize = 28;

  final String myInitial;
  final String? partnerInitial;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final partner = partnerInitial;
    final width = partner == null ? avatarSize : avatarSize * 2 - overlap;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: avatarSize + 4,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: SkyAvatar(initial: myInitial, size: avatarSize),
              ),
              if (partner != null) ...[
                Positioned(
                  left: avatarSize - overlap,
                  top: 0,
                  child: SkyAvatar(initial: partner, size: avatarSize, style: SkyAvatarStyle.partner),
                ),
                Positioned(
                  left: width / 2 - badgeSize / 2,
                  bottom: -2,
                  child: ExcludeSemantics(
                    child: Container(
                      width: badgeSize,
                      height: badgeSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: t.roseOrbGradient,
                        boxShadow: [
                          BoxShadow(color: t.page, spreadRadius: 3),
                          BoxShadow(
                            color: t.roseDeep.withValues(alpha: 0.5),
                            offset: const Offset(0, 4),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const SkyIcon(SkyIcons.heart, size: 14, color: SkyTokens.white),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (title != null && title!.isNotEmpty) ...[
          const SizedBox(height: SkySpace.md),
          Semantics(
            header: true,
            child: Text(
              title!,
              textAlign: TextAlign.center,
              style: SkyType.headline.copyWith(color: t.title),
            ),
          ),
        ],
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: SkyType.sans(12.5).copyWith(color: t.muted),
          ),
        ],
      ],
    );
  }
}
