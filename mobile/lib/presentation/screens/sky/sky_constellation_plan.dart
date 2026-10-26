import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sky/sky.dart';
import 'sky_constellations.dart';

enum SkyTipSide { right, left, below, above }

@immutable
class SkyTipPlacement {
  const SkyTipPlacement({required this.side, required this.offset, required this.alignment, required this.arrow});

  final SkyTipSide side;
  final Offset offset;
  final Alignment alignment;
  final bool arrow;

  @override
  bool operator ==(Object other) =>
      other is SkyTipPlacement &&
      other.side == side &&
      other.offset == offset &&
      other.alignment == alignment &&
      other.arrow == arrow;

  @override
  int get hashCode => Object.hash(side, offset, alignment, arrow);
}

abstract final class SkyConstellationPlan {
  static const int points = SkyConstellation.count;

  static int constellationOf({required int stars, required bool litToday}) {
    if (stars <= 0) return 0;
    return litToday ? (stars - 1) ~/ points : stars ~/ points;
  }

  static ConstellationShape shapeFor({required int stars, required bool litToday}) =>
      ConstellationShape.at(constellationOf(stars: stars, litToday: litToday));

  static int litIn({required int stars, required bool litToday}) {
    if (stars <= 0) return 0;
    return stars - constellationOf(stars: stars, litToday: litToday) * points;
  }

  static bool completes(int stars) => stars > 0 && stars % points == 0;

  static int? tonightSlot({required int stars, required bool litToday}) {
    if (litToday) return null;
    return shapeFor(stars: stars, litToday: false).order[litIn(stars: stars, litToday: false)];
  }

  static Set<int> _unlitFrom(ConstellationShape shape, int start) => {
    for (var i = start; i < points; i++) shape.order[i],
  };

  static SkyConstellation home({
    required int stars,
    required bool litToday,
    required bool presence,
    SkyConstellation base = const SkyConstellation(),
  }) {
    final shape = shapeFor(stars: stars, litToday: litToday);
    final lit = litIn(stars: stars, litToday: litToday);
    if (litToday || lit >= points) {
      return base.copyWith(
        shape: shape,
        clearGap: true,
        complete: lit >= points,
        burst: false,
        presence: presence,
        unlit: _unlitFrom(shape, lit),
      );
    }
    return base.copyWith(
      shape: shape,
      gap: shape.order[lit],
      complete: false,
      burst: false,
      presence: presence,
      unlit: _unlitFrom(shape, lit + 1),
    );
  }

  static SkyConstellation forSeries(
    ConstellationSeries series, {
    required bool presence,
    SkyConstellation base = const SkyConstellation(),
  }) => home(stars: series.stars, litToday: series.litToday, presence: presence, base: base);

  static int burstSlot(int stars) {
    final total = math.max(stars, 1);
    final lit = litIn(stars: total, litToday: true);
    return shapeFor(stars: total, litToday: true).order[lit - 1];
  }

  static SkyConstellation reveal({required int stars, SkyConstellation base = const SkyConstellation()}) {
    final total = math.max(stars, 1);
    final shape = shapeFor(stars: total, litToday: true);
    final lit = litIn(stars: total, litToday: true);
    return base.copyWith(
      shape: shape,
      gap: burstSlot(total),
      complete: true,
      burst: true,
      presence: false,
      unlit: _unlitFrom(shape, lit),
    );
  }

  static String completeLine(int stars) =>
      ConstellationChapter.completeLineOf(constellationOf(stars: stars, litToday: true));

  static const Size tipSize = Size(112, 40);
  static const double tipGap = 18;
  static const double designWidth = 390;

  static const SkyTipPlacement right = SkyTipPlacement(
    side: SkyTipSide.right,
    offset: Offset(tipGap, -tipGap),
    alignment: Alignment.topLeft,
    arrow: true,
  );

  static const SkyTipPlacement left = SkyTipPlacement(
    side: SkyTipSide.left,
    offset: Offset(-tipGap, -tipGap),
    alignment: Alignment.topRight,
    arrow: false,
  );

  static const SkyTipPlacement below = SkyTipPlacement(
    side: SkyTipSide.below,
    offset: Offset(0, 16),
    alignment: Alignment.topCenter,
    arrow: false,
  );

  static const SkyTipPlacement belowFar = SkyTipPlacement(
    side: SkyTipSide.below,
    offset: Offset(0, 40),
    alignment: Alignment.topCenter,
    arrow: false,
  );

  static const SkyTipPlacement above = SkyTipPlacement(
    side: SkyTipSide.above,
    offset: Offset(0, -16),
    alignment: Alignment.bottomCenter,
    arrow: false,
  );

  static Rect tipRect(Offset point, SkyTipPlacement placement, [Size size = tipSize]) {
    final top = point.dy + placement.offset.dy;
    switch (placement.side) {
      case SkyTipSide.right:
        return Rect.fromLTWH(point.dx + placement.offset.dx, top, size.width, size.height);
      case SkyTipSide.left:
        return Rect.fromLTWH(point.dx + placement.offset.dx - size.width, top, size.width, size.height);
      case SkyTipSide.below:
        return Rect.fromLTWH(point.dx + placement.offset.dx - size.width / 2, top, size.width, size.height);
      case SkyTipSide.above:
        return Rect.fromLTWH(point.dx + placement.offset.dx - size.width / 2, top - size.height, size.width, size.height);
    }
  }

  static const Size meLabelSize = Size(64, 22);

  static Size partnerLabelSize({required bool chip}) => Size(80, chip ? 40 : 22);

  static List<Rect> labelAreas(
    SkyConstellation constellation, {
    required bool me,
    required bool partner,
    required bool partnerChip,
  }) {
    final shape = constellation.shape;
    return [
      if (me) shape.meLabel.area(constellation.pointAt(constellation.me), meLabelSize),
      if (partner)
        shape.partnerLabel.area(
          constellation.pointAt(constellation.partner),
          partnerLabelSize(chip: partnerChip),
        ),
    ];
  }

  static double tipCost(
    Offset point,
    SkyTipPlacement placement, {
    Size size = tipSize,
    SkyConstellation? constellation,
    List<Rect> avoid = const [],
  }) {
    final rect = tipRect(point, placement, size);
    if (rect.left < 0 || rect.right > designWidth || rect.top < 0) return double.infinity;
    var cost = switch (placement.side) {
      SkyTipSide.right || SkyTipSide.left => 0.0,
      SkyTipSide.above => 100.0,
      SkyTipSide.below => 300.0,
    };
    for (final area in avoid) {
      final overlap = rect.intersect(area);
      if (overlap.width > 0 && overlap.height > 0) cost += overlap.width * overlap.height;
    }
    if (constellation != null) {
      for (final i in constellation.litPoints) {
        if (rect.contains(constellation.pointAt(i))) cost += 400;
      }
    }
    return cost;
  }

  static SkyTipPlacement tipFor(
    Offset point, {
    SkyConstellation? constellation,
    List<Rect> avoid = const [],
    Size size = tipSize,
  }) {
    final outside = point.dx >= 195 ? right : left;
    final inside = point.dx >= 195 ? left : right;
    var best = outside;
    var bestCost = double.infinity;
    for (final placement in [outside, inside, above, belowFar]) {
      final cost = tipCost(point, placement, size: size, constellation: constellation, avoid: avoid);
      if (cost < bestCost) {
        best = placement;
        bestCost = cost;
      }
    }
    return best;
  }
}
