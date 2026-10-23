import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sky/sky.dart';

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

abstract final class SkyHeartPlan {
  static const int points = HeartConstellation.count;

  static const List<int> order = [24, 5, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 25, 26, 27, 28, 0, 1, 2, 3, 4, 6, 7, 8, 9, 10];

  static const Offset asideStar = Offset(195, 274);

  static int litCount(int stars) => stars.clamp(0, points);

  static Set<int> _unlitFrom(int start) => {for (var i = start; i < points; i++) order[i]};

  static bool tonightAside({required int stars, required bool litToday}) => !litToday && litCount(stars) >= points;

  static int? tonightIndex({required int stars, required bool litToday}) {
    if (litToday) return null;
    final lit = litCount(stars);
    return lit < points ? order[lit] : null;
  }

  static HeartConstellation home({
    required int stars,
    required bool litToday,
    required bool presence,
    HeartConstellation base = const HeartConstellation(),
  }) {
    final lit = litCount(stars);
    if (litToday || lit >= points) {
      return base.copyWith(
        clearGap: true,
        complete: lit >= points,
        burst: false,
        presence: presence,
        unlit: _unlitFrom(lit),
      );
    }
    return base.copyWith(
      gap: order[lit],
      complete: false,
      burst: false,
      presence: presence,
      unlit: _unlitFrom(lit + 1),
    );
  }

  static int burstIndex(int stars) {
    final total = math.max(stars, 1);
    final lit = litCount(total);
    return lit < points ? order[lit - 1] : order[(total - 1) % points];
  }

  static HeartConstellation reveal({required int stars, HeartConstellation base = const HeartConstellation()}) {
    final lit = litCount(math.max(stars, 1));
    return base.copyWith(
      gap: burstIndex(stars),
      complete: true,
      burst: true,
      presence: false,
      unlit: _unlitFrom(lit),
    );
  }

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

  static Size tipSizeFor(String title, String subtitle) =>
      Size(22 + math.max(15 + title.length * 5.4, subtitle.length * 5.0), tipSize.height);

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

  static List<Rect> labelAreas(
    HeartConstellation heart, {
    required bool me,
    required bool partner,
    required bool partnerChip,
  }) {
    final mine = heart.pointAt(heart.me);
    final theirs = heart.pointAt(heart.partner);
    return [
      if (me) Rect.fromLTWH(mine.dx - 32, mine.dy + 16, 64, 22),
      if (partner) Rect.fromLTWH(theirs.dx - 52, theirs.dy + 28, 80, partnerChip ? 40 : 22),
    ];
  }

  static double tipCost(
    Offset point,
    SkyTipPlacement placement, {
    Size size = tipSize,
    HeartConstellation? heart,
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
    if (heart != null) {
      for (var i = 0; i < points; i++) {
        if (heart.isLit(i) && rect.contains(heart.pointAt(i))) cost += 400;
      }
    }
    return cost;
  }

  static SkyTipPlacement tipFor(
    Offset point, {
    HeartConstellation? heart,
    List<Rect> avoid = const [],
    Size size = tipSize,
  }) {
    final outside = point.dx >= 195 ? right : left;
    final inside = point.dx >= 195 ? left : right;
    var best = outside;
    var bestCost = double.infinity;
    for (final placement in [outside, inside, above, belowFar]) {
      final cost = tipCost(point, placement, size: size, heart: heart, avoid: avoid);
      if (cost < bestCost) {
        best = placement;
        bestCost = cost;
      }
    }
    return best;
  }
}
