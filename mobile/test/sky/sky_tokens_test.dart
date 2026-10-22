import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/theme/app_colors.dart';

void main() {
  group('tokens', () {
    test('night tokens match sky.css', () {
      const t = SkyTokens.night;
      expect(t.mode, SkyMode.night);
      expect(t.skyTop, const Color(0xFF0B0B2B));
      expect(t.skyMid, const Color(0xFF1A1650));
      expect(t.skyLow, const Color(0xFF3A1D4F));
      expect(t.page, const Color(0xFF0E0D2C));
      expect(t.surface, const Color(0xFF141238));
      expect(t.surface2, const Color(0xFF1C1A45));
      expect(t.star, const Color(0xFFFFD98A));
      expect(t.gold, const Color(0xFFFFD98A));
      expect(t.rose, const Color(0xFFFF6B95));
      expect(t.roseDeep, const Color(0xFFE24E79));
      expect(t.text, const Color(0xFFF3F0FF));
      expect(t.muted, const Color(0xFFA9A3D1));
      expect(t.activeBg, const Color(0xFFFFD98A));
      expect(t.activeFg, const Color(0xFF1B1838));
      expect(t.line.a, closeTo(0.42, 0.01));
      expect(t.chip.a, closeTo(0.72, 0.01));
      expect(t.statusBar.statusBarIconBrightness, Brightness.light);
    });

    test('day tokens match sky.css', () {
      const t = SkyTokens.day;
      expect(t.mode, SkyMode.day);
      expect(t.skyTop, const Color(0xFF8FC3FF));
      expect(t.skyMid, const Color(0xFFC9E0FF));
      expect(t.skyLow, const Color(0xFFFFE1CC));
      expect(t.page, const Color(0xFFF4F6FF));
      expect(t.surface, const Color(0xFFFFFFFF));
      expect(t.title, SkyTokens.indigo);
      expect(t.activeBg, SkyTokens.indigo);
      expect(t.gold, const Color(0xFFE8B04B));
      expect(t.rose, const Color(0xFFFF6B95));
      expect(t.text, const Color(0xFF1E1B3A));
      expect(t.muted, const Color(0xFF6B6890));
      expect(t.star, const Color(0xFFFFFFFF));
      expect(t.statusBar.statusBarIconBrightness, Brightness.dark);
    });

    test('of picks the set and copyWith switches mode', () {
      expect(SkyTokens.of(SkyMode.day), same(SkyTokens.day));
      expect(SkyTokens.of(SkyMode.night), same(SkyTokens.night));
      expect(SkyTokens.night.copyWith(mode: SkyMode.day), same(SkyTokens.day));
      expect(SkyTokens.night.copyWith(), same(SkyTokens.night));
    });

    test('lerp blends colours and flips the mode half way', () {
      final mid = SkyTokens.night.lerp(SkyTokens.day, 0.5);
      expect(mid.page, Color.lerp(SkyTokens.night.page, SkyTokens.day.page, 0.5));
      expect(mid.mode, SkyMode.day);
      expect(SkyTokens.night.lerp(SkyTokens.day, 0.4).mode, SkyMode.night);
      expect(SkyTokens.night.lerp(SkyTokens.day, 0), same(SkyTokens.night));
      expect(SkyTokens.night.lerp(SkyTokens.day, 1), same(SkyTokens.day));
      expect(mid.skylineOpacity, closeTo((0.96 + 0.55) / 2, 1e-9));
    });

    test('gradients follow the css stops', () {
      expect(SkyTokens.night.skyGradient.colors, [
        SkyTokens.night.skyTop,
        SkyTokens.night.skyMid,
        SkyTokens.night.skyLow,
      ]);
      expect(SkyTokens.night.skyGradient.stops, [0, 0.55, 1]);
      expect(SkyTokens.day.primaryGradient.colors.first, SkyTokens.roseDark);
      expect(SkyTokens.day.progressGradient.colors, [SkyTokens.day.gold, SkyTokens.day.rose]);
    });
  });

  group('typography', () {
    test('headlines are Bodoni Moda italic and body is DM Sans', () {
      expect(SkyType.display.fontFamily, SkyFonts.serif);
      expect(SkyType.display.fontStyle, FontStyle.italic);
      expect(SkyType.display.fontSize, 35);
      expect(SkyType.title.fontSize, 28);
      expect(SkyType.body.fontFamily, SkyFonts.sans);
      expect(SkyType.body.fontStyle, isNot(FontStyle.italic));
      expect(SkyType.handCaption.fontFamily, SkyFonts.hand);
      expect(SkyType.handCaption.fontFamilyFallback, contains('CaveatLatinExt'));
    });

    test('labels are small caps with wide tracking', () {
      expect(SkyType.kicker.fontSize, 10.5);
      expect(SkyType.kicker.letterSpacing, closeTo(10.5 * 0.22, 1e-9));
      expect(SkyType.label.fontWeight, FontWeight.w700);
      expect(SkyType.label.letterSpacing, closeTo(2, 1e-9));
    });

    test('variable fonts get weight and optical size axes', () {
      final serif = SkyType.serif(35, weight: FontWeight.w500);
      expect(serif.fontVariations, contains(const FontVariation('wght', 500)));
      expect(serif.fontVariations, contains(const FontVariation('opsz', 35)));
      final tiny = SkyType.sans(6);
      expect(tiny.fontVariations, contains(const FontVariation('opsz', 9)));
      final huge = SkyType.serif(120);
      expect(huge.fontVariations, contains(const FontVariation('opsz', 96)));
    });

    test('coloured typography follows the tokens and is cached', () {
      final night = SkyTypography.of(SkyTokens.night);
      expect(night.display.color, SkyTokens.night.title);
      expect(night.kicker.color, SkyTokens.night.kicker);
      expect(night.body.color, SkyTokens.night.text);
      expect(SkyTypography.of(SkyTokens.night), same(night));
      expect(SkyTypography.of(SkyTokens.day).display.color, SkyTokens.indigo);
    });
  });

  group('themes', () {
    test('the legacy theme keeps the old look and carries the tokens', () {
      final theme = SkyThemes.legacy(SkyTokens.night);
      expect(theme.colorScheme.primary, AppColors.blush500);
      expect(theme.extension<SkyTokens>(), same(SkyTokens.night));
      expect(SkyThemes.legacy(SkyTokens.night), same(theme));
    });

    test('the sky material theme is dark at night and light by day', () {
      final night = SkyThemes.material(SkyTokens.night);
      final day = SkyThemes.material(SkyTokens.day);
      expect(night.brightness, Brightness.dark);
      expect(day.brightness, Brightness.light);
      expect(night.scaffoldBackgroundColor, SkyTokens.night.page);
      expect(night.colorScheme.onSurface, SkyTokens.night.text);
      expect(day.colorScheme.primary, SkyTokens.day.rose);
      expect(night.textTheme.bodyMedium?.fontFamily, SkyFonts.sans);
      expect(night.textTheme.displayMedium?.fontFamily, SkyFonts.serif);
      expect(night.splashFactory, NoSplash.splashFactory);
      expect(night.extension<SkyTokens>(), same(SkyTokens.night));
    });

    testWidgets('context.sky falls back to night and SkyTheme applies the sky material theme', (tester) async {
      late SkyTokens outside;
      late ThemeData inside;
      late TextStyle style;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(),
          home: Builder(
            builder: (context) {
              outside = context.sky;
              return Theme(
                data: SkyThemes.legacy(SkyTokens.day),
                child: SkyTheme(
                  child: Builder(
                    builder: (context) {
                      inside = Theme.of(context);
                      style = DefaultTextStyle.of(context).style;
                      return const SizedBox();
                    },
                  ),
                ),
              );
            },
          ),
        ),
      );
      expect(outside, same(SkyTokens.night));
      expect(inside.brightness, Brightness.light);
      expect(inside.extension<SkyTokens>()?.mode, SkyMode.day);
      expect(style.fontFamily, SkyFonts.sans);
      expect(style.color, SkyTokens.day.text);
      expect(style.decoration, TextDecoration.none);
    });
  });

  test('metrics follow sky.css', () {
    expect(SkyRadii.card, 22);
    expect(SkyRadii.sheet, 32);
    expect(SkySizes.dockHeight, 62);
    expect(SkySizes.iconButton, 42);
    expect(SkySizes.button, 48);
    expect(SkySpace.gutter, 18);
    expect(SkyMotion.pressScale, 0.96);
    expect(SkyMotion.staggerDelay(3), const Duration(milliseconds: 135));
    expect(SkyMotion.staggerDelay(99), SkyMotion.staggerStep * SkyMotion.staggerCap);
    expect(SystemUiOverlayStyle.light.statusBarIconBrightness, Brightness.light);
  });
}
