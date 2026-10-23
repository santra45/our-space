import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/screens/love/love_tally.dart';
import 'package:our_space_mobile/presentation/screens/love/love_week.dart';

int ms(DateTime at) => at.millisecondsSinceEpoch;

void main() {
  final wednesday = DateTime(2026, 10, 21, 20, 15);
  final sunday = DateTime(2026, 10, 18);
  final monday = DateTime(2026, 10, 19);
  final lastWeek = DateTime(2026, 10, 15, 9);

  group('LoveWeek.startOf', () {
    test('finds the first day of the week for the locale', () {
      expect(LoveWeek.startOf(wednesday), sunday);
      expect(LoveWeek.startOf(wednesday, firstDay: 1), monday);
      expect(LoveWeek.startOf(DateTime(2026, 10, 18, 0, 1)), sunday);
      expect(LoveWeek.startOf(DateTime(2026, 10, 18, 23, 59), firstDay: 1), DateTime(2026, 10, 12));
      expect(LoveWeek.startOf(DateTime(2026, 10, 24, 23, 59)), sunday);
      expect(LoveWeek.startOf(DateTime(2026, 11, 3), firstDay: 6), DateTime(2026, 10, 31));
    });
  });

  group('LoveWeek.track', () {
    test('love sent before this week does not count', () {
      final week = LoveWeek.track(null, {'burst-me': (count: 12, at: ms(lastWeek))}, now: wednesday);
      expect(week.start, sunday);
      expect(week.count, 0);
      expect(week.records['burst-me'], const LoveWeekRecord(base: 12, seen: 12));
    });

    test('a record with no time or no love counts nothing', () {
      final week = LoveWeek.track(null, {
        'burst-me': (count: 4, at: null),
        'burst-tab': (count: 0, at: ms(wednesday)),
      }, now: wednesday);
      expect(week.count, 0);
    });

    test('every send seen during the week is counted exactly', () {
      var week = LoveWeek.track(null, {'burst-me': (count: 12, at: ms(lastWeek))}, now: wednesday);
      week = LoveWeek.track(week, {'burst-me': (count: 13, at: ms(wednesday))}, now: wednesday);
      week = LoveWeek.track(week, {'burst-me': (count: 15, at: ms(wednesday))}, now: wednesday.add(const Duration(hours: 1)));
      expect(week.count, 3);
      week = LoveWeek.track(week, {'burst-me': (count: 15, at: ms(wednesday))}, now: DateTime(2026, 10, 24, 22));
      expect(week.count, 3);
    });

    test('a new week starts again from zero', () {
      var week = LoveWeek.track(null, {'burst-me': (count: 2, at: ms(DateTime(2026, 10, 5)))}, now: lastWeek);
      week = LoveWeek.track(week, {'burst-me': (count: 9, at: ms(lastWeek))}, now: lastWeek);
      expect(week.count, 7);
      week = LoveWeek.track(week, {'burst-me': (count: 9, at: ms(lastWeek))}, now: wednesday);
      expect(week.start, sunday);
      expect(week.count, 0);
    });

    test('love sent elsewhere since the last look counts toward this week', () {
      var week = LoveWeek.track(null, {'burst-me': (count: 10, at: ms(lastWeek))}, now: lastWeek);
      week = LoveWeek.track(week, {'burst-me': (count: 14, at: ms(monday))}, now: wednesday);
      expect(week.count, 4);
    });

    test('without an earlier look only the latest love is known to be this week', () {
      final week = LoveWeek.track(null, {'burst-me': (count: 10, at: ms(monday))}, now: wednesday);
      expect(week.count, 1);
    });

    test('adds up all my phones and handles counts that went down', () {
      var week = LoveWeek.track(null, {
        'burst-me': (count: 3, at: ms(lastWeek)),
        'burst-tab': (count: 1, at: ms(monday)),
      }, now: wednesday);
      expect(week.count, 1);
      week = LoveWeek.track(week, {
        'burst-me': (count: 5, at: ms(wednesday)),
        'burst-tab': (count: 2, at: ms(wednesday)),
        'burst-old': (count: 40, at: ms(lastWeek)),
      }, now: wednesday);
      expect(week.count, 4);
      week = LoveWeek.track(week, {'burst-me': (count: 1, at: ms(wednesday))}, now: wednesday);
      expect(week.count, 0);
      expect(week.records.keys, ['burst-me']);
    });

    test('a clock that moved backwards does not trust the stored week', () {
      final future = LoveWeek(start: DateTime(2026, 11, 1), records: const {'burst-me': LoveWeekRecord(base: 0, seen: 50)});
      final week = LoveWeek.track(future, {'burst-me': (count: 50, at: ms(wednesday))}, now: wednesday);
      expect(week.start, sunday);
      expect(week.count, 1);
    });
  });

  group('LoveWeek storage', () {
    test('round trips through text', () {
      final week = LoveWeek.track(null, <String, LoveRecord>{
        'burst-me': (count: 7, at: ms(monday)),
        'burst-tab': (count: 3, at: ms(lastWeek)),
      }, now: wednesday);
      final back = LoveWeek.decode(week.encode());
      expect(back, week);
      expect(back!.count, 1);
      expect(back.start, sunday);
    });

    test('ignores anything it cannot read', () {
      expect(LoveWeek.decode(null), isNull);
      expect(LoveWeek.decode(''), isNull);
      expect(LoveWeek.decode('not json'), isNull);
      expect(LoveWeek.decode('[]'), isNull);
      expect(LoveWeek.decode('{"start":"2026-13-01","records":{}}'), isNull);
      expect(LoveWeek.decode('{"start":"soon","records":{}}'), isNull);
      expect(LoveWeek.decode('{"start":"2026-10-18"}'), isNull);
      final partial = LoveWeek.decode(
        '{"start":"2026-10-18","records":{"a":[1,2],"b":[1],"c":["1",2],"d":[-1,2],"e":{"base":1}}}',
      );
      expect(partial?.start, sunday);
      expect(partial?.records, {'a': const LoveWeekRecord(base: 1, seen: 2)});
    });
  });
}
