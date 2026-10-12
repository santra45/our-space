import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/theme/app_colors.dart';
import 'package:our_space_mobile/presentation/theme/app_gradients.dart';
import 'package:our_space_mobile/presentation/theme/app_metrics.dart';
import 'package:our_space_mobile/presentation/theme/app_motion.dart';
import 'package:our_space_mobile/presentation/theme/app_shadows.dart';
import 'package:our_space_mobile/presentation/theme/app_theme.dart';
import 'package:our_space_mobile/presentation/theme/app_typography.dart';

Map<String, int> _tailwindPalette() {
  final source = File('../tailwind.config.js').readAsStringSync();
  final colors = <String, int>{};
  final family = RegExp(r'(\w+):\s*\{([^{}]*)\}');
  final shade = RegExp(r"(\d+):\s*'#([0-9a-fA-F]{6})'");
  for (final f in family.allMatches(source)) {
    for (final s in shade.allMatches(f.group(2)!)) {
      colors['${f.group(1)}${s.group(1)}'] = 0xFF000000 | int.parse(s.group(2)!, radix: 16);
    }
  }
  return colors;
}

void main() {
  test('every custom colour in tailwind.config.js exists in AppColors with the same value', () {
    final palette = _tailwindPalette();
    final dart = <String, Color>{
      'blush50': AppColors.blush50,
      'blush100': AppColors.blush100,
      'blush200': AppColors.blush200,
      'blush300': AppColors.blush300,
      'blush400': AppColors.blush400,
      'blush500': AppColors.blush500,
      'blush600': AppColors.blush600,
      'cream50': AppColors.cream50,
      'cream100': AppColors.cream100,
      'cream200': AppColors.cream200,
      'cream300': AppColors.cream300,
      'lavender50': AppColors.lavender50,
      'lavender100': AppColors.lavender100,
      'lavender200': AppColors.lavender200,
      'lavender300': AppColors.lavender300,
      'lavender400': AppColors.lavender400,
      'lavender500': AppColors.lavender500,
      'lavender600': AppColors.lavender600,
      'lavender700': AppColors.lavender700,
      'matcha50': AppColors.matcha50,
      'matcha100': AppColors.matcha100,
      'matcha200': AppColors.matcha200,
      'matcha300': AppColors.matcha300,
      'caramel100': AppColors.caramel100,
      'caramel200': AppColors.caramel200,
      'caramel400': AppColors.caramel400,
    };
    expect(palette.length, dart.length);
    for (final entry in palette.entries) {
      expect(dart[entry.key]?.toARGB32(), entry.value, reason: entry.key);
    }
  });

  test('default Tailwind colours used by the web match the v3 palette', () {
    expect(AppColors.slate800.toARGB32(), 0xFF1E293B);
    expect(AppColors.slate400.toARGB32(), 0xFF94A3B8);
    expect(AppColors.rose500.toARGB32(), 0xFFF43F5E);
    expect(AppColors.amber500.toARGB32(), 0xFFF59E0B);
    expect(AppColors.emerald500.toARGB32(), 0xFF10B981);
    expect(AppColors.indigo600.toARGB32(), 0xFF4F46E5);
    expect(AppColors.placeholder.toARGB32(), 0xFF9CA3AF);
  });

  test('type scale matches Tailwind sizes and line heights', () {
    void check(TextStyle s, double size, double lineHeight) {
      expect(s.fontSize, size);
      expect(s.fontSize! * s.height!, closeTo(lineHeight, 0.001));
      expect(s.leadingDistribution, TextLeadingDistribution.even);
    }

    check(Tw.px10, 10, 15);
    check(Tw.px11, 11, 16.5);
    check(Tw.xs, 12, 16);
    check(Tw.sm, 14, 20);
    check(Tw.base, 16, 24);
    check(Tw.lg, 18, 28);
    check(Tw.xl, 20, 28);
    check(Tw.x2l, 24, 32);
    check(Tw.x3l, 30, 36);
    check(Tw.x6l, 60, 60);
  });

  test('text style helpers follow Tailwind weights, leading and tracking', () {
    expect(Tw.xs.semibold.fontWeight, FontWeight.w600);
    expect(Tw.xs.extrabold.fontWeight, FontWeight.w800);
    expect(Tw.xl.snug.height, 1.375);
    expect(Tw.xl.relaxed.height, 1.625);
    expect(Tw.xl.trackingTight.letterSpacing, closeTo(-0.5, 1e-9));
    expect(Tw.xs.trackingWidest.letterSpacing, closeTo(1.2, 1e-9));
    expect(Tw.xl.handwriting.fontFamily, 'Caveat');
    expect(Tw.xl.handwriting.fontFamilyFallback, contains('CaveatLatinExt'));
    expect(Tw.xs.c(AppColors.blush600).color, AppColors.blush600);
  });

  test('CSS blur radii convert to the same Gaussian sigma in Flutter', () {
    for (final blur in [2.0, 4.0, 10.0, 25.0, 30.0, 50.0]) {
      final radius = AppShadows.blurRadiusFromCss(blur);
      expect(Shadow.convertRadiusToSigma(radius), closeTo(blur / 2, 1e-3), reason: '$blur');
    }
    expect(AppShadows.blurRadiusFromCss(0), 0);
  });

  test('named shadows keep the web geometry', () {
    final glass = AppShadows.glassPanel.single;
    expect(glass.offset, const Offset(0, 10));
    expect(glass.spreadRadius, -5);
    expect(glass.color, const Color(0x40FFB6C1));
    expect(AppShadows.md.length, 2);
    expect(AppShadows.primaryButton.first.color, AppColors.blush300.withValues(alpha: 0.4));
    expect(AppShadows.bottomNav.single.offset, const Offset(0, -8));
  });

  test('corner gradients follow the CSS angle rules', () {
    final square = AppGradients.headerLogo.endpoints(const Rect.fromLTWH(0, 0, 32, 32));
    expect(square.$1.dx, closeTo(0, 1e-9));
    expect(square.$1.dy, closeTo(32, 1e-9));
    expect(square.$2.dx, closeTo(32, 1e-9));
    expect(square.$2.dy, closeTo(0, 1e-9));

    expect(AppGradients.angleDegrees(AppGradients.headerLogo, const Size(32, 32)), closeTo(45, 1e-9));
    expect(AppGradients.angleDegrees(AppGradients.scratchCard, const Size(400, 300)), closeTo(36.869898, 1e-5));

    final vertical = AppGradients.body.endpoints(const Rect.fromLTWH(0, 0, 100, 500));
    expect(vertical.$1, const Offset(50, 0));
    expect(vertical.$2, const Offset(50, 500));
    expect(AppGradients.body.colors, [AppColors.blush50, AppColors.cream50, AppColors.lavender50]);
  });

  test('radii and layout constants mirror the web utilities', () {
    expect(AppRadii.x2l, 16);
    expect(AppRadii.x3l, 24);
    expect(AppRadii.x4l, 32);
    expect(TwSpace.of(3.5), 14);
    expect(AppLayout.maxWidthMd, 448);
    expect(AppLayout.maxWidthSm, 384);
  });

  test('spring curve settles at 1 and overshoots like an underdamped framer spring', () {
    final curve = SpringCurve(stiffness: 350, damping: 20);
    expect(curve.transform(0), 0);
    expect(curve.transform(1), 1);
    final peak = [for (var i = 1; i < 100; i++) curve.transform(i / 100)].reduce((a, b) => a > b ? a : b);
    expect(peak, greaterThan(1));
    expect(curve.duration, greaterThan(Duration.zero));
  });

  test('light theme uses the web selection colours and no ink splashes', () {
    final theme = AppTheme.lightTheme;
    expect(theme.textSelectionTheme.selectionColor, AppColors.blush200);
    expect(theme.textSelectionTheme.cursorColor, AppColors.slate800);
    expect(theme.splashFactory, NoSplash.splashFactory);
    expect(theme.colorScheme.primary, AppColors.blush500);
    expect(theme.textTheme.bodyMedium?.color, AppColors.slate800);
    expect(theme.textTheme.bodyMedium?.fontSize, 16);
  });
}
