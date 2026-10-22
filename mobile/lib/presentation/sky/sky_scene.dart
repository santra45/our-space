import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

class SkyRandom {
  SkyRandom(int seed) : _seed = seed <= 0 ? 7 : seed;

  int _seed;

  double next() {
    _seed = (_seed * 16807) % 2147483647;
    return _seed / 2147483647;
  }
}

@immutable
class SkyCloud {
  const SkyCloud(this.x, this.y, {this.scale = 1, this.opacity = 0.85});

  final double x;
  final double y;
  final double scale;
  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is SkyCloud && other.x == x && other.y == y && other.scale == scale && other.opacity == opacity;

  @override
  int get hashCode => Object.hash(x, y, scale, opacity);
}

@immutable
class SkyShootingStar {
  const SkyShootingStar({
    this.from = const Offset(-6, 132),
    this.control = const Offset(52, 146),
    this.to = const Offset(112, 166),
    this.angle = 14,
    this.envelope = true,
  });

  final Offset from;
  final Offset control;
  final Offset to;
  final double angle;
  final bool envelope;

  Offset pointAt(double t) {
    final u = 1 - t;
    return from * (u * u) + control * (2 * u * t) + to * (t * t);
  }

  @override
  bool operator ==(Object other) =>
      other is SkyShootingStar &&
      other.from == from &&
      other.control == control &&
      other.to == to &&
      other.angle == angle &&
      other.envelope == envelope;

  @override
  int get hashCode => Object.hash(from, control, to, angle, envelope);
}

@immutable
class HeartConstellation {
  const HeartConstellation({
    this.center = const Offset(195, 284),
    this.scale = 6.4,
    this.gap = 10,
    this.qalbi = 24,
    this.farhu = 5,
    this.complete = false,
    this.burst = false,
    this.presence = true,
    this.dim = 1,
    this.unlit = const <int>{},
    this.gapGuide = true,
  });

  static const int count = 29;

  final Offset center;
  final double scale;
  final int? gap;
  final int qalbi;
  final int farhu;
  final bool complete;
  final bool burst;
  final bool presence;
  final double dim;
  final Set<int> unlit;
  final bool gapGuide;

