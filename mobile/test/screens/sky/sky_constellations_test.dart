import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_constellation_plan.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_constellations.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

List<String> daysFrom(DateTime first, int count) => [
  for (var i = 0; i < count; i++)
    DateTime.utc(first.year, first.month, first.day + i).toIso8601String().substring(0, 10),
];

AnsweredDay answered(String day, {bool both = true}) => AnsweredDay(
  day: day,
  question: allQuestions.first,
  mine: DailyAnswerEntry({'questionId': allQuestions.first.id, 'text': 'Mine $day', 'answeredAt': 1}),
  theirs: both
      ? DailyAnswerEntry({'questionId': allQuestions.first.id, 'text': 'Theirs $day', 'answeredAt': 2})
      : null,
);

void main() {
  final first = DateTime.utc(2026, 1, 1);

  group('every night you both answered is a star', () {
    test('nights are numbered oldest first and only count when both answered', () {
      final days = daysFrom(first, 4);
      final series = ConstellationSeries.fromAnswered(
        [answered(days[3]), answered(days[0]), answered(days[1], both: false), answered(days[2])],
        today: '2026-02-01',
      );
      expect(series.stars, 3);
      expect([for (final night in series.nights) night.day], [days[0], days[2], days[3]]);
      expect([for (final night in series.nights) night.number], [1, 2, 3]);
      expect(series.nights.first.mine?.text, 'Mine ${days[0]}');
      expect(series.nights.first.theirs?.text, 'Theirs ${days[0]}');
      expect(series.nights.first.question, allQuestions.first);
      expect(series.nights.first.date, DateTime.utc(2026, 1, 1, 12));
      expect(series.litToday, isFalse);
    });

    test('star g lives in constellation g ~/ 29 at its shape order slot', () {
      final series = ConstellationSeries.fromDays(daysFrom(first, 120), today: '2026-12-31');
      for (final night in series.nights) {
        final g = night.number - 1;
        expect(night.star, g);
        expect(night.constellation, g ~/ 29);
        expect(night.position, g % 29);
        expect(night.shape, ConstellationShape.at(g ~/ 29));
        expect(night.slot, ConstellationShape.at(g ~/ 29).order[g % 29]);
      }
      expect(series.nights[29].shape, ConstellationShape.moon);
      expect(series.nights[58].shape, ConstellationShape.infinity);
      expect(series.nights[87].shape, ConstellationShape.star);
      expect(series.nights[116].shape, ConstellationShape.heart);
      expect(series.nights[116].constellation, 4);
    });

    test('each constellation has a warm name, a number and the dates of its nights', () {
      final days = daysFrom(first, 70);
      final series = ConstellationSeries.fromDays(days, today: days.last);
      final all = series.constellations;
      expect(all, hasLength(3));
      expect(all[0].label, 'Our first constellation · The Heart');
      expect(all[1].label, 'Our second constellation · The Moon');
      expect(all[2].label, 'Our third constellation · Infinity');
      expect(ConstellationChapter(index: 3, nights: const []).label, 'Our fourth constellation · The Star');
      expect(ConstellationChapter(index: 4, nights: const []).label, 'Our fifth constellation · The Heart');
      expect(all[0].complete, isTrue);
      expect(all[0].firstDay, days[0]);
      expect(all[0].lastDay, days[28]);
      expect(all[0].from, DateTime.utc(2026, 1, 1, 12));
      expect(all[0].to, DateTime.utc(2026, 1, 29, 12));
      expect(all[1].firstDay, days[29]);
      expect(all[1].lastDay, days[57]);
      expect(all[2].lit, 12);
      expect(all[2].complete, isFalse);
      expect(series.completed, hasLength(2));
      expect(all[0].completeLine, 'Our first constellation is complete');
      expect(ConstellationChapter.ordinalOf(21), '21st');
      expect(ConstellationChapter.ordinalOf(22), '22nd');
      expect(ConstellationChapter.ordinalOf(23), '23rd');
      expect(ConstellationChapter.ordinalOf(111), '111th');
      expect(ConstellationChapter.titleOf(19), 'Our twentieth constellation');
    });

    test('a constellation knows which night lit each of its stars', () {
      final days = daysFrom(first, 31);
      final series = ConstellationSeries.fromDays(days, today: '2026-03-01');
      final heart = series.chapter(0);
      expect(heart.litSlots, ConstellationShape.heart.order.toSet());
      expect(heart.unlitSlots, isEmpty);
      expect(heart.nightAt(24)?.number, 1);
      expect(heart.nightAt(5)?.number, 2);
      expect(heart.nightAt(10)?.number, 29);
      final moon = series.current;
      expect(moon.index, 1);
      expect(moon.lit, 2);
      expect(moon.nightAt(ConstellationShape.moon.me)?.number, 30);
      expect(moon.nightAt(ConstellationShape.moon.partner)?.number, 31);
      expect(moon.nightAt(ConstellationShape.moon.order[2]), isNull);
      expect(moon.unlitSlots, hasLength(27));
      expect(moon.nextSlot, ConstellationShape.moon.order[2]);
      expect(series.nightAt(ConstellationShape.moon.partner)?.day, days[30]);
      expect(series.nightOn(days[3])?.number, 4);
      expect(series.latest?.number, 31);
    });
  });

  group('the home shows the constellation you are filling', () {
    test('tonight waits at the next slot until you both answer', () {
      final days = daysFrom(first, 5);
      final waiting = ConstellationSeries.fromDays(days, today: '2026-01-06');
      expect(waiting.litToday, isFalse);
      expect(waiting.current.index, 0);
      expect(waiting.tonightSlot, ConstellationShape.heart.order[5]);
      final lit = ConstellationSeries.fromDays([...days, '2026-01-06'], today: '2026-01-06');
      expect(lit.litToday, isTrue);
      expect(lit.tonightSlot, isNull);
      expect(lit.current.lit, 6);
      final home = SkyConstellationPlan.forSeries(waiting, presence: false);
      expect(home.gap, ConstellationShape.heart.order[5]);
      expect(home.litPoints.toSet(), ConstellationShape.heart.order.take(5).toSet());
    });

    test('the 29th star completes the shape that night and the next shape starts the night after', () {
      final days = daysFrom(first, 29);
      final tonight = ConstellationSeries.fromDays(days, today: days.last);
      expect(tonight.completedTonight, isTrue);
      expect(tonight.current.index, 0);
      expect(tonight.current.complete, isTrue);
      final whole = SkyConstellationPlan.forSeries(tonight, presence: false);
      expect(whole.shape, ConstellationShape.heart);
      expect(whole.complete, isTrue);
      expect(whole.litPoints, hasLength(29));

      final next = ConstellationSeries.fromDays(days, today: '2026-01-30');
      expect(next.completedTonight, isFalse);
      expect(next.current.index, 1);
      expect(next.current.lit, 0);
      expect(next.tonightSlot, ConstellationShape.moon.me);
      expect(next.constellations, hasLength(2));
      final moon = SkyConstellationPlan.forSeries(next, presence: false);
      expect(moon.shape, ConstellationShape.moon);
      expect(moon.gap, ConstellationShape.moon.me);
      expect(moon.litPoints, isEmpty);
      expect(next.stars, 29);
    });

    test('after four constellations the heart comes back', () {
      final days = daysFrom(first, 117);
      final series = ConstellationSeries.fromDays(days, today: '2027-01-01');
      expect(series.current.index, 4);
      expect(series.current.shape, ConstellationShape.heart);
      expect(series.current.label, 'Our fifth constellation · The Heart');
      expect(series.current.lit, 1);
      expect(series.completed, hasLength(4));
      expect(SkyConstellationPlan.forSeries(series, presence: false).shape, ConstellationShape.heart);
    });

    test('an empty sky starts the heart with your star', () {
      final series = ConstellationSeries.fromDays(const [], today: '2026-01-01');
      expect(series.stars, 0);
      expect(series.current.index, 0);
      expect(series.current.started, isFalse);
      expect(series.tonightSlot, 24);
      expect(series.latest, isNull);
      expect(series.constellations, hasLength(1));
    });

    test('the reveal says when a constellation is complete', () {
      expect(SkyConstellationPlan.completes(29), isTrue);
      expect(SkyConstellationPlan.completes(58), isTrue);
      expect(SkyConstellationPlan.completes(30), isFalse);
      expect(SkyConstellationPlan.completes(0), isFalse);
      expect(SkyConstellationPlan.completeLine(29), 'Our first constellation is complete');
      expect(SkyConstellationPlan.completeLine(58), 'Our second constellation is complete');
      expect(SkyConstellationPlan.reveal(stars: 58).shape, ConstellationShape.moon);
      expect(SkyConstellationPlan.reveal(stars: 58).unlit, isEmpty);
    });
  });
}
