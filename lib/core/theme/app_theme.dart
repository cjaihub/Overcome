import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';

abstract final class AppTheme {
  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    background: Brand.ink,
    surface: Brand.midnight,
    surfaceHigh: Brand.slate,
    onSurface: Colors.white,
  );

  static ThemeData light() => _build(
    brightness: Brightness.light,
    background: Brand.mist,
    surface: Colors.white,
    surfaceHigh: Brand.cloud,
    onSurface: Brand.ink,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceHigh,
    required Color onSurface,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: Brand.aurora,
      onPrimary: Brand.ink,
      secondary: Brand.iris,
      onSecondary: Colors.white,
      tertiary: Brand.ember,
      onTertiary: Brand.ink,
      error: Brand.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceHigh,
      outline: onSurface.withValues(alpha: 0.14),
      outlineVariant: onSurface.withValues(alpha: 0.08),
    );
    final text = Brand.textTheme(onSurface);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.radius));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        foregroundColor: onSurface,
        systemOverlayStyle: brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(color: surface, elevation: 0, shape: shape, margin: EdgeInsets.zero),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: Brand.aurora,
          foregroundColor: Brand.ink,
          textStyle: text.labelLarge?.copyWith(fontSize: 16),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: onSurface,
          side: BorderSide(color: onSurface.withValues(alpha: 0.18)),
          textStyle: text.labelLarge?.copyWith(fontSize: 16),
          shape: shape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh.withValues(alpha: brightness == Brightness.dark ? 0.6 : 1),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(Brand.radius), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
          borderSide: const BorderSide(color: Brand.aurora, width: 1.6),
        ),
        hintStyle: text.bodyLarge?.copyWith(color: onSurface.withValues(alpha: 0.4)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: Brand.aurora.withValues(alpha: 0.18),
        side: BorderSide(color: onSurface.withValues(alpha: 0.08)),
        labelStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: Brand.aurora,
        inactiveTrackColor: onSurface.withValues(alpha: 0.1),
        thumbColor: Colors.white,
        overlayColor: Brand.aurora.withValues(alpha: 0.16),
        trackHeight: 6,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface.withValues(alpha: 0.92),
        indicatorColor: Brand.aurora.withValues(alpha: 0.16),
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) =>
              IconThemeData(color: s.contains(WidgetState.selected) ? Brand.aurora : onSurface.withValues(alpha: 0.6)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Brand.aurora : onSurface.withValues(alpha: 0.16),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
