import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'love_tally.dart';

@immutable
class LoveWeekRecord {
  const LoveWeekRecord({required this.base, required this.seen});

  final int base;
  final int seen;

  int get count => math.max(0, seen - base);

  @override
  bool operator ==(Object other) => other is LoveWeekRecord && other.base == base && other.seen == seen;

  @override
  int get hashCode => Object.hash(base, seen);
}

@immutable
class LoveWeek {
  const LoveWeek({required this.start, this.records = const {}});

  static const String storageKey = 'loveSentThisWeek';

  final DateTime start;
  final Map<String, LoveWeekRecord> records;

  int get count => records.values.fold(0, (sum, record) => sum + record.count);

  static DateTime startOf(DateTime now, {int firstDay = 0}) {
    final back = (now.weekday % 7 - firstDay) % 7;
    return DateTime(now.year, now.month, now.day - back);
  }

  static LoveWeek track(
    LoveWeek? previous,
    Map<String, LoveRecord> mine, {
    required DateTime now,
    int firstDay = 0,
  }) {
    final start = startOf(now, firstDay: firstDay);
    final since = start.millisecondsSinceEpoch;
    final same = previous != null && previous.start == start;
    final earlier = previous != null && previous.start.isBefore(start);
    final records = <String, LoveWeekRecord>{};
    mine.forEach((id, record) {
      final seen = math.max(0, record.count);
      final at = record.at;
      final before = previous?.records[id];
      final int base;
      if (same && before != null) {
        base = math.min(before.base, seen);
      } else if (at == null || at < since || seen == 0) {
        base = seen;
      } else if (earlier && before != null) {
        base = math.min(before.seen, seen - 1);
      } else {
        base = seen - 1;
      }
      records[id] = LoveWeekRecord(base: math.max(0, base), seen: seen);
    });
    return LoveWeek(start: start, records: Map.unmodifiable(records));
  }

  String encode() => jsonEncode({
        'start': _day(start),
        'records': {
          for (final entry in records.entries) entry.key: [entry.value.base, entry.value.seen],
        },
      });

  static LoveWeek? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return null;
      final start = _parseDay(parsed['start']);
      final stored = parsed['records'];
      if (start == null || stored is! Map) return null;
      final records = <String, LoveWeekRecord>{};
      stored.forEach((id, value) {
        if (id is! String || value is! List || value.length != 2) return;
        final base = value[0];
        final seen = value[1];
        if (base is! int || seen is! int || base < 0 || seen < 0) return;
        records[id] = LoveWeekRecord(base: base, seen: seen);
      });
      return LoveWeek(start: start, records: Map.unmodifiable(records));
    } catch (_) {
      return null;
    }
  }

  static String _day(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDay(Object? value) {
    if (value is! String) return null;
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  @override
  bool operator ==(Object other) => other is LoveWeek && other.start == start && mapEquals(other.records, records);

  @override
  int get hashCode => Object.hash(start, records.length);
}
