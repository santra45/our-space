import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

@immutable
class ConstellationLabel {
  const ConstellationLabel(this.offset, {this.alignment = Alignment.topCenter});

  final Offset offset;
  final Alignment alignment;

  Rect area(Offset star, Size size) {
    final left = star.dx + offset.dx - (alignment.x + 1) / 2 * size.width;
    final top = star.dy + offset.dy - (alignment.y + 1) / 2 * size.height;
    return Rect.fromLTWH(left, top - 2, size.width, size.height);
  }

  @override
  bool operator ==(Object other) =>
      other is ConstellationLabel && other.offset == offset && other.alignment == alignment;

  @override
  int get hashCode => Object.hash(offset, alignment);
}

enum ConstellationShape {
  heart(
    title: 'The Heart',
    me: 24,
    partner: 5,
    meLabel: ConstellationLabel(Offset(0, 18)),
    partnerLabel: ConstellationLabel(Offset(-12, 30)),
  ),
  moon(
    title: 'The Moon',
    me: 0,
    partner: 18,
    meLabel: ConstellationLabel(Offset(16, 0), alignment: Alignment.centerLeft),
    partnerLabel: ConstellationLabel(Offset(30, 0), alignment: Alignment.centerLeft),
  ),
  infinity(
    title: 'Infinity',
    me: 25,
    partner: 11,
    meLabel: ConstellationLabel(Offset(0, 18)),
    partnerLabel: ConstellationLabel(Offset(-4, 30)),
  ),
  star(
    title: 'The Star',
    me: 23,
    partner: 6,
    meLabel: ConstellationLabel(Offset(0, -16), alignment: Alignment.bottomCenter),
    partnerLabel: ConstellationLabel(Offset(0, -30), alignment: Alignment.bottomCenter),
  );

  const ConstellationShape({
    required this.title,
    required this.me,
    required this.partner,
    required this.meLabel,
    required this.partnerLabel,
  });

  static const int count = 29;

  final String title;
  final int me;
  final int partner;
  final ConstellationLabel meLabel;
  final ConstellationLabel partnerLabel;

  static ConstellationShape at(int index) => values[index % values.length];

  List<Offset> get unit => _units[index];

  List<int> get order => _orders[index];

  Rect get unitBounds => _bounds[index];

  static final List<List<Offset>> _units = [
    for (final shape in values)
      List<Offset>.unmodifiable(switch (shape) {
        ConstellationShape.heart => _heart(),
        ConstellationShape.moon => _moon(),
        ConstellationShape.infinity => _infinity(),
        ConstellationShape.star => _star(),
      }),
  ];

  static final List<List<int>> _orders = [
    for (final shape in values)
      List<int>.unmodifiable(switch (shape) {
        ConstellationShape.heart => const [
          24, 5, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 25, 26, 27, 28, 0, 1, 2, 3, 4, 6, 7, 8, 9, 10,
        ],
        ConstellationShape.moon => _stroke(shape, 1),
        ConstellationShape.infinity => _stroke(shape, 0),
        ConstellationShape.star => _stroke(shape, 0),
      }),
  ];

  static final List<Rect> _bounds = [
    for (final points in _units)
      Rect.fromLTRB(
        points.map((p) => p.dx).reduce(math.min),
        points.map((p) => p.dy).reduce(math.min),
        points.map((p) => p.dx).reduce(math.max),
        points.map((p) => p.dy).reduce(math.max),
      ),
  ];

  static List<int> _stroke(ConstellationShape shape, int start) => [
    shape.me,
    shape.partner,
    for (var i = 0; i < count; i++)
      if ((start + i) % count != shape.me && (start + i) % count != shape.partner) (start + i) % count,
  ];

