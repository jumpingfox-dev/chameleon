import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/theming/server_themes.dart';
import 'custom_colors.dart';
import 'palette.dart';
import 'theme_presets.dart';
import '../core/storage/storage.dart';
import '../core/storage/app_defaults.dart';

const customThemeId = 'custom';
const defaultSeed = ThemeSeed(270, 280, 8, 1);

class ThemeController extends ValueNotifier<ThemePreset> {
  ThemeController._(super.value, this._custom, this._seed);

  static const _key = 'selected_theme';
  static const _seedKey = 'custom_seed';

  /// A server theme's colors as they were when picked, so it still looks right offline or after
  /// the server drops it.
  static const _serverColorsKey = 'server_theme_colors';
  static const _serverPrefix = 'server:';

  ThemePreset _custom;
  ThemeSeed _seed;

  ThemeSeed get seed => _seed;

  /// Your own theme, from [seed].
  ThemePreset get custom => _custom;

  /// The server's themes (see docs/themes.md): picked under Custom.
  List<ThemePreset> get serverPresets => _serverPresets();

  static List<ThemePreset> _serverPresets() => [
    for (final t in serverThemes.sheet.themes) ThemePreset(id: t.id, label: t.name, colors: t.colors),
  ];

  /// Whether [preset] is one of the server's themes.
  static bool isServerTheme(ThemePreset preset) => preset.id.startsWith(_serverPrefix);

  static ThemePreset _preset(Palette colors) => ThemePreset(id: customThemeId, label: 'Custom', colors: colors);

  static Future<ThemeController> load() async {
    final saved = _readSaved();
    return ThemeController._(saved.selected, saved.custom, saved.seed);
  }

  static ({ThemePreset selected, ThemePreset custom, ThemeSeed seed}) _readSaved() {
    final seed = ThemeSeed.parse(storage.getString(_seedKey) ?? '') ?? defaultSeed;
    final custom = _preset(generateColors(seed));

    // Someone who hasn't picked one themselves starts on the server's default theme, if it names
    // one that's there (ahead of a choice made on this device before themes were per person);
    // else assets/defaults.json's.
    // (It can also name one of Chameleon's: "Ruby", say.)
    final named = serverThemes.sheet.defaults.theme;
    final serverDefault =
        serverThemes.sheet.themeNamed(named)?.id ??
        themePresets.where((p) => p.id == named?.toLowerCase() || p.label.toLowerCase() == named?.toLowerCase()).firstOrNull?.id;
    final savedId =
        storage.getOwnString(_key) ?? serverDefault ?? storage.getString(_key) ?? appDefaults.appearance('theme');
    var selected = [...themePresets, custom, ..._serverPresets()].where((p) => p.id == savedId).firstOrNull;
    // A server theme that isn't in the server's CSS (offline before it's read, or dropped):
    // as it looked when picked.
    if (selected == null && savedId != null && savedId.startsWith(_serverPrefix)) {
      final colors = parseColorIni(storage.getString(_serverColorsKey) ?? '', themePresets.first.colors).colors;
      if (colors != null) {
        selected = ThemePreset(id: savedId, label: savedId.substring(_serverPrefix.length), colors: colors);
      }
    }
    selected ??= themePresets.first;
    serverThemes.activeTheme = isServerTheme(selected) ? selected.id.substring(_serverPrefix.length) : null;
    return (selected: selected, custom: custom, seed: seed);
  }

  /// Loads the theme saved for whoever is signed in now (see Storage.user).
  void reload() {
    final saved = _readSaved();
    _seed = saved.seed;
    _custom = saved.custom;
    value = saved.selected;
  }

  Future<void> select(ThemePreset preset) async {
    final server = isServerTheme(preset);
    serverThemes.activeTheme = server ? preset.label : null;
    value = preset;
    await storage.setString(_key, preset.id);
    if (server) {
      await storage.setString(_serverColorsKey, colorsToIni(preset.colors));
      // The server's CSS read again, in case the theme's changed since: its latest colors (applied
      // as it's read: see main.dart's reloadSettings), and its pictures saved for offline.
      unawaited(serverThemes.refresh());
    }
  }

  /// Your own theme, built from [seed].
  Future<void> applySeed(ThemeSeed seed) async {
    _seed = seed;
    _activate();
    await storage.setString(_seedKey, seed.code);
    await storage.setString(_key, customThemeId);
  }

  void _activate() {
    _custom = _preset(generateColors(_seed));
    value = _custom; // new instance, so listeners always fire
  }
}

late final ThemeController themeController;
