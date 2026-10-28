import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_drawn_placement.dart';
import 'package:our_space_mobile/presentation/sky/sky_constellation.dart';
import 'package:our_space_mobile/presentation/sky/sky_scene.dart';

const Size homeSky = Size(390, 444);
const double topBar = 128;
const double sheetTop = 404;

List<String> ids(int count) => [for (var i = 0; i < count; i++) 'sky-$i'];

void expectClear(List<SkyDrawnSpot> spots, List<Rect> avoid, Size sky) {
  for (final spot in spots) {
    expect((Offset.zero & sky).contains(spot.rect.topLeft), isTrue, reason: '$spot');
    expect(spot.rect.right, lessThanOrEqualTo(sky.width));
    expect(spot.rect.bottom, lessThanOrEqualTo(sky.height));
    for (final area in avoid) {
      expect(spot.rect.overlaps(area), isFalse, reason: '$spot over $area');
    }
    for (final other in spots) {
      if (identical(other, spot)) continue;
      expect(spot.rect.overlaps(other.rect), isFalse, reason: '$spot over $other');
    }
  }
}

void main() {
  for (final shape in ConstellationShape.values) {
    test('${shape.title} at night: up to six drawings, faint and small, around the edges and clear of everything', () {
      final constellation = SkyScene.home.constellation!.copyWith(shape: shape);
      final avoid = SkyDrawnPlacement.homeAvoid(
        sky: homeSky,
        constellation: constellation.bounds,
        topBarBottom: topBar,
        sheetTop: sheetTop,
        moon: SkyScene.home.moon,
      );
      final spots = SkyDrawnPlacement.place(sky: homeSky, avoid: avoid, ids: ids(9));
      expect(spots.length, inInclusiveRange(2, SkyDrawnPlacement.maxShown));
      expect(spots.map((s) => s.id), ids(spots.length));
      expectClear(spots, avoid, homeSky);
      for (final spot in spots) {
        expect(spot.rect.width, SkyDrawnPlacement.size);
        final nearEdge = spot.rect.left < 120 || spot.rect.right > homeSky.width - 120 || spot.rect.top < topBar + 60;
        expect(nearEdge, isTrue, reason: '$spot');
      }
      for (var i = 1; i < spots.length; i++) {
        expect(spots[i].opacity, lessThanOrEqualTo(spots[i - 1].opacity));
      }
      expect(spots.first.opacity, SkyDrawnPlacement.newestOpacity);
      expect(spots.every((s) => s.opacity <= 0.34 && s.opacity >= SkyDrawnPlacement.faintest), isTrue);
    });
  }

  test('by day the sun is kept clear too, and the same sky always gives the same places', () {
    final avoid = SkyDrawnPlacement.homeAvoid(
      sky: homeSky,
      constellation: SkyScene.home.constellation!.bounds,
      topBarBottom: topBar,
      sheetTop: sheetTop,
      sun: SkyScene.home.sunAt,
    );
    final once = SkyDrawnPlacement.place(sky: homeSky, avoid: avoid, ids: ids(6));
    final again = SkyDrawnPlacement.place(sky: homeSky, avoid: avoid, ids: ids(6));
    expect(once, again);
    expect(once, isNotEmpty);
    expectClear(once, avoid, homeSky);
    final sun = Rect.fromCircle(center: SkyScene.home.sunAt!, radius: SkyDrawnPlacement.sunReach);
    expect(once.any((s) => s.rect.overlaps(sun)), isFalse);
  });

  test('the first two drawings land on opposite sides, so they scatter instead of bunching', () {
    final avoid = SkyDrawnPlacement.homeAvoid(
      sky: homeSky,
      constellation: SkyScene.home.constellation!.bounds,
      topBarBottom: topBar,
      sheetTop: sheetTop,
      moon: SkyScene.home.moon,
    );
    final spots = SkyDrawnPlacement.place(sky: homeSky, avoid: avoid, ids: ids(2));
    expect(spots.length, 2);
    final left = spots.where((s) => s.rect.center.dx < homeSky.width / 2).length;
    expect(left, 1);
  });

  test('extra areas such as names and tips are avoided, repeats are skipped, and no room means none', () {
    const label = Rect.fromLTWH(0, 130, 390, 60);
    final avoid = SkyDrawnPlacement.homeAvoid(
      sky: homeSky,
      constellation: const Rect.fromLTWH(100, 200, 190, 190),
      topBarBottom: topBar,
      sheetTop: sheetTop,
      extra: const [label],
    );
    final spots = SkyDrawnPlacement.place(sky: homeSky, avoid: avoid, ids: ['sky-a', 'sky-a', 'sky-b']);
    expect(spots.map((s) => s.id), ['sky-a', 'sky-b']);
    expectClear(spots, avoid, homeSky);

    expect(
      SkyDrawnPlacement.place(sky: homeSky, avoid: [Offset.zero & homeSky], ids: ids(3)),
      isEmpty,
    );
    expect(SkyDrawnPlacement.place(sky: Size.zero, avoid: const [], ids: ids(3)), isEmpty);
    expect(SkyDrawnPlacement.place(sky: homeSky, avoid: const [], ids: const []), isEmpty);
    expect(SkyDrawnPlacement.place(sky: homeSky, avoid: const [], ids: ids(10), max: 3).length, 3);
    expect(SkyDrawnPlacement.place(sky: homeSky, avoid: const [], ids: ids(10), max: 9).length, SkyDrawnPlacement.maxShown);
  });

  test('older drawings fade a little more each, never below the faintest', () {
    expect(SkyDrawnPlacement.opacityFor(0), SkyDrawnPlacement.newestOpacity);
    expect(SkyDrawnPlacement.opacityFor(1), closeTo(0.305, 1e-9));
    expect(SkyDrawnPlacement.opacityFor(40), SkyDrawnPlacement.faintest);
  });
}
