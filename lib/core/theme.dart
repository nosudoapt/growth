import 'package:flutter/material.dart';

/// Dark-first palette.
class GCol {
  const GCol._();
  static const Color bg = Color(0xFF0E0D0B);
  static const Color surface = Color(0xFF1A1814);
  static const Color text = Color(0xFFF4EFE6);
  static const Color muted = Color(0xFF9C958A);
  static const Color gold = Color(0xFFF5C04A);
  static const Color ember = Color(0xFFE0703A);
}

/// Build the app theme. Serif display = Playfair Display (bundled); UI = Inter
/// (bundled). Body text never goes below 16sp. WCAG AA: #F4EFE6 on #0E0D0B is
/// ~15:1; muted #9C958A on #0E0D0B is ~6.4:1 — both pass AA for their uses.
ThemeData buildGrowthTheme(bool dark) {
  final cs = dark
      ? ColorScheme.dark(
          surface: GCol.bg,
          secondaryContainer: GCol.surface,
          primary: GCol.gold,
          onPrimary: GCol.bg,
          secondary: GCol.ember,
          onSecondary: GCol.bg,
          onSurface: GCol.text,
          onSurfaceVariant: GCol.muted,
          error: Color(0xFFEF9B8A),
        )
      : ColorScheme.light(
          surface: GCol.text,
          secondaryContainer: Color(0xFFE7E0D2),
          primary: Color(0xFFA87918),
          onPrimary: Color(0xFFFFFFFF),
          secondary: Color(0xFFB24E22),
          onSecondary: Color(0xFFFFFFFF),
          onSurface: GCol.bg,
          onSurfaceVariant: Color(0xFF5E5A52),
        );

  const serif = 'Playfair Display';
  const sans = 'Inter';

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: dark ? GCol.bg : GCol.text,
    splashFactory: InkSparkle.splashFactory,
    fontFamily: sans,
    textTheme: const TextTheme(
      displayLarge: TextStyle(
          fontFamily: serif, fontSize: 34, height: 1.12, color: GCol.text),
      displayMedium: TextStyle(
          fontFamily: serif, fontSize: 28, height: 1.15, color: GCol.text),
      displaySmall: TextStyle(
          fontFamily: serif, fontSize: 24, height: 1.2, color: GCol.text),
      headlineMedium: TextStyle(
          fontFamily: serif, fontSize: 22, height: 1.25, color: GCol.text),
      bodyLarge: TextStyle(fontSize: 16, height: 1.55, color: GCol.text),
      bodyMedium: TextStyle(fontSize: 15, height: 1.5, color: GCol.text),
      bodySmall: TextStyle(fontSize: 16, height: 1.4, color: GCol.muted),
      labelLarge: TextStyle(
          fontFamily: sans, fontSize: 16, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontFamily: sans, fontSize: 16, color: GCol.muted),
      labelSmall: TextStyle(
          fontFamily: sans, fontSize: 15, letterSpacing: 0.4, color: GCol.muted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? GCol.bg : GCol.text,
      foregroundColor: dark ? GCol.text : GCol.bg,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? GCol.surface : Color(0xFFE7E0D2),
      indicatorColor: GCol.gold.withValues(alpha: 0.25),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: sans,
          fontSize: 15,
          color: states.contains(WidgetState.selected)
              ? GCol.gold
              : GCol.muted,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: GCol.surface,
      contentTextStyle: const TextStyle(
          fontFamily: sans, fontSize: 16, color: GCol.text),
      behavior: SnackBarBehavior.floating,
    ),
    iconTheme: IconThemeData(color: dark ? GCol.text : GCol.bg, size: 24),
    sliderTheme: const SliderThemeData(
      activeTrackColor: GCol.gold,
      inactiveTrackColor: GCol.surface,
      thumbColor: GCol.gold,
      valueIndicatorColor: GCol.surface,
    ),
  ).copyWith(textSelectionTheme: TextSelectionThemeData(
      cursorColor: GCol.gold, selectionColor: GCol.gold.withValues(alpha: .3)));
}
