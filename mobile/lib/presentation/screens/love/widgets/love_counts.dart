import 'package:flutter/material.dart';

import '../../../sky/sky.dart';
import '../love_tally.dart';

class LoveCounts extends StatelessWidget {
  const LoveCounts({
    super.key,
    required this.sent,
    required this.received,
    required this.sentLabel,
    required this.receivedLabel,
  });

  static const double gap = 26;

  final int? sent;
  final int? received;
  final String sentLabel;
  final String receivedLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(child: LoveCount(value: sent, label: sentLabel)),
        const SizedBox(width: gap),
        Flexible(child: LoveCount(value: received, label: receivedLabel)),
      ],
    );
  }
}

class LoveCount extends StatelessWidget {
  const LoveCount({super.key, required this.value, required this.label});

  static const String pending = '–';

  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final motion = skyMotionAllowed(context);
    final count = value;
    final shown = count == null ? pending : formatLoveCount(count);
    return Semantics(
      container: true,
      label: count == null ? label : '$shown $label',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRect(
            child: AnimatedSwitcher(
              duration: motion ? SkyMotion.medium : Duration.zero,
              switchInCurve: SkyMotion.standard,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.45), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                shown,
                key: ValueKey<String>('love-count-$label-$shown'),
                maxLines: 1,
                textAlign: TextAlign.center,
                style: SkyType.serif(26, weight: FontWeight.w500, height: 1.2).copyWith(
                  color: count == null ? t.faint : t.text,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: SkyType.sans(11, height: 1.3).copyWith(color: t.muted),
          ),
        ],
      ),
    );
  }
}

class LoveNote extends StatelessWidget {
  const LoveNote({
    super.key,
    required this.leading,
    required this.text,
    this.strong,
    this.trailing,
    this.quiet = false,
    this.semanticLabel,
  });

  static const double height = 46;

  final Widget leading;
  final String text;
  final String? strong;
  final String? trailing;
  final bool quiet;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final style = SkyType.sans(12.5, height: 1.35).copyWith(color: quiet ? t.muted : t.text);
    return Semantics(
      container: true,
      label: semanticLabel ?? [?strong, text, ?trailing].join(' ').trim(),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: height),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: t.chip,
          borderRadius: SkyRadii.all(SkyRadii.md),
          border: Border.all(color: t.chipBorder),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (strong != null)
                      TextSpan(
                        text: strong,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    TextSpan(text: text),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Text(trailing!, maxLines: 1, style: SkyType.sans(11, height: 1.3).copyWith(color: t.faint)),
            ],
          ],
        ),
      ),
    );
  }
}

class LoveMark extends StatelessWidget {
  const LoveMark({super.key, this.initial, this.size = 26});

  final String? initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = initial;
    if (letter != null) {
      return SkyAvatar(initial: letter, style: SkyAvatarStyle.partner, size: size);
    }
    final t = context.sky;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.roseSoft,
        border: Border.all(color: t.roseBorder),
      ),
      child: SkyIcon(SkyIcons.heart, size: size * 0.52, color: t.rose),
    );
  }
}