  static Offset heartAt(double t) {
    final s = math.sin(t);
    return Offset(16 * s * s * s, -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)));
  }

  static List<Offset> _heart() => [for (var i = 0; i < count; i++) heartAt(i / count * math.pi * 2)];

  static List<Offset> _moon() {
    const outer = 14.5;
    const inner = 12.0;
    const shift = 7.0;
    const x = (outer * outer - inner * inner + shift * shift) / (2 * shift);
    final y = math.sqrt(outer * outer - x * x);
    final top = math.atan2(-y, x);
    final bottom = math.atan2(y, x);
    final innerTop = math.atan2(-y, x - shift);
    final innerBottom = math.atan2(y, x - shift);
    final innerEnd = innerTop > innerBottom ? innerTop : innerTop + math.pi * 2;
    final rim = _arc(Offset.zero, outer, top, bottom - math.pi * 2);
    final hollow = _arc(const Offset(shift, 0), inner, innerBottom, innerEnd);
    final points = [..._spread(rim, 18), ..._spread(hollow, count - 18)];
    return _place(points, angle: -28 * math.pi / 180, shift: const Offset(-1.2, 2.5));
  }

  static List<Offset> _infinity() {
    const reach = 18.5;
    const lift = 1.75;
    const steps = 2400;
    final path = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = math.pi / 2 - math.pi * 2 * i / steps;
      final d = 1 + math.sin(t) * math.sin(t);
      path.add(Offset(reach * math.cos(t) / d, lift * reach * math.sin(t) * math.cos(t) / d));
    }
    return _place(_spread(path, count), shift: const Offset(0, 3));
  }

  static List<Offset> _star() {
    const outer = 16.5;
    const inner = outer * 0.382;
    final corners = [
      for (var k = 0; k < 10; k++)
        Offset.fromDirection(-math.pi / 2 + k * math.pi / 5, k.isEven ? outer : inner),
    ];
    final points = <Offset>[];
    for (var k = 0; k < 10; k++) {
      final a = corners[k];
      final b = corners[(k + 1) % 10];
      final steps = k == 5 ? 2 : 3;
      for (var j = 0; j < steps; j++) {
        points.add(Offset.lerp(a, b, j / steps)!);
      }
    }
    return _place(points, shift: const Offset(0, 3.5));
  }

  static List<Offset> _arc(Offset center, double radius, double from, double to, {int steps = 600}) => [
    for (var i = 0; i <= steps; i++) center + Offset.fromDirection(from + (to - from) * i / steps, radius),
  ];

  static List<Offset> _spread(List<Offset> path, int n) {
    final lengths = <double>[0];
    for (var i = 1; i < path.length; i++) {
      lengths.add(lengths.last + (path[i] - path[i - 1]).distance);
    }
    final total = lengths.last;
    final out = <Offset>[];
    var k = 1;
    for (var j = 0; j < n; j++) {
      final d = total * j / n;
      while (k < path.length - 1 && lengths[k] < d) {
        k++;
      }
      final span = lengths[k] - lengths[k - 1];
      final u = span == 0 ? 0.0 : (d - lengths[k - 1]) / span;
      out.add(Offset.lerp(path[k - 1], path[k], u)!);
    }
    return out;
  }

  static List<Offset> _place(List<Offset> points, {double angle = 0, Offset shift = Offset.zero}) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return [for (final p in points) Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c) + shift];
  }
}

@immutable
class SkyConstellation {
  const SkyConstellation({
    this.shape = ConstellationShape.heart,
    this.center = const Offset(195, 284),
    this.scale = 6.4,
    this.gap = 10,
    this.complete = false,
    this.burst = false,
    this.presence = true,
    this.dim = 1,
    this.unlit = const <int>{},
    this.gapGuide = true,
  });

  static const int count = ConstellationShape.count;
  static const double hitRadius = 24;

  final ConstellationShape shape;
  final Offset center;
  final double scale;
  final int? gap;
  final bool complete;
  final bool burst;
  final bool presence;
  final double dim;
  final Set<int> unlit;
  final bool gapGuide;

  int get me => shape.me;

  int get partner => shape.partner;

  Offset pointAt(int index) => center + shape.unit[index % count] * scale;

  List<Offset> get points => [for (var i = 0; i < count; i++) pointAt(i)];

  Rect get bounds => Rect.fromPoints(
    center + shape.unitBounds.topLeft * scale,
    center + shape.unitBounds.bottomRight * scale,
  );

  bool get hasOpenGap => gap != null && !complete;

  bool isLit(int index) => !unlit.contains(index) && !(hasOpenGap && index == gap);

  bool isBig(int index) => index == me || index == partner;

  double smallRadius(int index) => 1.7 + ((index * 37) % 10) / 7;

  Iterable<int> get litPoints sync* {
    for (var i = 0; i < count; i++) {
      if (isLit(i)) yield i;
    }
  }

  int? starAt(Offset point, {double radius = hitRadius}) {
    int? best;
    var bestDistance = radius;
    for (final i in litPoints) {
      final distance = (pointAt(i) - point).distance;
      if (distance <= bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  SkyConstellation fitted(Rect box, {double margin = 0}) {
    final unit = shape.unitBounds;
    final room = box.deflate(margin);
    final k = math.max(0.0, math.min(room.width / unit.width, room.height / unit.height));
    return copyWith(center: room.center - unit.center * k, scale: k);
  }

  SkyConstellation copyWith({
    ConstellationShape? shape,
    Offset? center,
    double? scale,
    int? gap,
    bool clearGap = false,
    bool? complete,
    bool? burst,
    bool? presence,
    double? dim,
    Set<int>? unlit,
    bool? gapGuide,
  }) {
    return SkyConstellation(
      shape: shape ?? this.shape,
      center: center ?? this.center,
      scale: scale ?? this.scale,
      gap: clearGap ? null : (gap ?? this.gap),
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
      other is SkyConstellation &&
      other.shape == shape &&
      other.center == center &&
      other.scale == scale &&
      other.gap == gap &&
      other.complete == complete &&
      other.burst == burst &&
      other.presence == presence &&
      other.dim == dim &&
      setEquals(other.unlit, unlit) &&
      other.gapGuide == gapGuide;

  @override
  int get hashCode => Object.hash(
    shape,
    center,
    scale,
    gap,
    complete,
    burst,
    presence,
    dim,
    Object.hashAllUnordered(unlit),
    gapGuide,
  );
}
