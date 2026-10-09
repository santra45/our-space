import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'app_colors.dart';

abstract final class AppShadows {
  static double blurRadiusFromCss(double cssBlur) {
    if (cssBlur <= 0) return 0;
    return math.max(0, (cssBlur / 2 - 0.5) / 0.57735);
  }

  static BoxShadow css(
    Color color, {
    double x = 0,
    double y = 0,
    double blur = 0,
    double spread = 0,
  }) {
    return BoxShadow(
      color: color,
      offset: Offset(x, y),
      blurRadius: blurRadiusFromCss(blur),
      spreadRadius: spread,
    );
  }

  static List<BoxShadow> tinted(List<BoxShadow> geometry, Color color) {
    return [for (final s in geometry) s.copyWith(color: color)];
  }

  static const Color _black05 = Color(0x0D000000);
  static const Color _black10 = Color(0x1A000000);
  static const Color _black08 = Color(0x14000000);
  static const Color _black25 = Color(0x40000000);
  static const Color _pink20 = Color(0x33FFB6C1);
  static const Color _pink25 = Color(0x40FFB6C1);

  static const List<BoxShadow> none = [];

  static final List<BoxShadow> sm = [css(_black05, y: 1, blur: 2)];

  static final List<BoxShadow> base = [
    css(_black10, y: 1, blur: 3),
    css(_black10, y: 1, blur: 2, spread: -1),
  ];

  static final List<BoxShadow> md = [
    css(_black10, y: 4, blur: 6, spread: -1),
    css(_black10, y: 2, blur: 4, spread: -2),
  ];

  static final List<BoxShadow> lg = [
    css(_black10, y: 10, blur: 15, spread: -3),
    css(_black10, y: 4, blur: 6, spread: -4),
  ];

  static final List<BoxShadow> xl = [
    css(_black10, y: 20, blur: 25, spread: -5),
    css(_black10, y: 8, blur: 10, spread: -6),
  ];

  static final List<BoxShadow> x2l = [css(_black25, y: 25, blur: 50, spread: -12)];

  static final List<BoxShadow> cozy = [css(_pink25, y: 8, blur: 30)];

  static final List<BoxShadow> polaroid = [
    css(_black10, y: 10, blur: 25, spread: -5),
    css(_black08, y: 8, blur: 10, spread: -6),
  ];

  static final List<BoxShadow> glass = [css(_pink20, y: 8, blur: 32)];

  static final List<BoxShadow> glassPanel = [css(_pink25, y: 10, blur: 30, spread: -5)];

  static final List<BoxShadow> bottomNav = [css(_pink20, y: -8, blur: 25)];

  static final List<BoxShadow> primaryButton = tinted(md, AppColors.blush300.withValues(alpha: 0.4));

  static final List<BoxShadow> hairline = [css(const Color(0x05000000), y: 1, blur: 2)];
}
