import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

enum MoonPhaseName {
  newMoon('New moon'),
  waxingCrescent('Waxing crescent'),
  firstQuarter('First quarter'),
  waxingGibbous('Waxing gibbous'),
  fullMoon('Full moon'),
  waningGibbous('Waning gibbous'),
  lastQuarter('Last quarter'),
  waningCrescent('Waning crescent');

  const MoonPhaseName(this.label);

  final String label;
}

@immutable
class MoonPhase {
  const MoonPhase(this.age);

  factory MoonPhase.at(DateTime moment) {
    final days = moment.toUtc().difference(referenceNewMoon).inMicroseconds / Duration.microsecondsPerDay;
    final age = days % synodicMonth;
    return MoonPhase(age < 0 ? age + synodicMonth : age);
  }

  factory MoonPhase.tonight([DateTime? now]) {
    final t = now ?? DateTime.now();
    return MoonPhase.at(t.isUtc ? DateTime.utc(t.year, t.month, t.day, t.hour) : DateTime(t.year, t.month, t.day, t.hour));
  }

  static const double synodicMonth = 29.530588853;
  static final DateTime referenceNewMoon = DateTime.utc(2000, 1, 6, 18, 14);
  static const MoonPhase resting = MoonPhase(4.6);

  final double age;

  double get cycle => age / synodicMonth;

  double get illumination => (1 - math.cos(cycle * math.pi * 2)) / 2;

  bool get waxing => cycle < 0.5;

  double get daysFromNew => math.min(age, synodicMonth - age);

  double get daysFromFull => (age - synodicMonth / 2).abs();

  MoonPhaseName get phase => MoonPhaseName.values[((cycle * 8) + 0.5).floor() % 8];

  String get name => phase.label;

  bool get isNew => phase == MoonPhaseName.newMoon;

  Path litPath(double radius) {
    final path = Path();
    final light = illumination;
    if (light <= 0.001) return path;
    if (light >= 0.999) return path..addOval(Rect.fromCircle(center: Offset.zero, radius: radius));
    final k = math.cos(cycle * math.pi * 2);
    final reach = k.abs() * radius;
    path
      ..moveTo(0, -radius)
      ..arcTo(Rect.fromCircle(center: Offset.zero, radius: radius), -math.pi / 2, waxing ? math.pi : -math.pi, false);
    if (reach < 0.01) {
      path.lineTo(0, -radius);
    } else {
      path.arcTo(
        Rect.fromCenter(center: Offset.zero, width: reach * 2, height: radius * 2),
        math.pi / 2,
        (k > 0) == waxing ? -math.pi : math.pi,
        false,
      );
    }
    return path..close();
  }

  @override
  bool operator ==(Object other) => other is MoonPhase && other.age == age;

  @override
  int get hashCode => age.hashCode;

  @override
  String toString() => '$name (${age.toStringAsFixed(2)} days)';
}
