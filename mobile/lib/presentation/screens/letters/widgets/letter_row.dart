import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../sky/sky.dart';
import 'wax_seal.dart';

class LetterRow extends StatelessWidget {
  const LetterRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.sealed = false,
    this.busy = false,
    this.onTap,
    this.onLongPress,
  });

  final String title;
  final String subtitle;
  final bool sealed;
  final bool busy;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return SkyPressable(
      onTap: busy ? null : onTap,
      onLongPress: onLongPress,
      pressedScale: 0.985,
      semanticLabel: title,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.hairline))),
        child: Row(
          children: [
            PaperTile(sealed: sealed),
            const SizedBox(width: SkySpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SkyType.serifItem.copyWith(color: t.text),
                  ),
                  const SizedBox(height: SkySpace.xxs),
                  Text(subtitle, style: SkyType.small.copyWith(color: t.muted)),
                ],
              ),
            ),
            const SizedBox(width: SkySpace.sm),
            if (busy) SkySpinner(size: 16, color: t.rose) else SkyIcon(SkyIcons.chevron, size: 16, color: t.faint),
          ],
        ),
      ),
    );
  }
}

class PaperTile extends StatelessWidget {
  const PaperTile({super.key, this.sealed = false, this.size = 44});

  final bool sealed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Transform.rotate(
      angle: -4 * math.pi / 180,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: t.paper,
          borderRadius: SkyRadii.all(12),
          boxShadow: t.softShadow,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(child: SkyIcon(SkyIcons.letter, size: size * 20 / 44, color: t.paperMuted)),
            if (sealed) const Positioned(right: -3, bottom: -3, child: WaxSeal(size: 16, iconSize: 8)),
          ],
        ),
      ),
    );
  }
}
