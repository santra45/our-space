import 'package:flutter/material.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';

const Map<String, String> pronounLabels = {
  'she': 'she / her',
  'he': 'he / him',
  'they': 'they / them',
};

String pronounLabelFor(String? pronoun) => pronounLabels[pronoun] ?? pronounLabels[defaultPronoun]!;

class PronounPicker extends StatelessWidget {
  const PronounPicker({super.key, required this.value, required this.onChanged, this.dense = false});

  final String value;
  final ValueChanged<String> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < pronouns.length; i++) ...[
          if (i > 0) SizedBox(width: dense ? 6 : 8),
          Expanded(
            child: PronounChip(
              label: pronounLabels[pronouns[i]]!,
              selected: value == pronouns[i],
              dense: dense,
              onTap: () => onChanged(pronouns[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class PronounChip extends StatelessWidget {
  const PronounChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final motion = skyMotionAllowed(context);
    final fg = selected ? t.activeFg : t.text;
    return SkyPressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: motion ? SkyMotion.quick : Duration.zero,
        curve: SkyMotion.standard,
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: dense ? 6 : 8),
        decoration: BoxDecoration(
          color: selected ? t.activeBg : t.chip,
          borderRadius: SkyRadii.all(SkyRadii.pill),
          border: Border.all(color: selected ? const Color(0x00000000) : t.chipBorder),
          boxShadow: selected && t.isNight
              ? [BoxShadow(color: t.activeGlow, blurRadius: 12)]
              : const [],
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: (dense ? SkyType.sans(11, weight: FontWeight.w600, height: 1.2) : SkyType.chip).copyWith(color: fg),
        ),
      ),
    );
  }
}
