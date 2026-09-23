import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/theme.dart';

// Helper shortcut for clean HSL definitions
Color _hsl(double h, double s, double l, [double a = 1.0]) =>
    HSLColor.fromAHSL(a, h, s, l).toColor();

class ThemeSeed {
  const ThemeSeed(this.baseHue, this.accentHue, this.vibrance, this.depth);

  final int baseHue;   // 0–359
  final int accentHue; // 0–359
  final int vibrance;  // 0–9
  final int depth;     // 0–9

  String get code =>
      '${baseHue.toString().padLeft(3, '0')}${accentHue.toString().padLeft(3, '0')}$vibrance$depth';

  /// Accepts "28533082" or "285-330-8-2".
  static ThemeSeed? parse(String input) {
    final digits = input.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^\d{8}$').hasMatch(digits)) return null;
    final base = int.parse(digits.substring(0, 3));
    final accent = int.parse(digits.substring(3, 6));
    if (base > 359 || accent > 359) return null;
    return ThemeSeed(base, accent, int.parse(digits[6]), int.parse(digits[7]));
  }

  ThemeSeed copyWith({int? baseHue, int? accentHue, int? vibrance, int? depth}) => ThemeSeed(
    baseHue ?? this.baseHue,
    accentHue ?? this.accentHue,
    vibrance ?? this.vibrance,
    depth ?? this.depth,
  );
}

FColors generateColors(ThemeSeed s) {
  final b = s.baseHue.toDouble();
  final a = s.accentHue.toDouble();
  final accentSat = 0.40 + s.vibrance * 0.06; // 0.40 – 0.94
  final bgL = 0.03 + s.depth * 0.012;         // 0.03 – 0.138

  return FColors(
    brightness: .dark,
    systemOverlayStyle: .light,
    barrier: _hsl(b, 0.50, 0.03, 0.6),
    background: _hsl(b, 0.35, bgL),
    foreground: _hsl(b, 0.15, 0.96),
    primary: _hsl(a, accentSat, 0.58),
    primaryForeground: _hsl(a, 1.0, 0.98),
    secondary: _hsl(b, 0.25, bgL + 0.09),
    secondaryForeground: _hsl(b, 0.15, 0.96),
    muted: _hsl(b, 0.25, bgL + 0.09),
    mutedForeground: _hsl(b, 0.15, 0.65),
    destructive: _hsl(0, 0.70, 0.50),
    destructiveForeground: _hsl(0, 0.0, 0.98),
    error: _hsl(0, 0.70, 0.50),
    errorForeground: _hsl(0, 0.0, 0.98),
    card: _hsl(b, 0.30, bgL + 0.04),
    border: _hsl(b, 0.20, bgL + 0.13),
    extensions: const [AppColors()],
  );
}

class ThemePreset {
  const ThemePreset({required this.id, required this.label, required this.colors});

  final String id;
  final String label;
  final FColors colors;
}

final themePresets = <ThemePreset>[
// =============================================================================
// 1. PRISM THEME (The Culmination)
// Integrates tokens across the spectrum: Violet primary, Cyan/Teal secondary,
// Amber cards, Emerald borders, and Rose backgrounds.
// =============================================================================
  ThemePreset(
    id: 'defaultTheme',
    label: 'Default',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(260, 0.60, 0.05, 0.65),
      background: _hsl(260, 0.30, 0.05), // Deep cosmic violet
      foreground: _hsl(60, 0.30, 0.96),  // Starlight gold
      primary: _hsl(280, 0.85, 0.65),    // Vivid magenta-violet
      primaryForeground: _hsl(0, 0.0, 1.0),
      secondary: _hsl(185, 0.45, 0.14),  // Deep oceanic teal
      secondaryForeground: _hsl(185, 0.60, 0.90),
      muted: _hsl(225, 0.25, 0.13),      // Deep indigo
      mutedForeground: _hsl(225, 0.20, 0.65),
      destructive: _hsl(355, 0.75, 0.55),// Neon crimson
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(355, 0.75, 0.55),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(290, 0.25, 0.09),       // Midnight amethyst surface
      border: _hsl(160, 0.35, 0.22),     // Subtle auroral green edge
      extensions: const [AppColors()],
    ),
  ),

// =============================================================================
// 2. RED THEME (Ruby / Crimson) - Hue: ~355°
// =============================================================================
  ThemePreset(
    id: 'redTheme',
    label: 'Red',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(0, 0.0, 0.0, 0.5),
      background: _hsl(355, 0.35, 0.05),
      foreground: _hsl(355, 0.15, 0.96),
      primary: _hsl(355, 0.80, 0.54),
      primaryForeground: _hsl(355, 1.0, 0.98),
      secondary: _hsl(355, 0.25, 0.14),
      secondaryForeground: _hsl(355, 0.15, 0.96),
      muted: _hsl(355, 0.25, 0.14),
      mutedForeground: _hsl(355, 0.15, 0.65),
      destructive: _hsl(0, 0.70, 0.50),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.70, 0.50),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(355, 0.30, 0.09),
      border: _hsl(355, 0.20, 0.18),
      extensions: const [AppColors()],
    ),
  ),

