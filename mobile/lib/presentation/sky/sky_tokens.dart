import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum SkyMode { day, night }

@immutable
class SkyTokens extends ThemeExtension<SkyTokens> {
  const SkyTokens({
    required this.mode,
    required this.skyTop,
    required this.skyMid,
    required this.skyLow,
    required this.horizon,
    required this.haze,
    required this.page,
    required this.star,
    required this.starCore,
    required this.line,
    required this.lineUnder,
    required this.pointUnder,
    required this.gold,
    required this.goldDeep,
    required this.goldSoft,
    required this.label,
    required this.kicker,
    required this.title,
    required this.rose,
    required this.roseDeep,
    required this.roseSoft,
    required this.roseBorder,
    required this.lavender,
    required this.lavenderSoft,
    required this.surface,
    required this.surface2,
    required this.cardTop,
    required this.cardBottom,
    required this.cardBorder,
    required this.featureTop,
    required this.featureBottom,
    required this.hairline,
    required this.chip,
    required this.chipBorder,
    required this.text,
    required this.muted,
    required this.faint,
    required this.dock,
    required this.dockBorder,
    required this.dockIcon,
    required this.activeBg,
    required this.activeFg,
    required this.activeGlow,
    required this.skyline,
    required this.skylineOpacity,
    required this.window,
    required this.tipBg,
    required this.tipBorder,
    required this.tipText,
    required this.paper,
    required this.paperInk,
    required this.paperMuted,
    required this.toggleOff,
    required this.scrim,
    required this.hereText,
    required this.hereBg,
    required this.hereBorder,
    required this.nameShadow,
    required this.gapStroke,
    required this.burstRay,
    required this.sparkle,
    required this.envelope,
    required this.shadow,
    required this.softShadow,
    required this.cardShadow,
    required this.sheetShadow,
    required this.dockShadow,
    required this.glowSigma,
  });

  final SkyMode mode;
  final Color skyTop;
  final Color skyMid;
  final Color skyLow;
  final Color horizon;
  final Color haze;
  final Color page;
  final Color star;
  final Color starCore;
  final Color line;
  final Color lineUnder;
  final Color pointUnder;
  final Color gold;
  final Color goldDeep;
  final Color goldSoft;
  final Color label;
  final Color kicker;
  final Color title;
  final Color rose;
  final Color roseDeep;
  final Color roseSoft;
  final Color roseBorder;
  final Color lavender;
  final Color lavenderSoft;
  final Color surface;
  final Color surface2;
  final Color cardTop;
  final Color cardBottom;
  final Color cardBorder;
  final Color featureTop;
  final Color featureBottom;
  final Color hairline;
  final Color chip;
  final Color chipBorder;
  final Color text;
  final Color muted;
  final Color faint;
  final Color dock;
  final Color dockBorder;
  final Color dockIcon;
  final Color activeBg;
  final Color activeFg;
  final Color activeGlow;
  final Color skyline;
  final double skylineOpacity;
  final Color window;
  final Color tipBg;
  final Color tipBorder;
  final Color tipText;
  final Color paper;
  final Color paperInk;
  final Color paperMuted;
  final Color toggleOff;
  final Color scrim;
  final Color hereText;
  final Color hereBg;
  final Color hereBorder;
  final Color nameShadow;
  final Color gapStroke;
  final Color burstRay;
  final Color sparkle;
  final Color envelope;
  final List<BoxShadow> shadow;
  final List<BoxShadow> softShadow;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> sheetShadow;
  final List<BoxShadow> dockShadow;
  final double glowSigma;

  static const Color white = Color(0xFFFFFFFF);
  static const Color indigo = Color(0xFF2B2A6B);
  static const Color roseLight = Color(0xFFFF8AAE);
  static const Color roseMid = Color(0xFFF7608D);
  static const Color roseBase = Color(0xFFFF6B95);
  static const Color roseDark = Color(0xFFE24E79);
  static const Color presence = Color(0xFFFF6B95);

  bool get isNight => mode == SkyMode.night;
  bool get isDay => mode == SkyMode.day;

