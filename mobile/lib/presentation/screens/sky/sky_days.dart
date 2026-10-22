import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/engine.dart';

enum SkyMilestoneKind { year, month, hundred, week }

@immutable
class SkyMilestone {
  const SkyMilestone({required this.kind, required this.count, required this.date, required this.daysLeft});

  final SkyMilestoneKind kind;
  final int count;
  final DateTime date;
  final int daysLeft;

  static const List<String> _words = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
  ];

  static String _count(int n) => n >= 0 && n < _words.length ? _words[n] : '$n';

  String get name {
    switch (kind) {
      case SkyMilestoneKind.year:
        return count == 1 ? 'one year' : '${_count(count)} years';
      case SkyMilestoneKind.month:
        return count == 1 ? 'one month' : '${_count(count)} months';
      case SkyMilestoneKind.hundred:
        return '$count days';
      case SkyMilestoneKind.week:
        return 'one week';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SkyMilestone &&
      other.kind == kind &&
      other.count == count &&
      other.date == date &&
      other.daysLeft == daysLeft;

  @override
  int get hashCode => Object.hash(kind, count, date, daysLeft);

  @override
  String toString() => '$name in $daysLeft';
}

abstract final class SkyDays {
  static DateTime dateOnly(DateTime time) => DateTime(time.year, time.month, time.day);

  static DateTime? startOf(String? startDate) {
    if (startDate == null || startDate.trim().isEmpty) return null;
    final parsed = parseLocalDate(startDate);
    return parsed == null ? null : dateOnly(parsed);
  }

  static int between(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  static int dayNumber(DateTime start, DateTime now) => math.max(0, between(start, now)) + 1;

  static int _daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

  static DateTime addMonths(DateTime start, int months) {
    final first = DateTime(start.year, start.month + months, 1);
    return DateTime(first.year, first.month, math.min(start.day, _daysIn(first.year, first.month)));
  }

  static SkyMilestone next(DateTime start, DateTime now) {
    final today = dateOnly(now);
    final begin = dateOnly(start);
    final elapsed = between(begin, today);
    final candidates = <SkyMilestone>[];

    void consider(SkyMilestoneKind kind, int count, DateTime date) {
      final left = between(today, date);
      if (left < 0) return;
      candidates.add(SkyMilestone(kind: kind, count: count, date: date, daysLeft: left));
    }

    var years = math.max(1, today.year - begin.year);
    while (between(today, addMonths(begin, years * 12)) < 0) {
      years++;
    }
    consider(SkyMilestoneKind.year, years, addMonths(begin, years * 12));

    for (var month = 1; month < 12; month++) {
      final date = addMonths(begin, month);
      if (between(today, date) >= 0) {
        consider(SkyMilestoneKind.month, month, date);
        break;
      }
    }

    final hundreds = math.max(1, (math.max(elapsed, 0) / 100).ceil());
    consider(SkyMilestoneKind.hundred, hundreds * 100, DateTime(begin.year, begin.month, begin.day + hundreds * 100));

    if (elapsed <= 7) consider(SkyMilestoneKind.week, 1, DateTime(begin.year, begin.month, begin.day + 7));

    candidates.sort((a, b) {
      final byDays = a.daysLeft.compareTo(b.daysLeft);
      return byDays != 0 ? byDays : a.kind.index.compareTo(b.kind.index);
    });
    return candidates.first;
  }
}
