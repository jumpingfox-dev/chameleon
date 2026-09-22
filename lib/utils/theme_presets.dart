import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/theme.dart';

// Helper shortcut for clean HSL definitions
Color _hsl(double h, double s, double l, [double a = 1.0]) =>
    HSLColor.fromAHSL(a, h, s, l).toColor();

class ThemePreset {
  const ThemePreset({required this.id, required this.label, required this.light, required this.dark});

  final String id;
  final String label;
  final FColors light;
  final FColors dark;
}

final themes = {for (final p in themePresets) p.label: p};

final themePresets = <ThemePreset>[
// =============================================================================
// 0. DEFAULT THEME
// =============================================================================
  ThemePreset(
    id: 'defaultTheme',
    label: 'Default',
    light: FColors(
      brightness: .light,
      systemOverlayStyle: .dark,
      barrier: Color(0x33000000),
      background: Color(0xFFFFFFFF),
      foreground: Color(0xFF0C090C),
      primary: Color(0xFF8200DB),
      primaryForeground: Color(0xFFFAF5FF),
      secondary: Color(0xFFF3F1F3),
      secondaryForeground: Color(0xFF1D161E),
      muted: Color(0xFFF3F1F3),
      mutedForeground: Color(0xFF79697B),
      destructive: Color(0xFFE7000B),
      destructiveForeground: Color(0xFFFAFAFA),
      error: Color(0xFFE7000B),
      errorForeground: Color(0xFFFAFAFA),
      card: Color(0xFFFFFFFF),
      border: Color(0xFFE7E4E7),
      extensions: const [AppColors()],
    ),
    dark: FColors(
      brightness: .dark,
      systemOverlayStyle: .light,
      barrier: Color(0x7A000000),
      background: Color(0xFF0C090C),
      foreground: Color(0xFFFAFAFA),
      primary: Color(0xFF6E11B0),
      primaryForeground: Color(0xFFFAF5FF),
      secondary: Color(0xFF2A212C),
      secondaryForeground: Color(0xFFFAFAFA),
      muted: Color(0xFF2A212C),
      mutedForeground: Color(0xFFA89EA9),
      destructive: Color(0xFFFF6467),
      destructiveForeground: Color(0xFFFAFAFA),
      error: Color(0xFFFF6467),
      errorForeground: Color(0xFFFAFAFA),
      card: Color(0xFF1D161E),
      border: Color(0x1AFFFFFF),
      extensions: const [AppColors()],
    ),
  ),

// =============================================================================
// 1. RED THEME (Ruby / Crimson) - Hue: ~355°
// =============================================================================
  ThemePreset(
    id: 'redTheme',
    label: 'Red',
    light: FColors(
      brightness: .light,
      systemOverlayStyle: .dark,
      barrier: _hsl(0, 0.0, 0.0, 0.2),
      background: _hsl(355, 1.0, 0.99),
      foreground: _hsl(355, 0.50, 0.08),
      primary: _hsl(355, 0.85, 0.48),
      primaryForeground: _hsl(355, 1.0, 0.98),
      secondary: _hsl(355, 0.35, 0.95),
      secondaryForeground: _hsl(355, 0.60, 0.15),
      muted: _hsl(355, 0.30, 0.95),
      mutedForeground: _hsl(355, 0.20, 0.45),
      destructive: _hsl(0, 0.84, 0.60),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.84, 0.60),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(0, 0.0, 1.0),
      border: _hsl(355, 0.25, 0.90),
      extensions: const [AppColors()],
    ),
    dark: FColors(
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
// 2. ORANGE THEME (Amber / Tangerine) - Hue: ~28°
// =============================================================================
  ThemePreset(
    id: 'orangeTheme',
    label: 'Orange',
    light: FColors(
      brightness: .light,
      systemOverlayStyle: .dark,
      barrier: _hsl(0, 0.0, 0.0, 0.2),
      background: _hsl(28, 1.0, 0.99),
      foreground: _hsl(28, 0.50, 0.08),
      primary: _hsl(28, 0.95, 0.48),
      primaryForeground: _hsl(28, 1.0, 0.98),
      secondary: _hsl(28, 0.40, 0.94),
      secondaryForeground: _hsl(28, 0.60, 0.15),
      muted: _hsl(28, 0.30, 0.94),
      mutedForeground: _hsl(28, 0.25, 0.45),
      destructive: _hsl(0, 0.84, 0.60),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.84, 0.60),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(0, 0.0, 1.0),
      border: _hsl(28, 0.30, 0.89),
      extensions: const [AppColors()],
    ),
    dark: FColors(
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
// 3. YELLOW THEME (Gold / Sunburst) - Hue: ~45°
// =============================================================================
  ThemePreset(
    id: 'yellowTheme',
    label: 'Yellow',
    light: FColors(
      brightness: .light,
      systemOverlayStyle: .dark,
      barrier: _hsl(0, 0.0, 0.0, 0.2),
      background: _hsl(45, 1.0, 0.99),
      foreground: _hsl(45, 0.50, 0.08),
      primary: _hsl(45, 0.96, 0.44),
      primaryForeground: _hsl(45, 0.80, 0.08),
      secondary: _hsl(45, 0.40, 0.93),
      secondaryForeground: _hsl(45, 0.60, 0.15),
      muted: _hsl(45, 0.30, 0.94),
      mutedForeground: _hsl(45, 0.25, 0.45),
      destructive: _hsl(0, 0.84, 0.60),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.84, 0.60),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(0, 0.0, 1.0),
      border: _hsl(45, 0.30, 0.88),
      extensions: const [AppColors()],
    ),
    dark: FColors(
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
// 4. GREEN THEME (Emerald / Forest) - Hue: ~152°
// =============================================================================
  ThemePreset(
    id: 'greenTheme',
    label: 'Green',
    light: FColors(
      brightness: .light,
      systemOverlayStyle: .dark,
      barrier: _hsl(0, 0.0, 0.0, 0.2),
      background: _hsl(152, 0.50, 0.99),
      foreground: _hsl(152, 0.50, 0.08),
      primary: _hsl(152, 0.75, 0.36),
      primaryForeground: _hsl(152, 1.0, 0.98),
      secondary: _hsl(152, 0.30, 0.94),
      secondaryForeground: _hsl(152, 0.60, 0.15),
      muted: _hsl(152, 0.25, 0.94),
      mutedForeground: _hsl(152, 0.15, 0.45),
      destructive: _hsl(0, 0.84, 0.60),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.84, 0.60),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(0, 0.0, 1.0),
      border: _hsl(152, 0.20, 0.89),
      extensions: const [AppColors()],
    ),
    dark: FColors(
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
// 5. BLUE THEME (Sapphire / Ocean) - Hue: ~217°
// =============================================================================
  ThemePreset(
    id: 'blueTheme',
    label: 'Blue',
    light: FColors(
      brightness: .light,
      systemOverlayStyle: .dark,
      barrier: _hsl(0, 0.0, 0.0, 0.2),
      background: _hsl(217, 0.60, 0.99),
      foreground: _hsl(217, 0.50, 0.08),
      primary: _hsl(217, 0.90, 0.50),
      primaryForeground: _hsl(217, 1.0, 0.98),
      secondary: _hsl(217, 0.35, 0.95),
      secondaryForeground: _hsl(217, 0.60, 0.15),
      muted: _hsl(217, 0.25, 0.95),
      mutedForeground: _hsl(217, 0.20, 0.45),
      destructive: _hsl(0, 0.84, 0.60),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.84, 0.60),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(0, 0.0, 1.0),
      border: _hsl(217, 0.25, 0.90),
      extensions: const [AppColors()],
    ),
    dark: FColors(
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
// 6. INDIGO THEME (Deep Navy / Midnight) - Hue: ~238°
// =============================================================================
  ThemePreset(
    id: 'indigoTheme',
    label: 'Indigo',
    light: FColors(
      brightness: .light,
      systemOverlayStyle: .dark,
      barrier: _hsl(0, 0.0, 0.0, 0.2),
      background: _hsl(238, 0.50, 0.99),
      foreground: _hsl(238, 0.50, 0.08),
      primary: _hsl(238, 0.82, 0.54),
      primaryForeground: _hsl(238, 1.0, 0.98),
      secondary: _hsl(238, 0.30, 0.95),
      secondaryForeground: _hsl(238, 0.60, 0.15),
      muted: _hsl(238, 0.25, 0.95),
      mutedForeground: _hsl(238, 0.20, 0.45),
      destructive: _hsl(0, 0.84, 0.60),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.84, 0.60),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(0, 0.0, 1.0),
      border: _hsl(238, 0.25, 0.90),
      extensions: const [AppColors()],
    ),
    dark: FColors(
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
// 7. VIOLET THEME (Amethyst / Royal Purple) - Hue: ~270°
// =============================================================================
  ThemePreset(
    id: 'violetTheme',
    label: 'Violet',
    light: FColors(
      brightness: .light,
      systemOverlayStyle: .dark,
      barrier: _hsl(0, 0.0, 0.0, 0.2),
      background: _hsl(270, 0.50, 0.99),
      foreground: _hsl(270, 0.50, 0.08),
      primary: _hsl(270, 0.80, 0.50),
      primaryForeground: _hsl(270, 1.0, 0.98),
      secondary: _hsl(270, 0.30, 0.95),
      secondaryForeground: _hsl(270, 0.60, 0.15),
      muted: _hsl(270, 0.25, 0.95),
      mutedForeground: _hsl(270, 0.20, 0.45),
      destructive: _hsl(0, 0.84, 0.60),
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(0, 0.84, 0.60),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(0, 0.0, 1.0),
      border: _hsl(270, 0.25, 0.90),
      extensions: const [AppColors()],
    ),
    dark: FColors(
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
// 8. PRISM THEME (The Culmination)
// Integrates tokens across the spectrum: Violet primary, Cyan/Teal secondary,
// Amber cards, Emerald borders, and Rose backgrounds.
// =============================================================================
  ThemePreset(
    id: 'prismTheme',
    label: 'Prism',
    light: FColors(
      brightness: .light,
      systemOverlayStyle: .dark,
      barrier: _hsl(270, 0.60, 0.10, 0.25),
      background: _hsl(340, 0.60, 0.99), // Subtle rose hue
      foreground: _hsl(260, 0.40, 0.08), // Deep plum
      primary: _hsl(275, 0.85, 0.52),    // Spectrum violet
      primaryForeground: _hsl(0, 0.0, 1.0),
      secondary: _hsl(175, 0.55, 0.92),  // Cool prism cyan
      secondaryForeground: _hsl(175, 0.70, 0.15),
      muted: _hsl(215, 0.30, 0.94),      // Glacial blue
      mutedForeground: _hsl(220, 0.20, 0.46),
      destructive: _hsl(355, 0.85, 0.55),// Scarlet
      destructiveForeground: _hsl(0, 0.0, 0.98),
      error: _hsl(355, 0.85, 0.55),
      errorForeground: _hsl(0, 0.0, 0.98),
      card: _hsl(45, 0.80, 0.99),        // Warm sun-tinted surface
      border: _hsl(140, 0.30, 0.86),     // Subtle emerald border
      extensions: const [AppColors()],
    ),
    dark: FColors(
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
];