import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import 'milestone_copy.dart';

enum UpcomingKind { month, hundred, anniversary }

@immutable
class UpcomingMilestone {
  const UpcomingMilestone({required this.kind, required this.count, required this.daysLeft});

  final UpcomingKind kind;
  final int count;
  final int daysLeft;

  bool get isToday => daysLeft <= 0;

  String get title {
    switch (kind) {
      case UpcomingKind.month:
        return MilestoneCopy.months(count);
      case UpcomingKind.hundred:
        return MilestoneCopy.hundred(count);
      case UpcomingKind.anniversary:
        return MilestoneCopy.years(count);
    }
  }

  String get when => MilestoneCopy.inDays(daysLeft);

  SkyIcons get icon {
    switch (kind) {
      case UpcomingKind.month:
        return SkyIcons.moon;
      case UpcomingKind.hundred:
        return SkyIcons.star;
      case UpcomingKind.anniversary:
        return SkyIcons.sparkle;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is UpcomingMilestone && other.kind == kind && other.count == count && other.daysLeft == daysLeft;

  @override
  int get hashCode => Object.hash(kind, count, daysLeft);

  @override
  String toString() => '$title ($when)';
}

DateTime monthsAfter(DateTime start, int months) {
  final index = start.month - 1 + months;
  final year = start.year + index ~/ 12;
  final month = index % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, math.min(start.day, lastDay));
}

int daysFromTo(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

List<UpcomingMilestone> upcomingMilestones(String? startDate, DateTime now) {
  final next = calculateNextMilestone(startDate, now);
  final start = next == null ? null : parseLocalDate(startDate);
  if (next == null || start == null) return const [];
  final today = startOfLocalDay(now);
  final items = <UpcomingMilestone>[];
  for (var month = 1; month < 12; month++) {
    final left = daysFromTo(today, monthsAfter(start, month));
    if (left >= 0) {
      items.add(UpcomingMilestone(kind: UpcomingKind.month, count: month, daysLeft: left));
      break;
    }
  }
  items
    ..add(
      UpcomingMilestone(
        kind: UpcomingKind.hundred,
        count: next.hundredDay.milestone,
        daysLeft: next.hundredDay.daysLeft,
      ),
    )
    ..add(
      UpcomingMilestone(
        kind: UpcomingKind.anniversary,
        count: next.anniversary.year,
        daysLeft: next.anniversary.daysLeft,
      ),
    );
  items.sort((a, b) {
    final byDays = a.daysLeft.compareTo(b.daysLeft);
    return byDays != 0 ? byDays : a.kind.index.compareTo(b.kind.index);
  });
  return items;
}

class UpcomingRow extends StatelessWidget {
  const UpcomingRow({super.key, required this.items});

  static const double cardWidth = 150;
  static const double shadowRoom = 12;

  final List<UpcomingMilestone> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: shadowRoom),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              SkyEntrance(
                key: ValueKey<UpcomingKind>(items[i].kind),
                index: i,
                offset: const Offset(18, 0),
                child: UpcomingCard(item: items[i], lead: i == 0),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class UpcomingCard extends StatelessWidget {
  const UpcomingCard({super.key, required this.item, this.lead = false});

  final UpcomingMilestone item;
  final bool lead;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final tone = lead ? SkyTone.gold : SkyTone.rose;
    Widget tile = SkyIconTile(icon: item.icon, tone: tone, size: 34, iconSize: 18);
    if (item.isToday && skyMotionAllowed(context)) {
      tile = SkyPulse(minScale: 0.94, maxScale: 1.06, child: tile);
    }
    return Semantics(
      container: true,
      label: '${item.title}, ${item.when}',
      excludeSemantics: true,
      child: SizedBox(
        width: UpcomingRow.cardWidth,
        child: SkyCard(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              tile,
              const SizedBox(height: SkySpace.sm),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SkyType.serif(17, weight: FontWeight.w500, height: 1.25).copyWith(color: t.text),
              ),
              const SizedBox(height: 2),
              Text(
                item.when,
                style: item.isToday
                    ? SkyType.sans(11.5, weight: FontWeight.w700, height: 1.4).copyWith(color: tone.foreground(t))
                    : SkyType.small.copyWith(color: t.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