  LinearGradient get skyGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [skyTop, skyMid, skyLow],
    stops: const [0, 0.55, 1],
  );

  LinearGradient get cardGradient =>
      LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [cardTop, cardBottom]);

  LinearGradient get featureGradient =>
      LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [featureTop, featureBottom]);

  LinearGradient get primaryGradient => const LinearGradient(colors: [roseDark, roseMid, roseDark]);

  LinearGradient get roseOrbGradient =>
      const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [roseLight, roseDark]);

  LinearGradient get toggleOnGradient => LinearGradient(colors: [roseDeep, rose]);

  LinearGradient get progressGradient => LinearGradient(colors: [gold, rose]);

  List<BoxShadow> get primaryShadow => const [
    BoxShadow(color: Color(0x6BE24E79), offset: Offset(0, 8), blurRadius: 18.2),
  ];

  SystemUiOverlayStyle get statusBar => isNight
      ? const SystemUiOverlayStyle(
          statusBarColor: Color(0x00000000),
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Color(0x00000000),
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarDividerColor: Color(0x00000000),
          systemNavigationBarContrastEnforced: false,
        )
      : const SystemUiOverlayStyle(
          statusBarColor: Color(0x00000000),
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Color(0x00000000),
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: Color(0x00000000),
          systemNavigationBarContrastEnforced: false,
        );

  static SkyTokens of(SkyMode mode) => mode == SkyMode.day ? day : night;

  static const SkyTokens night = SkyTokens(
    mode: SkyMode.night,
    skyTop: Color(0xFF0B0B2B),
    skyMid: Color(0xFF1A1650),
    skyLow: Color(0xFF3A1D4F),
    horizon: Color(0x38FF6B95),
    haze: Color(0x33845CCC),
    page: Color(0xFF0E0D2C),
    star: Color(0xFFFFD98A),
    starCore: Color(0xFFFFFFFF),
    line: Color(0x6BFFD98A),
    lineUnder: Color(0x00000000),
    pointUnder: Color(0x00000000),
    gold: Color(0xFFFFD98A),
    goldDeep: Color(0xFFE8B04B),
    goldSoft: Color(0x24FFD98A),
    label: Color(0xFFFFE8B5),
    kicker: Color(0xEBC0B9E8),
    title: Color(0xFFFFFFFF),
    rose: Color(0xFFFF6B95),
    roseDeep: Color(0xFFE24E79),
    roseSoft: Color(0x24FF6B95),
    roseBorder: Color(0x4DFF6B95),
    lavender: Color(0xFFA99BFF),
    lavenderSoft: Color(0x24A99BFF),
    surface: Color(0xFF141238),
    surface2: Color(0xFF1C1A45),
    cardTop: Color(0xFF1E1B4E),
    cardBottom: Color(0xFF171442),
    cardBorder: Color(0x29FFD98A),
    featureTop: Color(0xFF221E57),
    featureBottom: Color(0xFF16133F),
    hairline: Color(0x14FFFFFF),
    chip: Color(0xB8110F33),
    chipBorder: Color(0x12FFFFFF),
    text: Color(0xFFF3F0FF),
    muted: Color(0xFFA9A3D1),
    faint: Color(0x8CA9A3D1),
    dock: Color(0xF51C1A45),
    dockBorder: Color(0x1AFFFFFF),
    dockIcon: Color(0xFF9E97C7),
    activeBg: Color(0xFFFFD98A),
    activeFg: Color(0xFF1B1838),
    activeGlow: Color(0x61FFD98A),
    skyline: Color(0xFF0F0C29),
    skylineOpacity: 0.96,
    window: Color(0x8CFFD98A),
    tipBg: Color(0xEB141238),
    tipBorder: Color(0x80FFD98A),
    tipText: Color(0xFFFFECC7),
    paper: Color(0xFFFFF8EC),
    paperInk: Color(0xFF2A2440),
    paperMuted: Color(0xFF857C9E),
    toggleOff: Color(0x24FFFFFF),
    scrim: Color(0x73060516),
    hereText: Color(0xFFFFB6CB),
    hereBg: Color(0xCC1A1650),
    hereBorder: Color(0x73FF6B95),
    nameShadow: Color(0x59000000),
    gapStroke: Color(0xFFFFD98A),
    burstRay: Color(0xFFFFE8B5),
    sparkle: Color(0xFFFFD98A),
    envelope: Color(0xFFFFF2CE),
    shadow: [BoxShadow(color: Color(0x8C04030F), offset: Offset(0, 14), blurRadius: 28.6)],
    softShadow: [BoxShadow(color: Color(0x5904030F), offset: Offset(0, 8), blurRadius: 18.2)],
    cardShadow: [],
    sheetShadow: [BoxShadow(color: Color(0xBF070617), offset: Offset(0, -14), blurRadius: 33.8)],
    dockShadow: [BoxShadow(color: Color(0xB304030F), offset: Offset(0, 14), blurRadius: 28.6)],
    glowSigma: 3.2,
  );

  static const SkyTokens day = SkyTokens(
    mode: SkyMode.day,
    skyTop: Color(0xFF8FC3FF),
    skyMid: Color(0xFFC9E0FF),
    skyLow: Color(0xFFFFE1CC),
    horizon: Color(0x59FFAA82),
    haze: Color(0x59FFFFFF),
    page: Color(0xFFF4F6FF),
    star: Color(0xFFFFFFFF),
    starCore: Color(0xFFFFFFFF),
    line: Color(0xEBFFFFFF),
    lineUnder: Color(0x1A2B2A6B),
    pointUnder: Color(0x1F2B2A6B),
    gold: Color(0xFFE8B04B),
    goldDeep: Color(0xFFC98D24),
    goldSoft: Color(0x24E8B04B),
    label: Color(0xFF2B2A6B),
    kicker: Color(0xB32B2A6B),
    title: Color(0xFF2B2A6B),
    rose: Color(0xFFFF6B95),
    roseDeep: Color(0xFFE24E79),
    roseSoft: Color(0x1AFF6B95),
    roseBorder: Color(0x4DFF6B95),
    lavender: Color(0xFF5B58C9),
    lavenderSoft: Color(0x1A5B58C9),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF6F7FE),
    cardTop: Color(0xFFFFFFFF),
    cardBottom: Color(0xFFFAF9FF),
    cardBorder: Color(0xFFE6E9F7),
    featureTop: Color(0xFFFFFFFF),
    featureBottom: Color(0xFFFFFFFF),
    hairline: Color(0xFFE9EBF7),
    chip: Color(0xFFFFFFFF),
    chipBorder: Color(0xFFE6E9F7),
    text: Color(0xFF1E1B3A),
    muted: Color(0xFF6B6890),
    faint: Color(0xFFA3A1C2),
    dock: Color(0xF7FFFFFF),
    dockBorder: Color(0xFFE6E9F7),
    dockIcon: Color(0xFF8E8BB0),
    activeBg: Color(0xFF2B2A6B),
    activeFg: Color(0xFFFFFFFF),
    activeGlow: Color(0x00FFFFFF),
    skyline: Color(0xFFB9C9E8),
    skylineOpacity: 0.55,
    window: Color(0x00FFFFFF),
    tipBg: Color(0xF2FFFFFF),
    tipBorder: Color(0x1F2B2A6B),
    tipText: Color(0xFF2B2A6B),
    paper: Color(0xFFFFFFFF),
    paperInk: Color(0xFF2A2440),
    paperMuted: Color(0xFF8A86A8),
    toggleOff: Color(0xFFE3E5F3),
    scrim: Color(0x2E2B2A6B),
    hereText: Color(0xFFD23F6E),
    hereBg: Color(0xE6FFFFFF),
    hereBorder: Color(0x59FF6B95),
    nameShadow: Color(0xE6FFFFFF),
    gapStroke: Color(0xFF2B2A6B),
    burstRay: Color(0xFFFFFFFF),
    sparkle: Color(0xFFFFFFFF),
    envelope: Color(0xFFFFFFFF),
    shadow: [BoxShadow(color: Color(0x242B2A6B), offset: Offset(0, 14), blurRadius: 28.6)],
    softShadow: [BoxShadow(color: Color(0x142B2A6B), offset: Offset(0, 8), blurRadius: 18.2)],
    cardShadow: [BoxShadow(color: Color(0x142B2A6B), offset: Offset(0, 8), blurRadius: 18.2)],
    sheetShadow: [BoxShadow(color: Color(0x1A2B2A6B), offset: Offset(0, -12), blurRadius: 28.6)],
    dockShadow: [BoxShadow(color: Color(0x292B2A6B), offset: Offset(0, 14), blurRadius: 28.6)],
    glowSigma: 2.2,
  );

  @override
  SkyTokens copyWith({SkyMode? mode}) => mode == null || mode == this.mode ? this : SkyTokens.of(mode);

  @override
  SkyTokens lerp(covariant ThemeExtension<SkyTokens>? other, double t) {
    if (other is! SkyTokens) return this;
    if (t <= 0) return this;
    if (t >= 1) return other;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    List<BoxShadow> s(List<BoxShadow> a, List<BoxShadow> b) => BoxShadow.lerpList(a, b, t) ?? const [];
    double d(double a, double b) => a + (b - a) * t;
    return SkyTokens(
      mode: t < 0.5 ? mode : other.mode,
      skyTop: c(skyTop, other.skyTop),
      skyMid: c(skyMid, other.skyMid),
      skyLow: c(skyLow, other.skyLow),
      horizon: c(horizon, other.horizon),
      haze: c(haze, other.haze),
      page: c(page, other.page),
      star: c(star, other.star),
      starCore: c(starCore, other.starCore),
      line: c(line, other.line),
      lineUnder: c(lineUnder, other.lineUnder),
      pointUnder: c(pointUnder, other.pointUnder),
      gold: c(gold, other.gold),
      goldDeep: c(goldDeep, other.goldDeep),
      goldSoft: c(goldSoft, other.goldSoft),
      label: c(label, other.label),
      kicker: c(kicker, other.kicker),
      title: c(title, other.title),
      rose: c(rose, other.rose),
      roseDeep: c(roseDeep, other.roseDeep),
      roseSoft: c(roseSoft, other.roseSoft),
      roseBorder: c(roseBorder, other.roseBorder),
      lavender: c(lavender, other.lavender),
      lavenderSoft: c(lavenderSoft, other.lavenderSoft),
      surface: c(surface, other.surface),
      surface2: c(surface2, other.surface2),
      cardTop: c(cardTop, other.cardTop),
      cardBottom: c(cardBottom, other.cardBottom),
      cardBorder: c(cardBorder, other.cardBorder),
      featureTop: c(featureTop, other.featureTop),
      featureBottom: c(featureBottom, other.featureBottom),
      hairline: c(hairline, other.hairline),
      chip: c(chip, other.chip),
      chipBorder: c(chipBorder, other.chipBorder),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      faint: c(faint, other.faint),
      dock: c(dock, other.dock),
      dockBorder: c(dockBorder, other.dockBorder),
      dockIcon: c(dockIcon, other.dockIcon),
      activeBg: c(activeBg, other.activeBg),
      activeFg: c(activeFg, other.activeFg),
      activeGlow: c(activeGlow, other.activeGlow),
      skyline: c(skyline, other.skyline),
      skylineOpacity: d(skylineOpacity, other.skylineOpacity),
      window: c(window, other.window),
      tipBg: c(tipBg, other.tipBg),
      tipBorder: c(tipBorder, other.tipBorder),
      tipText: c(tipText, other.tipText),
      paper: c(paper, other.paper),
      paperInk: c(paperInk, other.paperInk),
      paperMuted: c(paperMuted, other.paperMuted),
      toggleOff: c(toggleOff, other.toggleOff),
      scrim: c(scrim, other.scrim),
      hereText: c(hereText, other.hereText),
      hereBg: c(hereBg, other.hereBg),
      hereBorder: c(hereBorder, other.hereBorder),
      nameShadow: c(nameShadow, other.nameShadow),
      gapStroke: c(gapStroke, other.gapStroke),
      burstRay: c(burstRay, other.burstRay),
      sparkle: c(sparkle, other.sparkle),
      envelope: c(envelope, other.envelope),
      shadow: s(shadow, other.shadow),
      softShadow: s(softShadow, other.softShadow),
      cardShadow: s(cardShadow, other.cardShadow),
      sheetShadow: s(sheetShadow, other.sheetShadow),
      dockShadow: s(dockShadow, other.dockShadow),
      glowSigma: d(glowSigma, other.glowSigma),
    );
  }
}

extension SkyContext on BuildContext {
  SkyTokens get sky => Theme.of(this).extension<SkyTokens>() ?? SkyTokens.night;

  bool get skyIsNight => sky.isNight;
}
