import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

class SpringCurve extends Curve {
  SpringCurve({required double stiffness, required double damping, double mass = 1})
    : description = SpringDescription(mass: mass, stiffness: stiffness, damping: damping) {
    final simulation = _simulation();
    var t = 0.0;
    const step = 1 / 240;
    while (t < 10 && !simulation.isDone(t)) {
      t += step;
    }
    _seconds = t <= 0 ? step : t;
  }

  final SpringDescription description;
  late final double _seconds;

  SpringSimulation _simulation() => SpringSimulation(
    description,
    0,
    1,
    0,
    tolerance: const Tolerance(distance: 0.001, velocity: 0.01),
  );

  Duration get duration => Duration(microseconds: (_seconds * 1000000).round());

  @override
  double transformInternal(double t) => _simulation().x(t * _seconds);
}

abstract final class AppMotion {
  static const Duration tabSwitch = Duration(milliseconds: 220);
  static const Curve tabCurve = Curves.easeOut;
  static const double tabOffset = 12;

  static const Duration framerTween = Duration(milliseconds: 300);
  static const Curve framerEase = Cubic(0.25, 0.1, 0.35, 1);

  static const Duration modalExit = Duration(milliseconds: 150);

  static const Duration sheetEnter = Duration(milliseconds: 300);

  static const SpringDescription buttonSpring = SpringDescription(mass: 1, stiffness: 400, damping: 17);
  static const SpringDescription navPillSpring = SpringDescription(mass: 1, stiffness: 450, damping: 30);
  static const SpringDescription navIconSpring = SpringDescription(mass: 1, stiffness: 350, damping: 20);
  static const SpringDescription framerPositionSpring = SpringDescription(mass: 1, stiffness: 500, damping: 25);
  static const SpringDescription framerScaleSpring = SpringDescription(mass: 1, stiffness: 550, damping: 30);
  static const SpringDescription letterSpring = SpringDescription(mass: 1, stiffness: 350, damping: 25);
  static const SpringDescription progressSpring = SpringDescription(mass: 1, stiffness: 100, damping: 15);

  static const Duration pulse = Duration(seconds: 2);
  static const Curve pulseCurve = Cubic(0.4, 0, 0.6, 1);
  static const Duration ping = Duration(seconds: 1);
  static const Curve pingCurve = Cubic(0, 0, 0.2, 1);
  static const Duration bounce = Duration(seconds: 1);
  static const Duration spin = Duration(seconds: 1);

  static const Duration toast = Duration(milliseconds: 4000);

  static double springValue(SpringDescription spring, double from, double to, double seconds) {
    return SpringSimulation(spring, from, to, 0).x(seconds);
  }
}
