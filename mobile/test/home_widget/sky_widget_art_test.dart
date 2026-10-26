import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/home_widget/sky_widget_art.dart';
import 'package:our_space_mobile/presentation/home_widget/sky_widget_state.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_constellations.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

ConstellationSeries seriesOf(int stars) {
  final days = [for (var i = 0; i < stars; i++) DateTime.utc(2026, 1, 1 + i).toIso8601String().substring(0, 10)];
  return ConstellationSeries.fromDays(days, today: days.isEmpty ? '2026-01-01' : days.last);
}

Future<ui.Image> decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<Color> pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final at = (y * image.width + x) * 4;
  return Color.fromARGB(data.getUint8(at + 3), data.getUint8(at), data.getUint8(at + 1), data.getUint8(at + 2));
}

bool near(Color a, Color b, {double tolerance = 0.08}) =>
    (a.r - b.r).abs() <= tolerance && (a.g - b.g).abs() <= tolerance && (a.b - b.b).abs() <= tolerance;

const List<int> pngSignature = [0x89, 0x50, 0x4E, 0x47];

void main() {
  group('the widget picture', () {
    test('the constellation is fitted into a square with room for its glow', () {
      final state = SkyWidgetState.forSeries(seriesOf(12), night: true);
      final figure = SkyWidgetArt.figureFor(state)!;
      const box = Rect.fromLTWH(0, 0, SkyWidgetArt.designSide, SkyWidgetArt.designSide);
      expect(box.deflate(SkyWidgetArt.margin - 0.001).contains(figure.bounds.topLeft), isTrue);
      expect(box.deflate(SkyWidgetArt.margin - 0.001).contains(figure.bounds.bottomRight), isTrue);
      expect(figure.bounds.center.dx, closeTo(SkyWidgetArt.designSide / 2, 0.001));
      expect(figure.unlit, state.constellation!.unlit);
      expect(figure.shape, state.constellation!.shape);
      expect(SkyWidgetArt.figureFor(const SkyWidgetState.empty()), isNull);
    });

    test('the star layer paints only the constellation, still and without people', () {
      final figure = SkyWidgetArt.figureFor(SkyWidgetState.forSeries(seriesOf(3), night: true))!;
      final scene = SkyWidgetArt.starsScene(figure);
      expect(scene.stars, 0);
      expect(scene.dayStars, 0);
      expect(scene.sun, isFalse);
      expect(scene.clouds, isEmpty);
      expect(scene.moon, isNull);
      expect(scene.shootingStar, isNull);
      expect(scene.twinkle, isFalse);
      expect(scene.constellation, figure);
      expect(scene.constellation!.presence, isFalse);
      expect(SkyWidgetArt.backdrop.constellation, isNull);
      expect(SkyWidgetArt.backdrop.moon, isNull);
      expect(SkyWidgetArt.backdrop.shootingStar, isNull);
      expect(SkyWidgetArt.backdrop.twinkle, isFalse);
    });

    testWidgets('an empty sky is one opaque picture and no stars', (tester) async {
      await tester.runAsync(() async {
        const art = SkyWidgetArt(side: 60);
        final images = await art.render(const SkyWidgetState.empty());
        expect(images.stars, isNull);
        expect(images.sky.take(4), pngSignature);
        final sky = await decode(images.sky);
        expect(sky.width, art.skyPixels);
        expect(sky.height, art.skyPixels);
        expect((await pixel(sky, 0, 0)).a, 1);
        final top = await pixel(sky, sky.width ~/ 2, 0);
        expect(top.computeLuminance(), lessThan(0.05));
        expect(near(top, SkyTokens.night.skyTop, tolerance: 0.12), isTrue);
      });
    });

    testWidgets('a day sky is painted in day colours', (tester) async {
      await tester.runAsync(() async {
        const art = SkyWidgetArt(side: 60);
        final images = await art.render(const SkyWidgetState.empty(night: false));
        final sky = await decode(images.sky);
        final top = await pixel(sky, sky.width ~/ 2, 0);
        expect(top.computeLuminance(), greaterThan(0.4));
        expect(top.b, greaterThan(top.r));
      });
    });

    testWidgets('stars are painted on a clear layer at a sharper size', (tester) async {
      await tester.runAsync(() async {
        const art = SkyWidgetArt(side: 80);
        final state = SkyWidgetState.forSeries(seriesOf(29), night: true);
        final images = await art.render(state);
        final stars = await decode(images.stars!);
        expect(stars.width, art.starsPixels);
        expect(stars.height, art.starsPixels);
        expect(art.starsPixels, greaterThan(art.skyPixels));
        expect((await pixel(stars, 0, 0)).a, 0);
        final me = SkyWidgetArt.figureFor(state)!.pointAt(state.constellation!.me);
        final scale = art.starsPixels / SkyWidgetArt.designSide;
        final core = await pixel(stars, (me.dx * scale).round(), (me.dy * scale).round());
        expect(core.a, greaterThan(0.9));
      });
    });

    test('the default sizes stay light enough for a home screen', () {
      const art = SkyWidgetArt();
      expect(art.skyPixels, 480);
      expect(art.starsPixels, 600);
    });
  });
}
