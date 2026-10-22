import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

Widget skyHost(
  Widget child, {
  SkyTokens tokens = SkyTokens.night,
  bool animations = false,
  Size size = const Size(390, 484),
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: !animations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: ThemeData(extensions: [tokens]),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(size: size, child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('icons', () {
    test('every icon from the design is here with its duotone svg', () {
      expect(skyDesignIcons, hasLength(24));
      for (final icon in SkyIcons.values) {
        expect(icon.svg, startsWith('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'));
        expect(icon.body, isNotEmpty);
        if (!icon.multicolor) expect(icon.body, contains('currentColor'), reason: icon.name);
      }
      expect(SkyIcons.sealedStar.multicolor, isTrue);
    });

    testWidgets('every icon parses with flutter_svg', (tester) async {
      await tester.runAsync(() async {
        for (final icon in SkyIcons.values) {
          final info = await vg.loadPicture(
            SvgStringLoader(icon.svg, theme: const SvgTheme(currentColor: Color(0xFFFF6B95))),
            null,
          );
          expect(info.size, const Size(24, 24), reason: icon.name);
          info.picture.dispose();
        }
      });
    });

    testWidgets('SkyIcon takes a name, a size and a colour', (tester) async {
      await tester.pumpWidget(
        skyHost(const Center(child: SkyIcon(SkyIcons.heart, size: 30, color: Color(0xFFFF6B95)))),
      );
      expect(tester.getSize(find.byType(SkyIcon)), const Size(30, 30));
      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(picture.width, 30);
      final loader = picture.bytesLoader as SvgStringLoader;
      expect(loader.theme?.currentColor, const Color(0xFFFF6B95));
    });

    testWidgets('SkyIcon falls back to the icon theme colour', (tester) async {
      await tester.pumpWidget(
        skyHost(
          const IconTheme(
            data: IconThemeData(color: Color(0xFF123456)),
            child: Center(child: SkyIcon(SkyIcons.star)),
          ),
        ),
      );
      final loader = tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader as SvgStringLoader;
      expect(loader.theme?.currentColor, const Color(0xFF123456));
      expect(tester.getSize(find.byType(SkyIcon)), const Size(20, 20));
    });
  });

  group('heart constellation', () {
    test('29 points follow the sky.js heart curve', () {
      const heart = HeartConstellation();
      final points = heart.points;
      expect(points, hasLength(HeartConstellation.count));
      final t = 5 / 29 * math.pi * 2;
      final expected = Offset(
        195 + 6.4 * 16 * math.pow(math.sin(t), 3),
        284 - 6.4 * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)),
      );
      expect((points[5] - expected).distance, lessThan(1e-9));
      expect(points[0].dx, closeTo(195, 1e-9));
      expect((points[24].dx - 195), closeTo(-(points[5].dx - 195), 1e-9));
      expect(points[24].dy, closeTo(points[5].dy, 1e-9));
    });

    test('centre and scale move the whole heart', () {
      const small = HeartConstellation(center: Offset(100, 100), scale: 3.2);
      const big = HeartConstellation(center: Offset(100, 100), scale: 6.4);
      final a = small.pointAt(7) - const Offset(100, 100);
      final b = big.pointAt(7) - const Offset(100, 100);
      expect(b.dx, closeTo(a.dx * 2, 1e-9));
      expect(b.dy, closeTo(a.dy * 2, 1e-9));
    });

    test('the gap is unlit until the heart is complete', () {
      const heart = HeartConstellation(gap: 10, unlit: {3});
      expect(heart.hasOpenGap, isTrue);
      expect(heart.isLit(10), isFalse);
      expect(heart.isLit(3), isFalse);
      expect(heart.isLit(4), isTrue);
      expect(heart.isBig(24), isTrue);
      expect(heart.isBig(5), isTrue);
      expect(heart.copyWith(complete: true).isLit(10), isTrue);
      expect(heart.copyWith(clearGap: true).gap, isNull);
      expect(heart.copyWith(complete: true), isNot(heart));
      expect(heart.copyWith(), heart);
    });

    test('the seeded sky matches the Park-Miller generator from sky.js', () {
      final rnd = SkyRandom(7);
      expect(rnd.next(), closeTo(7 * 16807 / 2147483647, 1e-12));
      final field = SkyField.build(SkyScene.home, night: true, designHeight: 484);
      expect(field.stars, hasLength(70));
      expect(field.stars.first.position.dx, closeTo(7 * 16807 / 2147483647 * 390, 1e-6));
      expect(field.sparkles, hasLength(9));
      expect(field.stars.where((s) => s.twinkles), isNotEmpty);
      final day = SkyField.build(SkyScene.home, night: false, designHeight: 484);
      expect(day.stars, hasLength(12));
      expect(day.stars.every((s) => s.position.dy >= 110), isTrue);
    });

    test('scenes compare by value so painters only repaint on change', () {
      expect(
        SkyScene.home,
        const SkyScene(
          moon: Offset(306, 134),
          sunAt: Offset(40, 420),
          skyline: 416,
          horizonGlow: true,
          heart: HeartConstellation(),
          shootingStar: SkyShootingStar(),
        ),
      );
      expect(SkyScene.home.copyWith(clearHeart: true).heart, isNull);
      expect(SkyScene.page.scaleFor(const Size(780, 100)), 2);
      expect(SkyScene.page.designHeightFor(const Size(780, 100)), 50);
      const shooting = SkyShootingStar();
      expect(shooting.pointAt(0), shooting.from);
      expect(shooting.pointAt(1), shooting.to);
    });

    test('skyline path spans the full width and reaches the bottom', () {
      final path = SkyShapes.skyline(416, bottom: 600);
      final bounds = path.getBounds();
      expect(bounds.left, 0);
      expect(bounds.right, 390);
      expect(bounds.top, 416);
      expect(bounds.bottom, 600);
    });
  });

  group('sky canvas', () {
    testWidgets('anchors sit on the heart points, scaled to the width', (tester) async {
      const scene = SkyScene(heart: HeartConstellation());
      await tester.pumpWidget(
        skyHost(
          const SkyCanvas(
            scene: scene,
            anchors: [
              SkyAnchor(
                at: SkyPoint.qalbi(),
                offset: Offset(0, 18),
                child: SizedBox(width: 40, height: 10, key: Key('q')),
              ),
              SkyAnchor(
                at: SkyPoint.gap(),
                offset: Offset(18, -18),
                alignment: Alignment.topLeft,
                child: SizedBox(width: 40, height: 10, key: Key('g')),
              ),
              SkyAnchor(
                at: SkyPoint.moon(),
                child: SizedBox(width: 4, height: 4, key: Key('m')),
              ),
            ],
          ),
          size: const Size(780, 968),
        ),
      );
      final q = scene.heart!.pointAt(24);
      final qRect = tester.getRect(find.byKey(const Key('q')));
      expect(qRect.center.dx, closeTo(q.dx * 2, 0.01));
      expect(qRect.top, closeTo((q.dy + 18) * 2, 0.01));
      final g = scene.heart!.pointAt(10);
      expect(tester.getTopLeft(find.byKey(const Key('g'))), offsetMoreOrLessEquals((g + const Offset(18, -18)) * 2));
      expect(find.byKey(const Key('m')), findsNothing);
    });

    testWidgets('stays still when animations are off, so the tree settles', (tester) async {
      await tester.pumpWidget(skyHost(const SkyCanvas(scene: SkyScene.home)));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<SkyLivePainter>()
          .single;
      expect(painter.time.seconds, 0);
      expect(painter.time.burst, 1);
      expect(painter.time.streak, 1);
    });

    testWidgets('twinkles, streaks the shooting star and bursts the new star with one ticker', (tester) async {
      const still = SkyScene(heart: HeartConstellation(complete: false));
      await tester.pumpWidget(skyHost(const SkyCanvas(scene: still), animations: true));
      await tester.pump(const Duration(milliseconds: 100));
      SkyLivePainter live() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<SkyLivePainter>()
          .single;
      expect(tester.hasRunningAnimations, isTrue);
      expect(live().time.seconds, greaterThan(0));

      await tester.pumpWidget(
        skyHost(
          const SkyCanvas(
            scene: SkyScene(heart: HeartConstellation(complete: true, burst: true), shootingStar: SkyShootingStar()),
          ),
          animations: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 200));
      expect(live().time.burst, inExclusiveRange(0, 1));
      expect(live().time.streak, inExclusiveRange(0, 1));
      await tester.pump(SkyMotion.burst);
      expect(live().time.burst, 1);
      expect(live().time.streak, 1);
    });

    testWidgets('paints day and night skies, the burst and the shooting star without errors', (tester) async {
      for (final tokens in [SkyTokens.night, SkyTokens.day]) {
        final key = GlobalKey();
        await tester.pumpWidget(
          skyHost(
            RepaintBoundary(
              key: key,
              child: SkyBackdrop(
                fade: true,
                scene: SkyScene.home.copyWith(
                  heart: const HeartConstellation(complete: true, burst: true, dim: 0.6, unlit: {2, 3}),
                ),
              ),
            ),
            tokens: tokens,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final image = await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          return boundary.toImage();
        });
        expect(image!.width, 390);
        final bytes = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
        final top = bytes!.getUint32(0);
        expect(top, isNonZero);
        image.dispose();
      }
    });
  });
}
