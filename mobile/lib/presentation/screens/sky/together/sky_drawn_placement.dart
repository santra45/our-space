import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

@immutable
class SkyDrawnSpot {
  const SkyDrawnSpot({required this.id, required this.rect, required this.opacity});

  final String id;
  final Rect rect;
  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is SkyDrawnSpot && other.id == id && other.rect == rect && other.opacity == opacity;

  @override
  int get hashCode => Object.hash(id, rect, opacity);

  @override
  String toString() => 'SkyDrawnSpot($id, $rect, $opacity)';
}

abstract final class SkyDrawnPlacement {
  static const int maxShown = 6;
  static const double size = 46;
  static const double margin = 8;
  static const double gap = 12;
  static const double step = 4;
  static const double newestOpacity = 0.34;
  static const double fadeStep = 0.035;
  static const double faintest = 0.16;
  static const double moonReach = 40;
  static const double sunReach = 64;
  static const double constellationReach = 16;

  static double opacityFor(int index) => math.max(faintest, newestOpacity - index * fadeStep);

  static List<Rect> homeAvoid({
    required Size sky,
    required Rect constellation,
    required double topBarBottom,
    required double sheetTop,
    Offset? moon,
    Offset? sun,
    List<Rect> extra = const [],
  }) => [
    constellation.inflate(constellationReach),
    Rect.fromLTRB(0, 0, sky.width, topBarBottom),
    Rect.fromLTRB(0, sheetTop, sky.width, math.max(sheetTop, sky.height)),
    if (moon != null) Rect.fromCircle(center: moon, radius: moonReach),
    if (sun != null) Rect.fromCircle(center: sun, radius: sunReach),
    ...extra,
  ];

  static List<SkyDrawnSpot> place({
    required Size sky,
    required List<Rect> avoid,
    required List<String> ids,
    double size = size,
    double margin = margin,
    double gap = gap,
    double step = step,
    int max = maxShown,
  }) {
    if (sky.isEmpty || ids.isEmpty || size <= 0) return const [];
    final bounds = Offset.zero & sky;
    final blocked = [for (final r in avoid) r.inflate(gap)];
    final candidates = <Rect>[];
    for (var y = margin; y + size <= sky.height - margin; y += step) {
      for (var x = margin; x + size <= sky.width - margin; x += step) {
        final rect = Rect.fromLTWH(x, y, size, size);
        if (!bounds.contains(rect.topLeft) || blocked.any((b) => b.overlaps(rect))) continue;
        candidates.add(rect);
      }
    }
    final spots = <SkyDrawnSpot>[];
    final seen = <String>{};
    for (final id in ids) {
      if (spots.length >= math.min(max, maxShown)) break;
      if (!seen.add(id)) continue;
      Rect? best;
      var bestScore = double.infinity;
      for (final rect in candidates) {
        if (spots.any((s) => s.rect.inflate(gap).overlaps(rect))) continue;
        final edge = math.min(rect.left, sky.width - rect.right);
        var nearest = sky.longestSide;
        for (final s in spots) {
          nearest = math.min(nearest, (s.rect.center - rect.center).distance);
        }
        final spread = spots.isEmpty ? 0.0 : math.min(nearest, sky.shortestSide) * 0.75;
        final score = edge - spread + rect.top * 0.01;
        if (score < bestScore) {
          best = rect;
          bestScore = score;
        }
      }
      if (best == null) break;
      spots.add(SkyDrawnSpot(id: id, rect: best, opacity: opacityFor(spots.length)));
    }
    return spots;
  }
}
