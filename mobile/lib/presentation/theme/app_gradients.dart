import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'app_colors.dart';

enum TwDirection { toT, toTr, toR, toBr, toB, toBl, toL, toTl }

class TwGradient extends Gradient {
  const TwGradient(
    this.direction, {
    required super.colors,
    super.stops,
    super.transform,
  });

  factory TwGradient.fromTo(TwDirection direction, Color from, Color to) {
    return TwGradient(direction, colors: [from, to]);
  }

  factory TwGradient.fromViaTo(TwDirection direction, Color from, Color via, Color to) {
    return TwGradient(direction, colors: [from, via, to]);
  }

  final TwDirection direction;

  Offset _unit(Size size) {
    final w = size.width;
    final h = size.height;
    Offset v;
    switch (direction) {
      case TwDirection.toT:
        v = const Offset(0, -1);
      case TwDirection.toR:
        v = const Offset(1, 0);
      case TwDirection.toB:
        v = const Offset(0, 1);
      case TwDirection.toL:
        v = const Offset(-1, 0);
      case TwDirection.toTr:
        v = Offset(h, -w);
      case TwDirection.toBr:
        v = Offset(h, w);
      case TwDirection.toBl:
        v = Offset(-h, w);
      case TwDirection.toTl:
        v = Offset(-h, -w);
    }
    final length = v.distance;
    if (length == 0) return const Offset(0, 1);
    return v / length;
  }

  (Offset, Offset) endpoints(Rect rect) {
    final dir = _unit(rect.size);
    final length = (rect.width * dir.dx).abs() + (rect.height * dir.dy).abs();
    final half = dir * (length / 2);
    return (rect.center - half, rect.center + half);
  }

  List<double> _resolvedStops() {
    if (stops != null) return stops!;
    if (colors.length == 1) return const [0.0];
    final step = 1.0 / (colors.length - 1);
    return [for (var i = 0; i < colors.length; i++) i * step];
  }

  @override
  Shader createShader(Rect rect, {TextDirection? textDirection}) {
    final (start, end) = endpoints(rect);
    return ui.Gradient.linear(
      start,
      end,
      colors,
      _resolvedStops(),
      TileMode.clamp,
      transform?.transform(rect, textDirection: textDirection)?.storage,
    );
  }

  @override
  TwGradient scale(double factor) {
    return TwGradient(
      direction,
      colors: [for (final c in colors) Color.lerp(null, c, factor)!],
      stops: stops,
      transform: transform,
    );
  }

  @override
  TwGradient withOpacity(double opacity) {
    return TwGradient(
      direction,
      colors: [for (final c in colors) c.withValues(alpha: c.a * opacity)],
      stops: stops,
      transform: transform,
    );
  }

  @override
  Gradient? lerpFrom(Gradient? a, double t) {
    if (a is TwGradient && a.direction == direction && a.colors.length == colors.length) {
      return TwGradient(
        direction,
        colors: [for (var i = 0; i < colors.length; i++) Color.lerp(a.colors[i], colors[i], t)!],
        stops: stops,
        transform: transform,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  Gradient? lerpTo(Gradient? b, double t) {
    if (b is TwGradient && b.direction == direction && b.colors.length == colors.length) {
      return TwGradient(
        direction,
        colors: [for (var i = 0; i < colors.length; i++) Color.lerp(colors[i], b.colors[i], t)!],
        stops: stops,
        transform: transform,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TwGradient &&
        other.direction == direction &&
        _listEquals(other.colors, colors) &&
        _listEquals(other.stops, stops) &&
        other.transform == transform;
  }

  @override
  int get hashCode => Object.hash(direction, Object.hashAll(colors), stops == null ? null : Object.hashAll(stops!), transform);

  static bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

abstract final class AppGradients {
  static const TwGradient body = TwGradient(
    TwDirection.toB,
    colors: [AppColors.blush50, AppColors.cream50, AppColors.lavender50],
  );

  static const TwGradient buttonPrimary = TwGradient(
    TwDirection.toR,
    colors: [AppColors.blush400, AppColors.blush500],
  );

  static const TwGradient buttonMatcha = TwGradient(
    TwDirection.toR,
    colors: [AppColors.matcha200, AppColors.matcha300],
  );

  static const TwGradient buttonLavender = TwGradient(
    TwDirection.toR,
    colors: [AppColors.lavender200, AppColors.lavender300],
  );

  static const TwGradient headerLogo = TwGradient(
    TwDirection.toTr,
    colors: [AppColors.blush400, AppColors.blush300],
  );

  static const TwGradient lockHeart = TwGradient(
    TwDirection.toTr,
    colors: [AppColors.blush300, AppColors.blush200, AppColors.lavender200],
  );

  static const TwGradient progress = TwGradient(
    TwDirection.toR,
    colors: [AppColors.blush400, AppColors.blush500],
  );

  static const TwGradient scratchCard = TwGradient(
    TwDirection.toTr,
    colors: [AppColors.blush100, AppColors.white, AppColors.lavender100],
  );

  static const TwGradient envelope = TwGradient(
    TwDirection.toTr,
    colors: [AppColors.cream100, AppColors.blush100],
  );

  static Shader scratchCoatingShader(Size size) {
    return ui.Gradient.linear(
      Offset.zero,
      Offset(size.width, size.height),
      const [AppColors.blush200, AppColors.blush100, AppColors.lavender300],
      const [0, 0.5, 1],
    );
  }

  static double angleDegrees(TwGradient gradient, Size size) {
    final (start, end) = gradient.endpoints(Offset.zero & size);
    final d = end - start;
    final deg = math.atan2(d.dx, -d.dy) * 180 / math.pi;
    return deg < 0 ? deg + 360 : deg;
  }
}
