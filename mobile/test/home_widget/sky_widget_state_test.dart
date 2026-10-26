import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/home_widget/sky_widget_state.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_constellations.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

List<String> daysFrom(DateTime first, int count) => [
  for (var i = 0; i < count; i++)
    DateTime.utc(first.year, first.month, first.day + i).toIso8601String().substring(0, 10),
];

ConstellationSeries seriesOf(int stars, {bool litToday = true}) {
  final days = daysFrom(DateTime.utc(2026, 1, 1), stars);
  final today = litToday && days.isNotEmpty ? days.last : '2027-01-01';
  return ConstellationSeries.fromDays(days, today: today);
}

AnsweredDay secretDay(String day) => AnsweredDay(
  day: day,
  question: allQuestions.first,
  mine: DailyAnswerEntry({'questionId': allQuestions.first.id, 'text': 'Sam wrote about Alex', 'answeredAt': 1}),
  theirs: DailyAnswerEntry({'questionId': allQuestions.first.id, 'text': 'Alex wrote about Sam', 'answeredAt': 2}),
);

void main() {
  group('what the home-screen widget shows', () {
    test('an empty sky says Our Space and carries no constellation', () {
      const state = SkyWidgetState.empty();
      expect(state.isEmpty, isTrue);
      expect(state.night, isTrue);
      expect(state.stars, 0);
      expect(state.constellation, isNull);
      expect(state.label, 'Our Space');
      expect(state.mode, SkyMode.night);
      expect(const SkyWidgetState.empty(night: false).mode, SkyMode.day);
    });

    test('no shared nights yet is the same calm empty sky', () {
      expect(SkyWidgetState.forSeries(seriesOf(0), night: false), const SkyWidgetState.empty(night: false));
    });

    test('the star count reads naturally', () {
      expect(SkyWidgetCopy.stars(1), '1 star');
      expect(SkyWidgetCopy.stars(2), '2 stars');
      expect(SkyWidgetState.forSeries(seriesOf(1), night: true).label, '1 star');
      expect(SkyWidgetState.forSeries(seriesOf(12), night: true).label, '12 stars');
    });

    test('the current constellation is drawn with its lit stars and no waiting slot', () {
      final series = seriesOf(12, litToday: false);
      final state = SkyWidgetState.forSeries(series, night: true);
      final figure = state.constellation!;
      expect(figure.shape, ConstellationShape.heart);
      expect(figure.gap, isNull);
      expect(figure.hasOpenGap, isFalse);
      expect(figure.presence, isFalse);
      expect(figure.burst, isFalse);
      expect(figure.complete, isFalse);
      expect(figure.unlit, series.current.unlitSlots);
      expect(figure.litPoints.toSet(), series.current.litSlots);
      expect(figure.litPoints.length, 12);
    });

    test('a finished constellation stays whole on the night it is finished', () {
      final state = SkyWidgetState.forSeries(seriesOf(29), night: true);
      expect(state.constellation!.shape, ConstellationShape.heart);
      expect(state.constellation!.complete, isTrue);
      expect(state.constellation!.unlit, isEmpty);
      expect(state.label, '29 stars');
    });

    test('the next night starts the next shape', () {
      final waiting = SkyWidgetState.forSeries(seriesOf(29, litToday: false), night: true);
      expect(waiting.constellation!.shape, ConstellationShape.moon);
      expect(waiting.constellation!.litPoints, isEmpty);
      expect(waiting.label, '29 stars');

      final next = SkyWidgetState.forSeries(seriesOf(30), night: true);
      expect(next.constellation!.shape, ConstellationShape.moon);
      expect(next.constellation!.litPoints, [ConstellationShape.moon.me]);
      expect(next.label, '30 stars');
    });

    test('switching between day and night keeps the same stars', () {
      final night = SkyWidgetState.forSeries(seriesOf(5), night: true);
      final day = night.inMode(night: false);
      expect(day.night, isFalse);
      expect(day.mode, SkyMode.day);
      expect(day.stars, night.stars);
      expect(day.constellation, night.constellation);
      expect(day, isNot(night));
      expect(day.inMode(night: true), night);
      expect(identical(night.inMode(night: true), night), isTrue);
    });

    test('states compare by what they show', () {
      expect(SkyWidgetState.forSeries(seriesOf(7), night: true), SkyWidgetState.forSeries(seriesOf(7), night: true));
      expect(
        SkyWidgetState.forSeries(seriesOf(7), night: true).hashCode,
        SkyWidgetState.forSeries(seriesOf(7), night: true).hashCode,
      );
      expect(
        SkyWidgetState.forSeries(seriesOf(7), night: true),
        isNot(SkyWidgetState.forSeries(seriesOf(8), night: true)),
      );
    });
  });

  group('what leaves the app for the widget', () {
    test('only the label and the time of day are sent as text', () {
      expect(SkyWidgetState.forSeries(seriesOf(3), night: false).data, {
        SkyWidgetKeys.label: '3 stars',
        SkyWidgetKeys.night: false,
      });
      expect(const SkyWidgetState.empty().data, {SkyWidgetKeys.label: 'Our Space', SkyWidgetKeys.night: true});
    });

    test('names, questions, answers and dates never reach the widget', () {
      final days = daysFrom(DateTime.utc(2026, 3, 1), 4);
      final series = ConstellationSeries.fromAnswered([for (final day in days) secretDay(day)], today: days.last);
      final state = SkyWidgetState.forSeries(series, night: true);
      final sent = [...state.data.keys, ...state.data.values.map((value) => '$value'), '$state'].join(' ');
      for (final secret in [
        'Sam',
        'Alex',
        allQuestions.first.text,
        allQuestions.first.id,
        ...days,
        '2026',
        'Mar',
        'March',
      ]) {
        expect(sent.contains(secret), isFalse, reason: secret);
      }
      expect(state.data.keys.toSet(), {SkyWidgetKeys.label, SkyWidgetKeys.night});
      expect(SkyWidgetKeys.all.toSet().containsAll(state.data.keys), isTrue);
    });

    test('the widget is found by its Android provider name', () {
      expect(SkyWidgetKeys.provider, 'com.ourspace.our_space_mobile.SkyWidgetProvider');
      expect(SkyWidgetKeys.all, hasLength(4));
      expect(SkyWidgetKeys.all.toSet(), hasLength(4));
    });
  });
}
