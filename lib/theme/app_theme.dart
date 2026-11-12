import 'package:flutter/material.dart';

// All colors below come from DesignArtifact.html (Light and Dark screens).
// Change a color here and the whole app changes with it.

class AppTheme {
  // Light colors
  static const _lightPrimary = Color(0xFF0175C2); // main blue (buttons, links)
  static const _lightSecondary = Color(
    0xFF13B9FD,
  ); // bright sky blue (rider dots)
  static const _lightText = Color(0xFF0B1F33);
  static const _lightMuted = Color(0xFF4A6178); // grey blue for small text
  static const _lightBorder = Color(0xFFD5E2EE);
  static const _lightBackground = Color(0xFFE8F0F7); // behind everything
  static const _lightSurface = Color(0xFFFFFFFF); // cards and sheets
  static const _lightChip = Color(0xFFE1F2FD); // "Live sync" pill background
  static const _lightChipText = Color(0xFF01579B);
  static const _lightPanel = Color(0xFFF1F6FB); // soft box inside a sheet

  // Dark colors
  static const _darkPrimary = Color(0xFF54C5F8);
  static const _darkOnPrimary = Color(0xFF04203D);
  static const _darkSecondary = Color(0xFF13B9FD);
  static const _darkText = Color(0xFFECF1F6);
  static const _darkMuted = Color(0xFF9AA5B1);
  static const _darkBorder = Color(0xFF2A313A);
  static const _darkBackground = Color(0xFF0A0C0F);
  static const _darkSurface = Color(0xFF161A20);
  static const _darkChip = Color(0xFF1B2530);
  static const _darkChipText = Color(0xFF7DD3FB);
  static const _darkPanel = Color(0xFF11151A);

  // Warning color for "Signal lost" (the design has none, so we pick amber)
  static const _warnLight = Color(0xFFB45309);
  static const _warnDark = Color(0xFFFFBA28);

  static final ThemeData light = _build(
    const ColorScheme.light(
      primary: _lightPrimary,
      onPrimary: Colors.white,
      primaryContainer: _lightChip,
      onPrimaryContainer: _lightChipText,
      secondary: _lightSecondary,
      onSecondary: Color(0xFF04203D),
      tertiary: _warnLight,
      surface: _lightBackground,
      onSurface: _lightText,
      onSurfaceVariant: _lightMuted,
      surfaceContainerLow: _lightSurface,
      surfaceContainerHighest: _lightPanel,
      outlineVariant: _lightBorder,
    ),
  );

  static final ThemeData dark = _build(
    const ColorScheme.dark(
      primary: _darkPrimary,
      onPrimary: _darkOnPrimary,
      primaryContainer: _darkChip,
      onPrimaryContainer: _darkChipText,
      secondary: _darkSecondary,
      onSecondary: _darkOnPrimary,
      tertiary: _warnDark,
      surface: _darkBackground,
      onSurface: _darkText,
      onSurfaceVariant: _darkMuted,
      surfaceContainerLow: _darkSurface,
      surfaceContainerHighest: _darkPanel,
      outlineVariant: _darkBorder,
    ),
  );

  // One function builds both themes so they always have the same shapes.
  // Only the colors differ between light and dark.
  static ThemeData _build(ColorScheme colors) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      // The design uses the Manrope font. Adding it needs a new package,
      // so for now the phone's normal font is used.

      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: colors.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),

      // White cards with a thin border and rounded corners.
      cardTheme: CardThemeData(
        color: colors.surfaceContainerLow,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),

      // Big rounded buttons (54 tall, corner radius 16) like "Start synced ride".
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          foregroundColor: colors.onSurface,
          side: BorderSide(color: colors.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.primaryContainer,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected ? colors.primary : colors.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? colors.primary : colors.onSurfaceVariant,
          );
        }),
      ),

      dividerTheme: DividerThemeData(color: colors.outlineVariant),
    );
  }
}