// =============================================================================
// 3. ORANGE THEME (Amber / Tangerine) - Hue: ~28°
// =============================================================================
  ThemePreset(
    id: 'orangeTheme',
    label: 'Orange',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(0, 0.0, 0.0, 0.5),
      background: _hsl(28, 0.35, 0.05),
      foreground: _hsl(28, 0.15, 0.96),
      primary: _hsl(28, 0.90, 0.52),
      primaryForeground: _hsl(28, 1.0, 0.98),
      secondary: _hsl(28, 0.25, 0.14),
      secondaryForeground: _hsl(28, 0.15, 0.96),
      muted: _hsl(28, 0.25, 0.14),
      mutedForeground: _hsl(28, 0.15, 0.65),
      destructive: _hsl(0, 0.70, 0.50),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.70, 0.50),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(28, 0.30, 0.09),
      border: _hsl(28, 0.20, 0.18),
      extensions: const [AppColors()],
    ),
  ),

// =============================================================================
// 4. YELLOW THEME (Gold / Sunburst) - Hue: ~45°
// =============================================================================
  ThemePreset(
    id: 'yellowTheme',
    label: 'Yellow',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(0, 0.0, 0.0, 0.5),
      background: _hsl(45, 0.30, 0.05),
      foreground: _hsl(45, 0.15, 0.96),
      primary: _hsl(45, 0.90, 0.50),
      primaryForeground: _hsl(45, 0.80, 0.08),
      secondary: _hsl(45, 0.25, 0.14),
      secondaryForeground: _hsl(45, 0.15, 0.96),
      muted: _hsl(45, 0.25, 0.14),
      mutedForeground: _hsl(45, 0.15, 0.65),
      destructive: _hsl(0, 0.70, 0.50),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.70, 0.50),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(45, 0.25, 0.09),
      border: _hsl(45, 0.20, 0.18),
      extensions: const [AppColors()],
    ),
  ),

// =============================================================================
// 5. GREEN THEME (Emerald / Forest) - Hue: ~152°
// =============================================================================
  ThemePreset(
    id: 'greenTheme',
    label: 'Green',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(0, 0.0, 0.0, 0.5),
      background: _hsl(152, 0.35, 0.05),
      foreground: _hsl(152, 0.15, 0.96),
      primary: _hsl(152, 0.68, 0.46),
      primaryForeground: _hsl(152, 1.0, 0.98),
      secondary: _hsl(152, 0.25, 0.13),
      secondaryForeground: _hsl(152, 0.15, 0.96),
      muted: _hsl(152, 0.25, 0.13),
      mutedForeground: _hsl(152, 0.15, 0.65),
      destructive: _hsl(0, 0.70, 0.50),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.70, 0.50),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(152, 0.30, 0.09),
      border: _hsl(152, 0.20, 0.18),
      extensions: const [AppColors()],
    ),
  ),

// =============================================================================
// 6. BLUE THEME (Sapphire / Ocean) - Hue: ~217°
// =============================================================================
  ThemePreset(
    id: 'blueTheme',
    label: 'Blue',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(0, 0.0, 0.0, 0.5),
      background: _hsl(217, 0.35, 0.05),
      foreground: _hsl(217, 0.15, 0.96),
      primary: _hsl(217, 0.85, 0.58),
      primaryForeground: _hsl(217, 1.0, 0.98),
      secondary: _hsl(217, 0.25, 0.14),
      secondaryForeground: _hsl(217, 0.15, 0.96),
      muted: _hsl(217, 0.25, 0.14),
      mutedForeground: _hsl(217, 0.15, 0.65),
      destructive: _hsl(0, 0.70, 0.50),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.70, 0.50),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(217, 0.30, 0.09),
      border: _hsl(217, 0.20, 0.18),
      extensions: const [AppColors()],
    ),
  ),

// =============================================================================
// 7. INDIGO THEME (Deep Navy / Midnight) - Hue: ~238°
// =============================================================================
  ThemePreset(
    id: 'indigoTheme',
    label: 'Indigo',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(0, 0.0, 0.0, 0.5),
      background: _hsl(238, 0.35, 0.05),
      foreground: _hsl(238, 0.15, 0.96),
      primary: _hsl(238, 0.80, 0.62),
      primaryForeground: _hsl(238, 1.0, 0.98),
      secondary: _hsl(238, 0.25, 0.14),
      secondaryForeground: _hsl(238, 0.15, 0.96),
      muted: _hsl(238, 0.25, 0.14),
      mutedForeground: _hsl(238, 0.15, 0.65),
      destructive: _hsl(0, 0.70, 0.50),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.70, 0.50),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(238, 0.30, 0.09),
      border: _hsl(238, 0.20, 0.18),
      extensions: const [AppColors()],
    ),
  ),

// =============================================================================
// 8. VIOLET THEME (Amethyst / Royal Purple) - Hue: ~270°
// =============================================================================
  ThemePreset(
    id: 'violetTheme',
    label: 'Violet',
    colors: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: _hsl(0, 0.0, 0.0, 0.5),
      background: _hsl(270, 0.35, 0.05),
      foreground: _hsl(270, 0.15, 0.96),
      primary: _hsl(270, 0.78, 0.60),
      primaryForeground: _hsl(270, 1.0, 0.98),
      secondary: _hsl(270, 0.25, 0.14),
      secondaryForeground: _hsl(270, 0.15, 0.96),
      muted: _hsl(270, 0.25, 0.14),
      mutedForeground: _hsl(270, 0.15, 0.65),
      destructive: _hsl(0, 0.70, 0.50),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.70, 0.50),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(270, 0.30, 0.09),
      border: _hsl(270, 0.20, 0.18),
      extensions: const [AppColors()],
    ),
  ),

// =============================================================================
// ADD CUSTOM THEMES
// =============================================================================

];