  static Offset curve(double t, {Offset center = const Offset(195, 284), double scale = 6.4}) {
    final s = math.sin(t);
    return Offset(
      center.dx + scale * 16 * s * s * s,
      center.dy - scale * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)),
    );
  }

  Offset pointAt(int index) => curve((index % count) / count * math.pi * 2, center: center, scale: scale);

  List<Offset> get points => [for (var i = 0; i < count; i++) pointAt(i)];

  bool get hasOpenGap => gap != null && !complete;

  bool isLit(int index) => !unlit.contains(index) && !(hasOpenGap && index == gap);

  bool isBig(int index) => index == qalbi || index == farhu;

  double smallRadius(int index) => 1.7 + ((index * 37) % 10) / 7;

  HeartConstellation copyWith({
    Offset? center,
    double? scale,
    int? gap,
    bool clearGap = false,
    int? qalbi,
    int? farhu,
    bool? complete,
    bool? burst,
    bool? presence,
    double? dim,
    Set<int>? unlit,
    bool? gapGuide,
  }) {
    return HeartConstellation(
      center: center ?? this.center,
      scale: scale ?? this.scale,
      gap: clearGap ? null : (gap ?? this.gap),
      qalbi: qalbi ?? this.qalbi,
      farhu: farhu ?? this.farhu,
      complete: complete ?? this.complete,
      burst: burst ?? this.burst,
      presence: presence ?? this.presence,
      dim: dim ?? this.dim,
      unlit: unlit ?? this.unlit,
      gapGuide: gapGuide ?? this.gapGuide,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HeartConstellation &&
      other.center == center &&
      other.scale == scale &&
      other.gap == gap &&
      other.qalbi == qalbi &&
      other.farhu == farhu &&
      other.complete == complete &&
      other.burst == burst &&
      other.presence == presence &&
      other.dim == dim &&
      setEquals(other.unlit, unlit) &&
      other.gapGuide == gapGuide;

  @override
  int get hashCode => Object.hash(
    center,
    scale,
    gap,
    qalbi,
    farhu,
    complete,
    burst,
    presence,
    dim,
    Object.hashAllUnordered(unlit),
    gapGuide,
  );
}

@immutable
class SkyScene {
  const SkyScene({
    this.seed = 7,
    this.stars = 70,
    this.dayStars = 12,
    this.moon,
    this.sun = true,
    this.sunAt,
    this.clouds = defaultClouds,
    this.skyline,
    this.heart,
    this.shootingStar,
    this.haze = true,
    this.horizonGlow = false,
    this.twinkle = true,
    this.designWidth = 390,
  });

  static const List<SkyCloud> defaultClouds = [
    SkyCloud(318, 150, scale: 1, opacity: 0.85),
    SkyCloud(60, 250, scale: 0.7, opacity: 0.6),
    SkyCloud(352, 330, scale: 0.6, opacity: 0.5),
  ];

  static const SkyScene page = SkyScene(
    stars: 50,
    moon: Offset(250, 104),
    sun: false,
    clouds: [SkyCloud(300, 110, scale: 0.9, opacity: 0.85), SkyCloud(60, 230, scale: 0.6, opacity: 0.5)],
  );

  static const SkyScene home = SkyScene(
    moon: Offset(306, 134),
    sunAt: Offset(40, 420),
    skyline: 416,
    horizonGlow: true,
    heart: HeartConstellation(),
    shootingStar: SkyShootingStar(),
  );

  static const SkyScene full = SkyScene(
    stars: 90,
    moon: Offset(320, 96),
    clouds: [SkyCloud(320, 96, scale: 1, opacity: 0.8), SkyCloud(60, 760, scale: 0.8, opacity: 0.6)],
    sunAt: Offset(40, 820),
  );

  final int seed;
  final int stars;
  final int dayStars;
  final Offset? moon;
  final bool sun;
  final Offset? sunAt;
  final List<SkyCloud> clouds;
  final double? skyline;
  final HeartConstellation? heart;
  final SkyShootingStar? shootingStar;
  final bool haze;
  final bool horizonGlow;
  final bool twinkle;
  final double designWidth;

  double scaleFor(Size size) => size.width <= 0 ? 1 : size.width / designWidth;

  double designHeightFor(Size size) => size.height / scaleFor(size);

  SkyScene copyWith({
    int? seed,
    int? stars,
    int? dayStars,
    Offset? moon,
    bool clearMoon = false,
    bool? sun,
    Offset? sunAt,
    List<SkyCloud>? clouds,
    double? skyline,
    bool clearSkyline = false,
    HeartConstellation? heart,
    bool clearHeart = false,
    SkyShootingStar? shootingStar,
    bool clearShootingStar = false,
    bool? haze,
    bool? horizonGlow,
    bool? twinkle,
    double? designWidth,
  }) {
    return SkyScene(
      seed: seed ?? this.seed,
      stars: stars ?? this.stars,
      dayStars: dayStars ?? this.dayStars,
      moon: clearMoon ? null : (moon ?? this.moon),
      sun: sun ?? this.sun,
      sunAt: sunAt ?? this.sunAt,
      clouds: clouds ?? this.clouds,
      skyline: clearSkyline ? null : (skyline ?? this.skyline),
      heart: clearHeart ? null : (heart ?? this.heart),
      shootingStar: clearShootingStar ? null : (shootingStar ?? this.shootingStar),
      haze: haze ?? this.haze,
      horizonGlow: horizonGlow ?? this.horizonGlow,
      twinkle: twinkle ?? this.twinkle,
      designWidth: designWidth ?? this.designWidth,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SkyScene &&
      other.seed == seed &&
      other.stars == stars &&
      other.dayStars == dayStars &&
      other.moon == moon &&
      other.sun == sun &&
      other.sunAt == sunAt &&
      listEquals(other.clouds, clouds) &&
      other.skyline == skyline &&
      other.heart == heart &&
      other.shootingStar == shootingStar &&
      other.haze == haze &&
      other.horizonGlow == horizonGlow &&
      other.twinkle == twinkle &&
      other.designWidth == designWidth;

  @override
  int get hashCode => Object.hash(
    seed,
    stars,
    dayStars,
    moon,
    sun,
    sunAt,
    Object.hashAll(clouds),
    skyline,
    heart,
    shootingStar,
    haze,
    horizonGlow,
    twinkle,
    designWidth,
  );
}

@immutable
class SkyStar {
  const SkyStar(
    this.position,
    this.radius,
    this.color,
    this.opacity, {
    this.twinkles = false,
    this.phase = 0,
    this.period = 3,
  });

  final Offset position;
  final double radius;
  final Color color;
  final double opacity;
  final bool twinkles;
  final double phase;
  final double period;
}

@immutable
class SkySparkle {
  const SkySparkle(this.offset, this.radius);

  final Offset offset;
  final double radius;
}

@immutable
class SkyField {
  const SkyField({required this.stars, required this.sparkles});

  final List<SkyStar> stars;
  final List<SkySparkle> sparkles;

  static const Color _gold = Color(0xFFFFD98A);
  static const Color _white = Color(0xFFFFFFFF);

  static SkyField build(SkyScene scene, {required bool night, required double designHeight}) {
    final rnd = SkyRandom(scene.seed);
    final w = scene.designWidth;
    final h = designHeight;
    final stars = <SkyStar>[];
    if (night) {
      for (var i = 0; i < scene.stars; i++) {
        final x = rnd.next() * w;
        final y = rnd.next() * h * 0.92;
        final r = 0.4 + rnd.next() * 0.9;
        final color = rnd.next() > 0.8 ? _gold : _white;
        final opacity = 0.18 + rnd.next() * 0.5;
        final twinkles = scene.twinkle && i % 3 == 0;
        stars.add(
          SkyStar(
            Offset(x, y),
            r,
            color,
            opacity,
            twinkles: twinkles,
            phase: (i * 0.618) % 1 * math.pi * 2,
            period: 2.4 + (i * 37 % 19) / 10,
          ),
        );
      }
    } else {
      for (var i = 0; i < scene.dayStars; i++) {
        final x = rnd.next() * w;
        final y = 110 + rnd.next() * h * 0.6;
        stars.add(
          SkyStar(
            Offset(x, y),
            0.9,
            _white,
            0.55,
            twinkles: scene.twinkle && i.isEven,
            phase: (i * 0.618) % 1 * math.pi * 2,
            period: 2.8 + (i * 29 % 13) / 10,
          ),
        );
      }
    }
    final sparkles = <SkySparkle>[
      for (var k = 0; k < 9; k++)
        SkySparkle(Offset((rnd.next() - 0.5) * 120, (rnd.next() - 0.5) * 120), 0.8 + rnd.next() * 1.4),
    ];
    return SkyField(stars: stars, sparkles: sparkles);
  }
}
