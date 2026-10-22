import 'package:flutter/material.dart';

import '../../sky/sky.dart';

class DailyAnswerCard extends StatelessWidget {
  const DailyAnswerCard({
    super.key,
    required this.name,
    required this.initial,
    required this.text,
    this.time = '',
    this.partner = false,
  });

  final String name;
  final String initial;
  final String text;
  final String time;
  final bool partner;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final gradient = partner
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(t.rose.withValues(alpha: 0.10), t.surface),
              Color.alphaBlend(t.rose.withValues(alpha: 0.03), t.surface),
            ],
          )
        : t.cardGradient;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: SkyRadii.all(SkyRadii.paper),
        border: Border.all(color: partner ? t.roseBorder : t.cardBorder),
        boxShadow: t.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SkyAvatar(
                initial: initial,
                size: 30,
                style: partner ? SkyAvatarStyle.partner : SkyAvatarStyle.me,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SkyType.sans(13, weight: FontWeight.w700, height: 1.3).copyWith(color: t.text),
                ),
              ),
              if (time.isNotEmpty) Text(time, style: SkyType.sans(11, height: 1.3).copyWith(color: t.muted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(text, style:SkyType.sans(14.5, height: 1.55).copyWith(color: t.text)),
        ],
      ),
    );
  }
}

class DailyWaitingCard extends StatelessWidget {
  const DailyWaitingCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: t.chip,
        borderRadius: SkyRadii.all(SkyRadii.paper),
        border: Border.all(color: t.chipBorder),
      ),
      child: Row(
        children: [
          SkyIcon(SkyIcons.clock, size: 18, color: t.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: SkyType.bodySmall.copyWith(color: t.muted)),
          ),
        ],
      ),
    );
  }
}
