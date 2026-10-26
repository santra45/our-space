import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_constellations.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_map_plan.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_night_sheet.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

final RegExp _emoji = RegExp(r'[\p{Extended_Pictographic}\u{FE0F}]', unicode: true);
final RegExp _engineWords = RegExp(
  r'\b(sync\w*|devices?|pair\w*|servers?|upload\w*|download\w*|data|peers?|relays?|mailbox\w*|encrypt\w*|keys?)\b',
  caseSensitive: false,
);

List<String> daysFrom(DateTime first, int count) => [
  for (var i = 0; i < count; i++) first.add(Duration(days: i)).toIso8601String().substring(0, 10),
];

ConstellationSeries seriesOf(int stars, {bool litToday = false}) {
  final days = daysFrom(DateTime.utc(2026, 1, 1), stars);
  final today = litToday && days.isNotEmpty ? days.last : '2030-01-01';
  return ConstellationSeries.fromDays(days, today: today);
}

void main() {
  group('the map keeps the growing constellation first, then every finished one, newest first', () {
    test('before the first star there is nothing to keep yet', () {
      final entries = SkyMapPlan.entriesOf(seriesOf(0));
      expect(entries.isEmpty, isTrue);
      expect(entries.growing, isNull);
      expect(entries.finished, isEmpty);
    });

    test('a constellation still being lit grows on its own', () {
      final entries = SkyMapPlan.entriesOf(seriesOf(12));
      expect(entries.isEmpty, isFalse);
      expect(entries.growing?.index, 0);
      expect(entries.growing?.lit, 12);
      expect(entries.finished, isEmpty);
    });

    test('the night the 29th star lights it, the heart is kept and nothing else grows yet', () {
      final tonight = SkyMapPlan.entriesOf(seriesOf(29, litToday: true));
      expect(tonight.growing, isNull);
      expect(tonight.finished.map((chapter) => chapter.index), [0]);
      expect(tonight.finished.single.complete, isTrue);

      final next = SkyMapPlan.entriesOf(seriesOf(29));
      expect(next.growing?.index, 1);
      expect(next.growing?.lit, 0);
      expect(next.growing?.shape, ConstellationShape.moon);
      expect(next.finished.map((chapter) => chapter.index), [0]);
    });

    test('older constellations follow the newer ones', () {
      final entries = SkyMapPlan.entriesOf(seriesOf(70));
      expect(entries.growing?.index, 2);
      expect(entries.growing?.lit, 12);
      expect(entries.growing?.shape, ConstellationShape.infinity);
      expect(entries.finished.map((chapter) => chapter.index), [1, 0]);
      expect(entries.finished.map((chapter) => chapter.shape), [ConstellationShape.moon, ConstellationShape.heart]);
    });
  });

  group('each constellation is drawn as it was lit', () {
    test('a finished one shines whole with no waiting gap', () {
      final series = seriesOf(60);
      for (final index in [0, 1]) {
        final chapter = series.chapter(index);
        final figure = SkyMapPlan.figure(chapter, litToday: false);
        expect(figure.shape, chapter.shape);
        expect(figure.complete, isTrue);
        expect(figure.gap, isNull);
        expect(figure.presence, isFalse);
        expect(figure.burst, isFalse);
        expect(figure.litPoints, hasLength(29));
      }
    });

    test('a growing one shows its lit stars and keeps tonight waiting in the next slot', () {
      final chapter = seriesOf(41).current;
      final waiting = SkyMapPlan.figure(chapter, litToday: false);
      expect(waiting.shape, ConstellationShape.moon);
      expect(waiting.gap, chapter.nextSlot);
      expect(waiting.litPoints.toSet(), chapter.litSlots);
      expect(waiting.unlit, hasLength(29 - 12 - 1));

      final lit = SkyMapPlan.figure(seriesOf(41, litToday: true).current, litToday: true);
      expect(lit.gap, isNull);
      expect(lit.litPoints.toSet(), seriesOf(41, litToday: true).current.litSlots);
      expect(lit.unlit, hasLength(29 - 12));
    });

    test('a constellation waiting for its first star only shows where it will begin', () {
      final chapter = seriesOf(29).current;
      final figure = SkyMapPlan.figure(chapter, litToday: false);
      expect(figure.gap, ConstellationShape.moon.me);
      expect(figure.litPoints, isEmpty);

      final first = SkyMapPlan.waiting();
      expect(first.shape, ConstellationShape.heart);
      expect(first.gap, ConstellationShape.heart.me);
      expect(first.litPoints, isEmpty);
    });
  });

  group('the large view fits the full sky', () {
    test('the frame sits below the title and above the hint on a phone', () {
      const size = Size(390, 844);
      const padding = EdgeInsets.only(top: 47, bottom: 34);
      final frame = SkyMapPlan.frameFor(size, padding);
      expect(SkyMapPlan.scaleOf(390), 1);
      expect(frame.top, 47 + 150);
      expect(frame.bottom, 844 - 34 - 130);
      expect(frame.width, 390);
      for (final shape in ConstellationShape.values) {
        final fitted = SkyMapPlan.fit(SkyConstellation(shape: shape), frame);
        final bounds = fitted.bounds;
        expect(bounds.left, greaterThanOrEqualTo(frame.left + SkyMapPlan.margin - 1e-6), reason: shape.name);
        expect(bounds.right, lessThanOrEqualTo(frame.right - SkyMapPlan.margin + 1e-6), reason: shape.name);
        expect(bounds.top, greaterThanOrEqualTo(frame.top + SkyMapPlan.margin - 1e-6), reason: shape.name);
        expect(bounds.bottom, lessThanOrEqualTo(frame.bottom - SkyMapPlan.margin + 1e-6), reason: shape.name);
        expect(fitted.scale, greaterThan(const SkyConstellation().scale), reason: shape.name);
        expect(fitted.scale, lessThanOrEqualTo(SkyMapPlan.maxScale), reason: shape.name);
      }
    });

    test('on a tall or wide screen it stays a gentle size and centred', () {
      final frame = SkyMapPlan.frameFor(const Size(1000, 2400), EdgeInsets.zero);
      expect(SkyMapPlan.scaleOf(1000), 520 / 390);
      for (final shape in ConstellationShape.values) {
        final fitted = SkyMapPlan.fit(SkyConstellation(shape: shape), frame);
        expect(fitted.scale, SkyMapPlan.maxScale, reason: shape.name);
        expect((fitted.bounds.center - frame.center).distance, lessThan(1e-6), reason: shape.name);
      }
      final short = SkyMapPlan.frameFor(const Size(390, 300), EdgeInsets.zero);
      expect(short.height, greaterThanOrEqualTo(160));
    });
  });

  group('the map speaks warmly', () {
    test('counts, growth and finished nights', () {
      final series = seriesOf(41);
      final heart = series.chapter(0);
      final moon = series.current;
      expect(SkyMapCopy.kicker(0), 'Before the first star');
      expect(SkyMapCopy.kicker(1), 'One star so far');
      expect(SkyMapCopy.kicker(41), '41 stars so far');
      expect(SkyMapCopy.nights(29), '29 nights');
      expect(SkyMapCopy.nights(1), '1 night');
      expect(SkyMapCopy.stillGrowing(12), 'Still growing · 12 of 29');
      expect(SkyMapCopy.status(heart), '29 nights');
      expect(SkyMapCopy.status(moon), 'Still growing · 12 of 29');
      expect(SkyMapCopy.status(seriesOf(29).current), SkyMapCopy.waitingFirst);
      expect(
        SkyMapCopy.card(heart),
        'Our first constellation · The Heart, ${StarNightCopy.range(heart)}, 29 nights',
      );
      expect(StarNightCopy.range(heart), '1 January – 29 January');
      expect(SkyMapCopy.card(seriesOf(29).current), 'Our second constellation · The Moon, Waiting for its first star');
      expect(SkyMapCopy.sky(moon), 'Our second constellation · The Moon. Still growing · 12 of 29.');
      expect(SkyMapCopy.emptyMessage(night: true), contains("tonight's question"));
      expect(SkyMapCopy.emptyMessage(night: false), contains("today's question"));
    });

    test('no engine words and no emoji in any line', () {
      final series = seriesOf(41);
      final lines = [
        SkyMapCopy.title,
        SkyMapCopy.action,
        SkyMapCopy.seeInMap,
        SkyMapCopy.finished,
        SkyMapCopy.keepNote,
        SkyMapCopy.everyDayNote,
        SkyMapCopy.emptyTitle,
        SkyMapCopy.waitingFirst,
        SkyMapCopy.kicker(0),
        SkyMapCopy.kicker(41),
        SkyMapCopy.emptyMessage(night: true),
        SkyMapCopy.emptyMessage(night: false),
        SkyMapCopy.card(series.chapter(0)),
        SkyMapCopy.card(series.current),
        SkyMapCopy.sky(series.current),
      ];
      for (final line in lines) {
        expect(_emoji.hasMatch(line), isFalse, reason: line);
        expect(_engineWords.hasMatch(line), isFalse, reason: line);
      }
    });
  });
}
