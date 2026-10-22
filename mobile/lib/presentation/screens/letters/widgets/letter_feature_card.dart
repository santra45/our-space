import 'package:flutter/material.dart';

import '../../../sky/sky.dart';
import '../letters_copy.dart';
import 'sealed_envelope.dart';

class LetterFeatureCard extends StatelessWidget {
  const LetterFeatureCard({
    super.key,
    required this.label,
    required this.title,
    required this.meta,
    required this.onBreak,
    this.busy = false,
    this.onLongPress,
  });

  final String label;
  final String title;
  final String meta;
  final VoidCallback onBreak;
  final bool busy;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: SkyFeatureCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SkyLabel(label, icon: SkyIcons.sparkle, tone: SkyTone.rose),
            const SizedBox(height: SkySpace.sm),
            SkyPressable(
              onTap: busy ? null : onBreak,
              pressedScale: 0.97,
              semanticLabel: 'Sealed envelope',
              excludeSemantics: true,
              child: SealedEnvelope(breathe: !busy),
            ),
            const SizedBox(height: 14),
            Text(title, style: SkyType.headline.copyWith(color: t.text)),
            const SizedBox(height: SkySpace.xs),
            Text(meta, style: SkyType.bodySmall.copyWith(color: t.muted)),
            const SizedBox(height: 14),
            SkyButton(
              label: LettersCopy.breakSeal,
              busyLabel: LettersCopy.breaking,
              busy: busy,
              icon: SkyIcons.sparkle,
              onPressed: onBreak,
            ),
          ],
        ),
      ),
    );
  }
}
