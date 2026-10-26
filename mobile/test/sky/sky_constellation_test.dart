import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

bool strokesOn(ConstellationShape shape) {
  final order = shape.order;
  final lit = <int>{order[0], order[1]};
  for (var k = 2; k < order.length; k++) {
    final next = order[k];
    var step = (order[k - 1] + 1) % SkyConstellation.count;
    while (lit.contains(step) && step != next) {
      step = (step + 1) % SkyConstellation.count;
    }
    if (k > 2 && step != next) return false;
    lit.add(next);
  }
  return true;
}

void main() {
  group('the four shapes', () {
    test('cycle heart, moon, infinity, star and back to the heart', () {
      expect(ConstellationShape.values, [
        ConstellationShape.heart,
        ConstellationShape.moon,
        ConstellationShape.infinity,
        ConstellationShape.star,
      ]);
      expect([for (var i = 0; i < 6; i++) ConstellationShape.at(i)], [
        ConstellationShape.heart,
        ConstellationShape.moon,
        ConstellationShape.infinity,
        ConstellationShape.star,
        ConstellationShape.heart,
        ConstellationShape.moon,
      ]);
      expect([for (final shape in ConstellationShape.values) shape.title], [
        'The Heart',
        'The Moon',
        'Infinity',
        'The Star',
      ]);
    });

    test('every shape holds 29 points and lights each once, the two of you first', () {
      for (final shape in ConstellationShape.values) {
        expect(shape.unit, hasLength(29), reason: shape.name);
        expect(shape.order, hasLength(29), reason: shape.name);
        expect(shape.order.toSet(), {for (var i = 0; i < 29; i++) i}, reason: shape.name);
        expect(shape.order.take(2), [shape.me, shape.partner], reason: shape.name);
        expect(shape.me, isNot(shape.partner), reason: shape.name);
      }
    });

    test('after the two bright stars each shape is drawn like one pen stroke', () {
      for (final shape in ConstellationShape.values) {
        expect(strokesOn(shape), isTrue, reason: shape.name);
      }
      expect(ConstellationShape.moon.order.skip(2).first, 1);
      expect(ConstellationShape.infinity.order.skip(2).first, 0);
      expect(ConstellationShape.star.order.skip(2).first, 0);
    });

    test('the heart keeps the sky.js points and lighting order', () {
      const heart = SkyConstellation();
      final t = 5 / 29 * math.pi * 2;
      final expected = Offset(
        195 + 6.4 * 16 * math.pow(math.sin(t), 3),
        284 - 6.4 * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)),
      );
      expect((heart.pointAt(5) - expected).distance, lessThan(1e-9));
      expect(ConstellationShape.heart.order, [
        24, 5, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 25, 26, 27, 28, 0, 1, 2, 3, 4, 6, 7, 8, 9, 10,
      ]);
      expect(heart.me, 24);
      expect(heart.partner, 5);
    });

    test('the new shapes sit where the heart sits and their stars stay apart', () {
      const heart = SkyConstellation();
      final home = heart.bounds.inflate(24);
      for (final shape in ConstellationShape.values.skip(1)) {
        final figure = SkyConstellation(shape: shape);
        final bounds = figure.bounds;
        expect(home.contains(bounds.topLeft) && home.contains(bounds.bottomRight), isTrue, reason: '${shape.name} $bounds');
        expect(bounds.width, greaterThan(150), reason: shape.name);
        expect(bounds.height, greaterThan(120), reason: shape.name);
        final points = figure.points;
        var nearest = double.infinity;
        for (var i = 0; i < points.length; i++) {
          for (var j = i + 1; j < points.length; j++) {
            nearest = math.min(nearest, (points[i] - points[j]).distance);
          }
        }
        expect(nearest, greaterThan(9), reason: shape.name);
      }
    });

    test('the moon is a crescent with the two of you on its horns', () {
      const moon = SkyConstellation(shape: ConstellationShape.moon);
      final top = moon.pointAt(moon.me);
      final bottom = moon.pointAt(moon.partner);
      expect(top.dy, lessThan(bottom.dy));
      for (final p in moon.points) {
        expect(p.dy, greaterThanOrEqualTo(top.dy - 0.01));
      }
      expect(moon.bounds.left, lessThan(top.dx));
    });

    test('infinity crosses itself once at the middle and the two of you top its loops', () {
      const infinity = SkyConstellation(shape: ConstellationShape.infinity);
      final middle = infinity.pointAt(0);
      expect(middle.dx, closeTo(infinity.bounds.center.dx, 0.5));
      final me = infinity.pointAt(infinity.me);
      final partner = infinity.pointAt(infinity.partner);
      expect(me.dx, lessThan(middle.dx));
      expect(partner.dx, greaterThan(middle.dx));
      expect(me.dy, closeTo(infinity.bounds.top, 2));
      expect(partner.dy, closeTo(infinity.bounds.top, 2));
    });

    test('the star has five points with the two of you on its arms', () {
      const star = SkyConstellation(shape: ConstellationShape.star);
      final center = star.center + const Offset(0, 3.5) * star.scale;
      final far = [
        for (var i = 0; i < 29; i++)
          if (((star.pointAt(i) - center).distance - 16.5 * star.scale).abs() < 0.01) i,
      ];
      expect(far, hasLength(5));
      expect(far, containsAll([star.me, star.partner]));
      expect(star.pointAt(star.me).dx, lessThan(center.dx));
      expect(star.pointAt(star.partner).dx, greaterThan(center.dx));
      expect(star.pointAt(star.me).dy, closeTo(star.pointAt(star.partner).dy, 0.01));
    });

    test('name labels stay inside the sky for every shape', () {
      for (final shape in ConstellationShape.values) {
        final figure = SkyConstellation(shape: shape);
        final me = shape.meLabel.area(figure.pointAt(figure.me), const Size(64, 22));
        final partner = shape.partnerLabel.area(figure.pointAt(figure.partner), const Size(80, 40));
        for (final area in [me, partner]) {
          expect(area.left, greaterThanOrEqualTo(0), reason: shape.name);
          expect(area.right, lessThanOrEqualTo(390), reason: shape.name);
          expect(area.top, greaterThan(150), reason: shape.name);
          expect(area.bottom, lessThan(404), reason: shape.name);
        }
      }
      const heart = SkyConstellation();
      final mine = heart.pointAt(heart.me);
      final area = ConstellationShape.heart.meLabel.area(mine, const Size(64, 22));
      expect((area.topLeft - Offset(mine.dx - 32, mine.dy + 16)).distance, lessThan(1e-9));
      expect(area.size, const Size(64, 22));
    });
  });

  group('drawing a constellation', () {
    test('centre and scale move the whole shape', () {
      for (final shape in ConstellationShape.values) {
        final small = SkyConstellation(shape: shape, center: const Offset(100, 100), scale: 3.2);
        final big = SkyConstellation(shape: shape, center: const Offset(100, 100), scale: 6.4);
        final a = small.pointAt(7) - const Offset(100, 100);
        final b = big.pointAt(7) - const Offset(100, 100);
        expect(b.dx, closeTo(a.dx * 2, 1e-9));
        expect(b.dy, closeTo(a.dy * 2, 1e-9));
      }
    });

    test('fits inside any box', () {
      for (final shape in ConstellationShape.values) {
        const box = Rect.fromLTWH(10, 20, 120, 90);
        final fitted = SkyConstellation(shape: shape).fitted(box, margin: 8);
        final bounds = fitted.bounds;
        expect(bounds.left, greaterThanOrEqualTo(18 - 1e-6), reason: shape.name);
        expect(bounds.right, lessThanOrEqualTo(122 + 1e-6), reason: shape.name);
        expect(bounds.top, greaterThanOrEqualTo(28 - 1e-6), reason: shape.name);
        expect(bounds.bottom, lessThanOrEqualTo(102 + 1e-6), reason: shape.name);
        expect(bounds.center.dx, closeTo(box.center.dx, 1e-6), reason: shape.name);
        expect(bounds.center.dy, closeTo(box.center.dy, 1e-6), reason: shape.name);
        expect(
          math.max(bounds.width - 104, bounds.height - 74).abs(),
          lessThan(1e-6),
          reason: shape.name,
        );
      }
    });

    test('a generous touch finds the nearest lit star and ignores the rest', () {
      const figure = SkyConstellation(gap: 10, unlit: {11, 12});
      final lit = figure.pointAt(3);
      expect(figure.starAt(lit), 3);
      expect(figure.starAt(lit + const Offset(16, 12)), 3);
      expect(figure.starAt(lit + const Offset(30, 30)), isNull);
      expect(figure.starAt(figure.pointAt(10)), isNot(10));
      expect(figure.starAt(figure.pointAt(11)), isNot(11));
      expect(figure.starAt(figure.pointAt(12)), isNot(12));
      expect(figure.litPoints, isNot(contains(10)));
      expect(figure.litPoints, hasLength(26));
      final between = Offset.lerp(figure.pointAt(20), figure.pointAt(21), 0.3)!;
      expect(figure.starAt(between), 20);
      expect(figure.starAt(lit + const Offset(4, 0), radius: 2), isNull);
      expect(const SkyConstellation(complete: true).litPoints, hasLength(29));
    });

    test('compares by value, shape included', () {
      const heart = SkyConstellation(gap: 10, unlit: {3});
      expect(heart.copyWith(), heart);
      expect(heart.copyWith(shape: ConstellationShape.moon), isNot(heart));
      expect(heart.copyWith(shape: ConstellationShape.moon).me, ConstellationShape.moon.me);
      expect(heart.copyWith(clearGap: true).gap, isNull);
    });
  });
}
