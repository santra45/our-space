import 'package:flutter/widgets.dart';

import 'sky_tokens.dart';

abstract final class SkyFonts {
  static const String serif = 'BodoniModa';
  static const String sans = 'DMSans';
  static const String hand = 'Caveat';
  static const List<String> handFallback = ['CaveatLatinExt', SkyFonts.sans];
  static const List<String> serifFallback = [SkyFonts.sans];

  static List<FontVariation> serifAxes(double size, FontWeight weight) => [
        FontVariation('wght', weight.value.toDouble()),
        FontVariation('opsz', size.clamp(6.0, 96.0)),
      ];

  static List<FontVariation> sansAxes(double size, FontWeight weight) => [
        FontVariation('wght', weight.value.toDouble()),
        FontVariation('opsz', size.clamp(9.0, 40.0)),
      ];
}

abstract final class SkyType {
  static TextStyle serif(
    double size, {
    FontWeight weight = FontWeight.w400,
    bool italic = true,
    double? height,
    double? letterSpacing,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: SkyFonts.serif,
      fontFamilyFallback: SkyFonts.serifFallback,
      fontSize: size,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      fontVariations: SkyFonts.serifAxes(size, weight),
      height: height,
      letterSpacing: letterSpacing,
      color: color,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  static TextStyle sans(
    double size, {
    FontWeight weight = FontWeight.w400,
    double? height,
    double? letterSpacing,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: SkyFonts.sans,
      fontSize: size,
      fontWeight: weight,
      fontVariations: SkyFonts.sansAxes(size, weight),
      height: height,
      letterSpacing: letterSpacing,
      color: color,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  static TextStyle caps(double size, {FontWeight weight = FontWeight.w700, double tracking = 0.2, Color? color}) {
    return sans(size, weight: weight, letterSpacing: size * tracking, height: 1.3, color: color);
  }

  static TextStyle hand(double size, {Color? color, double height = 1.05}) {
    return TextStyle(
      fontFamily: SkyFonts.hand,
      fontFamilyFallback: SkyFonts.handFallback,
      fontSize: size,
      height: height,
      color: color,
    );
  }

  static final TextStyle displayLarge = serif(46, height: 1.1);
  static final TextStyle display = serif(35, height: 1.12, letterSpacing: 0.35);
  static final TextStyle title = serif(28, height: 1.15);
  static final TextStyle titleSmall = serif(26, height: 1.15);
  static final TextStyle headline = serif(24, weight: FontWeight.w500, height: 1.2);
  static final TextStyle headlineSmall = serif(22, weight: FontWeight.w500, height: 1.2);
  static final TextStyle serifLarge = serif(19, height: 1.3);
  static final TextStyle serifBody = serif(17.5, height: 1.3);
  static final TextStyle serifItem = serif(16, weight: FontWeight.w500, height: 1.25);
  static final TextStyle name = serif(15, weight: FontWeight.w500, height: 1.2);
  static final TextStyle stat = serif(18, weight: FontWeight.w600, height: 1.2);
  static final TextStyle avatar = serif(18, height: 1);
  static final TextStyle letter = serif(16.5, italic: false, height: 32 / 16.5);

  static final TextStyle kicker = caps(10.5, weight: FontWeight.w600, tracking: 0.22);
  static final TextStyle label = caps(10, weight: FontWeight.w700, tracking: 0.2);
  static final TextStyle hold = caps(13, weight: FontWeight.w700, tracking: 0.12);

  static final TextStyle bodyLarge = sans(15, height: 1.5);
  static final TextStyle body = sans(14, height: 1.45);
  static final TextStyle bodyStrong = sans(14, weight: FontWeight.w600, height: 1.35);
  static final TextStyle bodySmall = sans(12.5, height: 1.45);
  static final TextStyle small = sans(11.5, height: 1.4);
  static final TextStyle caption = sans(11, height: 1.4);
  static final TextStyle tiny = sans(9.5, weight: FontWeight.w600, height: 1.2);
  static final TextStyle button = sans(14.5, weight: FontWeight.w700, height: 1.2, letterSpacing: 0.15);
  static final TextStyle chip = sans(12, weight: FontWeight.w600, height: 1.2);
  static final TextStyle tip = sans(11, weight: FontWeight.w500, height: 1.25);
  static final TextStyle dock = sans(9.5, weight: FontWeight.w600, height: 1.1);
  static final TextStyle dockActive = sans(12, weight: FontWeight.w700, height: 1.1);

  static final TextStyle handCaption = hand(19);
  static final TextStyle handSignature = hand(26);
}

@immutable
class SkyTypography {
  SkyTypography(this.tokens)
      : displayLarge = SkyType.displayLarge.copyWith(color: tokens.title),
        display = SkyType.display.copyWith(color: tokens.title),
        title = SkyType.title.copyWith(color: tokens.title),
        titleSmall = SkyType.titleSmall.copyWith(color: tokens.title),
        headline = SkyType.headline.copyWith(color: tokens.text),
        headlineSmall = SkyType.headlineSmall.copyWith(color: tokens.text),
        serifLarge = SkyType.serifLarge.copyWith(color: tokens.text),
        serifBody = SkyType.serifBody.copyWith(color: tokens.text),
        serifItem = SkyType.serifItem.copyWith(color: tokens.text),
        name = SkyType.name.copyWith(color: tokens.label),
        stat = SkyType.stat.copyWith(color: tokens.text),
        kicker = SkyType.kicker.copyWith(color: tokens.kicker),
        label = SkyType.label.copyWith(color: tokens.muted),
        body = SkyType.body.copyWith(color: tokens.text),
        bodyMuted = SkyType.body.copyWith(color: tokens.muted),
        bodyStrong = SkyType.bodyStrong.copyWith(color: tokens.text),
        bodySmall = SkyType.bodySmall.copyWith(color: tokens.muted),
        small = SkyType.small.copyWith(color: tokens.muted),
        caption = SkyType.caption.copyWith(color: tokens.faint),
        button = SkyType.button.copyWith(color: tokens.text),
        chip = SkyType.chip.copyWith(color: tokens.text),
        tip = SkyType.tip.copyWith(color: tokens.tipText),
        hand = SkyType.handCaption.copyWith(color: tokens.paperInk);

  final SkyTokens tokens;
  final TextStyle displayLarge;
  final TextStyle display;
  final TextStyle title;
  final TextStyle titleSmall;
  final TextStyle headline;
  final TextStyle headlineSmall;
  final TextStyle serifLarge;
  final TextStyle serifBody;
  final TextStyle serifItem;
  final TextStyle name;
  final TextStyle stat;
  final TextStyle kicker;
  final TextStyle label;
  final TextStyle body;
  final TextStyle bodyMuted;
  final TextStyle bodyStrong;
  final TextStyle bodySmall;
  final TextStyle small;
  final TextStyle caption;
  final TextStyle button;
  final TextStyle chip;
  final TextStyle tip;
  final TextStyle hand;

  static final Expando<SkyTypography> _cache = Expando<SkyTypography>('SkyTypography');

  static SkyTypography of(SkyTokens tokens) => _cache[tokens] ??= SkyTypography(tokens);
}

extension SkyTypeContext on BuildContext {
  SkyTypography get skyText => SkyTypography.of(sky);
}
