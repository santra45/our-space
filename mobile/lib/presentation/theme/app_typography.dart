import 'package:flutter/painting.dart';

abstract final class AppFonts {
  static const String handwriting = 'Caveat';
  static const List<String> handwritingFallback = ['CaveatLatinExt', 'cursive', 'sans-serif'];
  static const String mono = 'monospace';
  static const List<String> monoFallback = ['Roboto Mono', 'Droid Sans Mono', 'Courier New'];
}

abstract final class Tw {
  static const double defaultLineHeight = 1.5;

  static TextStyle size(double fontSize, {double? lineHeight}) {
    return TextStyle(
      fontSize: fontSize,
      height: (lineHeight ?? fontSize * defaultLineHeight) / fontSize,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  static final TextStyle px9 = size(9);
  static final TextStyle px10 = size(10);
  static final TextStyle px11 = size(11);
  static final TextStyle xs = size(12, lineHeight: 16);
  static final TextStyle sm = size(14, lineHeight: 20);
  static final TextStyle base = size(16, lineHeight: 24);
  static final TextStyle lg = size(18, lineHeight: 28);
  static final TextStyle xl = size(20, lineHeight: 28);
  static final TextStyle x2l = size(24, lineHeight: 32);
  static final TextStyle x3l = size(30, lineHeight: 36);
  static final TextStyle x6l = size(60, lineHeight: 60);
}

extension TwTextStyle on TextStyle {
  double get _size => fontSize ?? 16;

  TextStyle get normal => copyWith(fontWeight: FontWeight.w400);
  TextStyle get medium => copyWith(fontWeight: FontWeight.w500);
  TextStyle get semibold => copyWith(fontWeight: FontWeight.w600);
  TextStyle get bold => copyWith(fontWeight: FontWeight.w700);
  TextStyle get extrabold => copyWith(fontWeight: FontWeight.w800);
  TextStyle get black => copyWith(fontWeight: FontWeight.w900);

  TextStyle c(Color color) => copyWith(color: color);

  TextStyle get leadingNone => copyWith(height: 1);
  TextStyle get tight => copyWith(height: 1.25);
  TextStyle get snug => copyWith(height: 1.375);
  TextStyle get leadingNormal => copyWith(height: 1.5);
  TextStyle get relaxed => copyWith(height: 1.625);
  TextStyle leading(double pixels) => copyWith(height: pixels / _size);

  TextStyle get trackingTight => copyWith(letterSpacing: -0.025 * _size);
  TextStyle get trackingWide => copyWith(letterSpacing: 0.025 * _size);
  TextStyle get trackingWider => copyWith(letterSpacing: 0.05 * _size);
  TextStyle get trackingWidest => copyWith(letterSpacing: 0.1 * _size);

  TextStyle get handwriting => copyWith(
    fontFamily: AppFonts.handwriting,
    fontFamilyFallback: AppFonts.handwritingFallback,
  );

  TextStyle get mono => copyWith(fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback);

  TextStyle get italic => copyWith(fontStyle: FontStyle.italic);
  TextStyle get underline => copyWith(decoration: TextDecoration.underline);
  TextStyle get lineThrough => copyWith(decoration: TextDecoration.lineThrough);
}
