import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_metrics.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static const SystemUiOverlayStyle systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Color(0x00000000),
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Color(0x00000000),
    systemNavigationBarContrastEnforced: false,
  );

  static const Color statusBarTint = AppColors.blush100;

  static final TextStyle bodyText = Tw.base.c(AppColors.slate800);

  static TextTheme get textTheme {
    final slate800 = AppColors.slate800;
    return TextTheme(
      displayLarge: Tw.x6l.black.c(slate800),
      displayMedium: Tw.x3l.extrabold.c(slate800),
      displaySmall: Tw.x2l.extrabold.c(slate800),
      headlineLarge: Tw.x3l.extrabold.c(slate800),
      headlineMedium: Tw.x2l.extrabold.c(slate800),
      headlineSmall: Tw.xl.extrabold.c(slate800),
      titleLarge: Tw.lg.bold.c(slate800),
      titleMedium: Tw.base.bold.c(slate800),
      titleSmall: Tw.sm.bold.c(slate800),
      bodyLarge: Tw.base.c(slate800),
      bodyMedium: Tw.base.c(slate800),
      bodySmall: Tw.xs.c(AppColors.slate500),
      labelLarge: Tw.sm.semibold.c(slate800),
      labelMedium: Tw.xs.semibold.c(AppColors.slate600),
      labelSmall: Tw.px10.semibold.c(AppColors.slate400),
    );
  }

  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.blush500,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.blush500,
      onPrimary: AppColors.white,
      primaryContainer: AppColors.blush100,
      onPrimaryContainer: AppColors.blush600,
      secondary: AppColors.lavender500,
      onSecondary: AppColors.white,
      secondaryContainer: AppColors.lavender100,
      onSecondaryContainer: AppColors.lavender700,
      tertiary: AppColors.matcha300,
      error: AppColors.rose600,
      onError: AppColors.white,
      errorContainer: AppColors.rose50,
      onErrorContainer: AppColors.rose700,
      surface: AppColors.white,
      onSurface: AppColors.slate800,
      onSurfaceVariant: AppColors.slate500,
      outline: AppColors.blush200,
      outlineVariant: AppColors.slate200,
      surfaceTint: AppColors.transparent,
      shadow: AppColors.black,
      scrim: AppColors.slate900.withValues(alpha: 0.4),
    );

    final inputRadius = AppRadii.all(AppRadii.xl);
    OutlineInputBorder outline(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: inputRadius,
      borderSide: BorderSide(color: color, width: width),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.blush50,
      canvasColor: AppColors.blush50,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      splashColor: AppColors.transparent,
      highlightColor: AppColors.transparent,
      hoverColor: AppColors.blush100.withValues(alpha: 0.5),
      focusColor: AppColors.blush400.withValues(alpha: 0.2),
      dividerColor: AppColors.slate100,
      iconTheme: const IconThemeData(color: AppColors.slate500, size: 16),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.slate800,
        selectionColor: AppColors.blush200,
        selectionHandleColor: AppColors.blush400,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.transparent,
        surfaceTintColor: AppColors.transparent,
        foregroundColor: AppColors.slate800,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: Tw.sm.bold.c(AppColors.slate800),
        systemOverlayStyle: systemOverlay,
      ),
      cardTheme: CardThemeData(
        color: AppColors.white.withValues(alpha: 0.72),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(AppRadii.x3l),
          side: BorderSide(color: AppColors.white.withValues(alpha: 0.85)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.blush500,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.x2l)),
          textStyle: Tw.sm.semibold,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.blush600,
          textStyle: Tw.xs.semibold,
          shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.xl)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        hintStyle: Tw.xs.c(AppColors.slate400),
        labelStyle: Tw.xs.semibold.c(AppColors.slate600),
        border: outline(AppColors.blush200),
        enabledBorder: outline(AppColors.blush200),
        focusedBorder: outline(AppColors.blush400, 2),
        errorBorder: outline(AppColors.rose300),
        focusedErrorBorder: outline(AppColors.rose400, 2),
        disabledBorder: outline(AppColors.slate200),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.blush500,
        circularTrackColor: AppColors.blush200,
        linearTrackColor: AppColors.white,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.xl)),
        side: const BorderSide(color: AppColors.blush300, width: 2),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.matcha300 : AppColors.white,
        ),
        checkColor: const WidgetStatePropertyAll(AppColors.emerald900),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(AppRadii.x3l),
          side: const BorderSide(color: AppColors.blush100),
        ),
        titleTextStyle: Tw.base.bold.c(AppColors.slate800),
        contentTextStyle: Tw.px11.relaxed.c(AppColors.slate500),
        barrierColor: AppColors.slate900.withValues(alpha: 0.4),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.transparent,
        modalBarrierColor: AppColors.slate900.withValues(alpha: 0.4),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.top(AppRadii.x3l)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.blush500,
        contentTextStyle: Tw.xs.semibold.c(AppColors.white),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.full)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.transparent,
        headerBackgroundColor: AppColors.blush100,
        headerForegroundColor: AppColors.blush600,
        todayForegroundColor: const WidgetStatePropertyAll(AppColors.blush600),
        todayBorder: const BorderSide(color: AppColors.blush400),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.white : AppColors.slate700,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.blush500 : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.x3l)),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: AppColors.slate500),
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: AppColors.blush600),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.slate800,
          borderRadius: AppRadii.all(AppRadii.lg),
        ),
        textStyle: Tw.px11.medium.c(AppColors.white),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(AppRadii.full),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? AppColors.blush300 : AppColors.blush200,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
      ),
    );
  }
}
