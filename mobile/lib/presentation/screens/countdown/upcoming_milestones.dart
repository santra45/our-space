import 'package:flutter/widgets.dart';

import '../../../core/engine.dart';
import '../../widgets/our_widgets.dart';
import 'milestone_copy.dart';

class UpcomingMilestones extends StatelessWidget {
  const UpcomingMilestones({super.key, required this.milestones});

  final NextMilestone milestones;

  @override
  Widget build(BuildContext context) {
    final anniversary = milestones.anniversary;
    final hundredDay = milestones.hundredDay;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: UpcomingCard(
              icon: AppIcons.award,
              iconColor: AppColors.blush500,
              tag: const OurTag(MilestoneCopy.anniversary),
              daysLeft: anniversary.daysLeft,
              todayColor: AppColors.blush600,
              caption: MilestoneCopy.yearCelebration(anniversary.year),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: UpcomingCard(
              icon: AppIcons.trophy,
              iconColor: AppColors.lavender500,
              tag: OurTag(
                MilestoneCopy.dayTag(hundredDay.milestone),
                background: AppColors.lavender100,
                foreground: AppColors.lavender700,
              ),
              daysLeft: hundredDay.daysLeft,
              todayColor: AppColors.lavender600,
              caption: MilestoneCopy.nextHundred,
            ),
          ),
        ],
      ),
    );
  }
}

class UpcomingCard extends StatelessWidget {
  const UpcomingCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.tag,
    required this.daysLeft,
    required this.todayColor,
    required this.caption,
  });

  final LucideIconData icon;
  final Color iconColor;
  final Widget tag;
  final int daysLeft;
  final Color todayColor;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final count = daysLeft == 0
        ? Text(MilestoneCopy.today, style: Tw.x2l.extrabold.c(todayColor))
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$daysLeft'),
                const WidgetSpan(child: SizedBox(width: 4)),
                TextSpan(text: MilestoneCopy.daysLeft, style: Tw.xs.semibold.c(AppColors.slate400)),
              ],
            ),
            style: Tw.x2l.extrabold.c(AppColors.slate800),
          );
    return GlassCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                LucideIcon(icon, size: 20, color: iconColor),
                const SizedBox(width: 4),
                Flexible(child: tag),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              count,
              const SizedBox(height: 2),
              Text(caption, style: Tw.xs.medium.c(AppColors.slate500)),
            ],
          ),
        ],
      ),
    );
  }
}
