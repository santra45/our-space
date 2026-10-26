import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

class MoonCanvas implements Canvas {
  final List<Paint> circles = [];
  final List<Path> paths = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(paint);

  @override
  void drawPath(Path path, Paint paint) => paths.add(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

MoonCanvas paintMoon(MoonPhase? phase, {SkyTokens tokens = SkyTokens.night, Offset? moon = const Offset(100, 100)}) {
  final canvas = MoonCanvas();
  SkyBackdropPainter(
    scene: SkyScene(
      stars: 0,
      dayStars: 0,
      moon: moon,
      moonPhase: phase,
      sun: false,
      clouds: const [],
      haze: false,
    ),
    tokens: tokens,
  ).paint(canvas, const Size(390, 484));
  return canvas;
}

int rings(MoonCanvas canvas) => canvas.circles.where((paint) => paint.style == PaintingStyle.stroke).length;

double ageOn(DateTime moment) => MoonPhase.at(moment).age;

void main() {
  group('the moon tonight is worked out from the date', () {
    test('the cycle starts at the reference new moon and repeats every synodic month', () {
      expect(MoonPhase.synodicMonth, 29.530588853);
      expect(MoonPhase.referenceNewMoon, DateTime.utc(2000, 1, 6, 18, 14));
      expect(ageOn(DateTime.utc(2000, 1, 6, 18, 14)), closeTo(0, 1e-9));
      final later = DateTime.utc(2000, 1, 6, 18, 14).add(const Duration(days: 10));
      expect(ageOn(later), closeTo(10, 1e-6));
      expect(ageOn(DateTime.utc(1999, 12, 31)), inInclusiveRange(0, MoonPhase.synodicMonth));
      expect(MoonPhase.at(DateTime.utc(1999, 12, 31)).name, 'Half moon');
    });

    test('full moon on 26 October 2026 and new moon on 9 November 2026, within a day of the tables', () {
      final full = MoonPhase.at(DateTime.utc(2026, 10, 26, 4, 12));
      expect(full.daysFromFull, lessThan(1));
      expect(full.name, 'Full moon');
      expect(full.illumination, greaterThan(0.99));

      final dark = MoonPhase.at(DateTime.utc(2026, 11, 9, 7, 2));
      expect(dark.daysFromNew, lessThan(1));
      expect(dark.name, 'New moon');
      expect(dark.illumination, lessThan(0.01));
      expect(dark.isNew, isTrue);

      expect(MoonPhase.at(DateTime.utc(2026, 10, 10, 15, 50)).daysFromNew, lessThan(1));
      expect(MoonPhase.at(DateTime.utc(2026, 11, 24, 14, 53)).daysFromFull, lessThan(1));
      expect(MoonPhase.at(DateTime.utc(2024, 4, 8, 18, 21)).daysFromNew, lessThan(1));
    });

    test('every night of the month gets a plain, warm name', () {
      expect(MoonPhase.at(DateTime.utc(2026, 10, 18, 16, 13)).name, 'Half moon');
      expect(MoonPhase.at(DateTime.utc(2026, 11, 1, 20, 28)).name, 'Half moon');
      expect(MoonPhase.at(DateTime.utc(2026, 10, 14, 12)).name, 'A growing crescent');
      expect(MoonPhase.at(DateTime.utc(2026, 10, 22, 12)).name, 'Almost full');
      expect(MoonPhase.at(DateTime.utc(2026, 10, 29, 12)).name, 'Just past full');
      expect(MoonPhase.at(DateTime.utc(2026, 11, 5, 12)).name, 'A fading crescent');
      expect(
        [for (final name in MoonPhaseName.values) name.label],
        [
          'New moon',
          'A growing crescent',
          'Half moon',
          'Almost full',
          'Full moon',
          'Just past full',
          'Half moon',
          'A fading crescent',
        ],
      );
      final stargazing = RegExp(r'(waxing|waning|gibbous|quarter)', caseSensitive: false);
      for (final name in MoonPhaseName.values) {
        expect(stargazing.hasMatch(name.label), isFalse, reason: name.label);
      }
    });

    test('the lit fraction grows to full and shrinks back, waxing then waning', () {
      final quarter = MoonPhase(MoonPhase.synodicMonth / 4);
      expect(quarter.illumination, closeTo(0.5, 1e-9));
      expect(quarter.waxing, isTrue);
      final last = MoonPhase(MoonPhase.synodicMonth * 3 / 4);
      expect(last.illumination, closeTo(0.5, 1e-9));
      expect(last.waxing, isFalse);
      expect(const MoonPhase(0).illumination, closeTo(0, 1e-12));
      expect(MoonPhase(MoonPhase.synodicMonth / 2).illumination, closeTo(1, 1e-12));
      expect(const MoonPhase(3).illumination, lessThan(const MoonPhase(6).illumination));
    });

    test('tonight holds still for the hour so the sky does not repaint', () {
      final a = MoonPhase.tonight(DateTime(2026, 10, 26, 21, 5, 12));
      final b = MoonPhase.tonight(DateTime(2026, 10, 26, 21, 58, 40));
      final c = MoonPhase.tonight(DateTime(2026, 10, 26, 22, 1));
      expect(a, b);
      expect(a, isNot(c));
      expect(a.age, closeTo(MoonPhase.at(DateTime(2026, 10, 26, 21)).age, 1e-12));
    });
  });

  group('the lit shape has a real terminator', () {
    const r = 10.0;

    test('a full moon is the whole disc and a new moon is dark', () {
      final full = MoonPhase(MoonPhase.synodicMonth / 2).litPath(r);
      expect(full.contains(const Offset(-8, 0)), isTrue);
      expect(full.contains(const Offset(8, 0)), isTrue);
      expect(full.getBounds().width, closeTo(2 * r, 0.01));
      expect(const MoonPhase(0).litPath(r).getBounds().isEmpty, isTrue);
    });

    test('quarters light half the disc on the side of the sun', () {
      final first = MoonPhase(MoonPhase.synodicMonth / 4).litPath(r);
      expect(first.contains(const Offset(5, 0)), isTrue);
      expect(first.contains(const Offset(-5, 0)), isFalse);
      final last = MoonPhase(MoonPhase.synodicMonth * 3 / 4).litPath(r);
      expect(last.contains(const Offset(-5, 0)), isTrue);
      expect(last.contains(const Offset(5, 0)), isFalse);
    });

    test('crescents are thin slivers and gibbous moons bulge past the middle', () {
      final crescent = const MoonPhase(4).litPath(r);
      expect(crescent.contains(const Offset(9, 0)), isTrue);
      expect(crescent.contains(const Offset(2, 0)), isFalse);
      expect(crescent.contains(const Offset(-5, 0)), isFalse);
      final waning = MoonPhase(MoonPhase.synodicMonth - 4).litPath(r);
      expect(waning.contains(const Offset(-9, 0)), isTrue);
      expect(waning.contains(const Offset(-2, 0)), isFalse);
      final gibbous = const MoonPhase(11).litPath(r);
      expect(gibbous.contains(const Offset(-3, 0)), isTrue);
      expect(gibbous.contains(const Offset(-9.5, 0)), isFalse);
      expect(gibbous.contains(const Offset(9, 0)), isTrue);
    });
  });

  group('the painter draws tonight\'s moon', () {
    test('at night with a soft halo, the lit shape and a faint ring only at new moon', () {
      final full = paintMoon(MoonPhase(MoonPhase.synodicMonth / 2));
      expect(full.paths, hasLength(3));
      expect(full.paths.first.getBounds().width, closeTo(2 * SkyShapes.moonRadius, 0.5));
      expect(rings(full), 0);
      expect(full.circles.where((paint) => paint.shader != null), hasLength(1));

      final dark = paintMoon(const MoonPhase(0.2));
      expect(rings(dark), 1);
      expect(dark.paths.every((path) => path.getBounds().width < 3), isTrue);

      final crescent = paintMoon(const MoonPhase(4));
      expect(rings(crescent), 0);
      expect(crescent.paths.first.contains(const Offset(SkyShapes.moonRadius - 0.5, 0)), isTrue);
      expect(crescent.paths.first.contains(const Offset(-SkyShapes.moonRadius / 2, 0)), isFalse);
    });

    test('without a phase the resting crescent shows, and nothing at all by day', () {
      final resting = paintMoon(null);
      expect(resting.paths, hasLength(3));
      expect(MoonPhase.resting.name, 'A growing crescent');
      expect(paintMoon(const MoonPhase(4), tokens: SkyTokens.day).paths, isEmpty);
      expect(paintMoon(const MoonPhase(4), moon: null).paths, isEmpty);
    });

    test('scenes compare by phase so a new night repaints', () {
      const a = SkyScene(moon: Offset(1, 1), moonPhase: MoonPhase(4));
      expect(a, const SkyScene(moon: Offset(1, 1), moonPhase: MoonPhase(4)));
      expect(a, isNot(const SkyScene(moon: Offset(1, 1), moonPhase: MoonPhase(5))));
      expect(a.copyWith().moonPhase, const MoonPhase(4));
      expect(SkyScene.home.moonPhase, isNull);
    });

    testWidgets('the canvas paints the real moon of tonight when a scene has none', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 484), disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Theme(
              data: ThemeData(extensions: const [SkyTokens.night]),
              child: const SkyCanvas(scene: SkyScene.home),
            ),
          ),
        ),
      );
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<SkyBackdropPainter>()
          .single;
      expect((painter.scene.moonPhase!.age - MoonPhase.at(DateTime.now()).age).abs(), lessThan(1 / 24 + 0.001));
      final pinned = SkyScene.home.copyWith(moonPhase: const MoonPhase(14));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 484), disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Theme(
              data: ThemeData(extensions: const [SkyTokens.night]),
              child: SkyCanvas(scene: pinned),
            ),
          ),
        ),
      );
      final again = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<SkyBackdropPainter>()
          .single;
      expect(again.scene.moonPhase, const MoonPhase(14));
    });
  });
}
