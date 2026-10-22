import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'sky_metrics.dart';
import 'sky_tokens.dart';
import 'sky_type.dart';

abstract final class SkyThemes {
  static final ThemeData _legacyBase = AppTheme.lightTheme;
  static final Expando<ThemeData> _legacy = Expando<ThemeData>('SkyLegacyTheme');
  static final Expando<ThemeData> _material = Expando<ThemeData>('SkyMaterialTheme');

  static ThemeData legacy(SkyTokens tokens) =>
      _legacy[tokens] ??= _legacyBase.copyWith(extensions: <ThemeExtension<dynamic>>[tokens]);

  static ThemeData material(SkyTokens tokens) => _material[tokens] ??= _build(tokens);

  static TextTheme textTheme(SkyTokens t) {
    return TextTheme(
      displayLarge: SkyType.displayLarge.copyWith(color: t.title),
      displayMedium: SkyType.display.copyWith(color: t.title),
      displaySmall: SkyType.title.copyWith(color: t.title),
      headlineLarge: SkyType.title.copyWith(color: t.title),
      headlineMedium: SkyType.headline.copyWith(color: t.text),
      headlineSmall: SkyType.headlineSmall.copyWith(color: t.text),
      titleLarge: SkyType.serifLarge.copyWith(color: t.text),
      titleMedium: SkyType.bodyStrong.copyWith(color: t.text),
      titleSmall: SkyType.chip.copyWith(color: t.text),
      bodyLarge: SkyType.bodyLarge.copyWith(color: t.text),
      bodyMedium: SkyType.body.copyWith(color: t.text),
      bodySmall: SkyType.bodySmall.copyWith(color: t.muted),
      labelLarge: SkyType.button.copyWith(color: t.text),
      labelMedium: SkyType.chip.copyWith(color: t.muted),
      labelSmall: SkyType.label.copyWith(color: t.muted),
    );
  }

  static ThemeData _build(SkyTokens t) {
    final brightness = t.isNight ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: t.rose,
      onPrimary: SkyTokens.white,
      primaryContainer: t.roseSoft,
      onPrimaryContainer: t.rose,
      secondary: t.gold,
      onSecondary: t.activeFg,
      secondaryContainer: t.goldSoft,
      onSecondaryContainer: t.gold,
      tertiary: t.lavender,
      onTertiary: SkyTokens.white,
      error: t.roseDeep,
      onError: SkyTokens.white,
      errorContainer: t.roseSoft,
      onErrorContainer: t.rose,
      surface: t.surface,
      onSurface: t.text,
      onSurfaceVariant: t.muted,
      surfaceContainerHighest: t.surface2,
      outline: t.cardBorder,
      outlineVariant: t.hairline,
      shadow: const Color(0xFF000000),
      scrim: t.scrim,
      surfaceTint: const Color(0x00000000),
      inverseSurface: t.text,
      onInverseSurface: t.page,
      inversePrimary: t.roseDeep,
    );
    final text = textTheme(t);
    OutlineInputBorder outline(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: SkyRadii.all(SkyRadii.field),
          borderSide: BorderSide(color: color, width: width),
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: SkyFonts.sans,
      scaffoldBackgroundColor: t.page,
      canvasColor: t.page,
      cardColor: t.surface,
      dividerColor: t.hairline,
      textTheme: text,
      primaryTextTheme: text,
      splashFactory: NoSplash.splashFactory,
      splashColor: const Color(0x00000000),
      highlightColor: const Color(0x00000000),
      hoverColor: t.roseSoft,
      focusColor: t.roseSoft,
      iconTheme: IconThemeData(color: t.text, size: 20),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: t.roseDeep,
        selectionColor: t.rose.withValues(alpha: 0.28),
        selectionHandleColor: t.rose,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.chip,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: SkyType.body.copyWith(color: t.faint),
        labelStyle: SkyType.small.copyWith(color: t.muted),
        errorStyle: SkyType.small.copyWith(color: t.rose),
        border: outline(t.chipBorder),
        enabledBorder: outline(t.chipBorder),
        focusedBorder: outline(t.rose, 1.4),
        errorBorder: outline(t.roseBorder),
        focusedErrorBorder: outline(t.rose, 1.4),
        disabledBorder: outline(t.hairline),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.gold,
        circularTrackColor: t.toggleOff,
        linearTrackColor: t.toggleOff,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: const Color(0x00000000),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: SkyRadii.all(SkyRadii.feature),
          side: BorderSide(color: t.cardBorder),
        ),
        titleTextStyle: SkyType.headline.copyWith(color: t.text),
        contentTextStyle: SkyType.body.copyWith(color: t.muted),
        barrierColor: t.scrim,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: const Color(0x00000000),
        modalBarrierColor: t.scrim,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: SkyRadii.top(SkyRadii.sheet)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: const Color(0x00000000),
        headerBackgroundColor: t.surface2,
        headerForegroundColor: t.title,
        headerHeadlineStyle: SkyType.headline.copyWith(color: t.title),
        weekdayStyle: SkyType.small.copyWith(color: t.muted),
        dayStyle: SkyType.body,
        todayForegroundColor: WidgetStatePropertyAll(t.rose),
        todayBorder: BorderSide(color: t.rose),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? SkyTokens.white : t.text,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? t.roseDeep : null,
        ),
        yearForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? SkyTokens.white : t.text,
        ),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? t.roseDeep : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: SkyRadii.all(SkyRadii.feature)),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: t.muted),
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: t.rose),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: t.rose, textStyle: SkyType.chip),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: t.tipBg,
          borderRadius: SkyRadii.all(SkyRadii.pill),
          border: Border.all(color: t.tipBorder),
        ),
        textStyle: SkyType.tip.copyWith(color: t.tipText),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(4),
        radius: const Radius.circular(SkyRadii.pill),
        thumbColor: WidgetStatePropertyAll(t.faint),
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SharedAxisPageTransitionsBuilder(
            transitionType: SharedAxisTransitionType.horizontal,
            fillColor: t.page,
          ),
          TargetPlatform.iOS: SharedAxisPageTransitionsBuilder(
            transitionType: SharedAxisTransitionType.horizontal,
            fillColor: t.page,
          ),
        },
      ),
      extensions: <ThemeExtension<dynamic>>[t],
    );
  }
}

class SkyTheme extends StatelessWidget {
  const SkyTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.sky;
    return Theme(
      data: SkyThemes.material(tokens),
      child: DefaultTextStyle(
        style: SkyType.body.copyWith(color: tokens.text, decoration: TextDecoration.none),
        child: IconTheme.merge(data: IconThemeData(color: tokens.text, size: 20), child: child),
      ),
    );
  }
}
