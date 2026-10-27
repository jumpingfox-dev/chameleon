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
  ThemeController._(super.value, this._custom, this._seed, this._customIni, this._advanced);

  static const _key = 'selected_theme';
  static const _seedKey = 'custom_seed';
  static const _iniKey = 'custom_ini';
  static const _advancedKey = 'custom_advanced';

  /// A server theme's colors as they were when picked, so it still looks right offline or after
  /// the server drops it.
  static const _serverColorsKey = 'server_theme_colors';
  static const _serverPrefix = 'server:';

  ThemePreset _custom;
  ThemeSeed _seed;
  String? _customIni;
  bool _advanced;

  ThemeSeed get seed => _seed;
  bool get advanced => _advanced;
  /// Chameleon's themes, the custom one, then the server's (see docs/themes.md).
  List<ThemePreset> get allPresets => [...themePresets, _custom, ..._serverPresets()];

  static List<ThemePreset> _serverPresets() => [
    for (final t in serverThemes.sheet.themes) ThemePreset(id: t.id, label: t.name, colors: t.colors),
  ];

  /// Whether [preset] is one of the server's themes.
  static bool isServerTheme(ThemePreset preset) => preset.id.startsWith(_serverPrefix);

  /// The saved INI, or the current seed written out as INI if none has been saved yet.
  String get customIni => _customIni ?? colorsToIni(generateColors(_seed));

  static Palette _resolve(ThemeSeed seed, String? ini, bool advanced) {
    final seedColors = generateColors(seed);
    if (!advanced || ini == null) return seedColors;
    return parseColorIni(ini, seedColors).colors ?? seedColors;
  }

  static ThemePreset _preset(Palette colors) => ThemePreset(id: customThemeId, label: 'Custom', colors: colors);

  static Future<ThemeController> load() async {
    final saved = _readSaved();
    return ThemeController._(saved.selected, saved.custom, saved.seed, saved.ini, saved.advanced);
  }

  static ({ThemePreset selected, ThemePreset custom, ThemeSeed seed, String? ini, bool advanced}) _readSaved() {
    final seed = ThemeSeed.parse(storage.getString(_seedKey) ?? '') ?? defaultSeed;
    final ini = storage.getString(_iniKey);
    final advanced = storage.getBool(_advancedKey) ?? false;
    final custom = _preset(_resolve(seed, ini, advanced));

    // Someone who hasn't picked one themselves starts on the server's default theme, if it names
    // one that's there (ahead of a choice made on this device before themes were per person);
    // else assets/defaults.json's.
    final serverDefault = serverThemes.sheet.themeNamed(serverThemes.sheet.defaults.theme)?.id;
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
    return (selected: selected, custom: custom, seed: seed, ini: ini, advanced: advanced);
  }

  /// Loads the theme saved for whoever is signed in now (see Storage.user).
  void reload() {
    final saved = _readSaved();
    _seed = saved.seed;
    _customIni = saved.ini;
    _advanced = saved.advanced;
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
      unawaited(serverThemes.saveTheme(preset.label)); // its pictures, for offline
    }
  }

  /// The server's themes changed (read, or fetched again): the current one with its new colors,
  /// or someone new on the server's default.
  void serverThemesChanged() => reload();

  /// Simple mode: build the whole theme from a seed.
  Future<void> applySeed(ThemeSeed seed) async {
    _seed = seed;
    _activate();
    await storage.setString(_seedKey, seed.code);
    await storage.setString(_key, customThemeId);
  }

  /// Switches between the seed steppers and the INI editor.
  Future<void> setAdvanced(bool on) async {
    _advanced = on;
    _activate();
    await storage.setBool(_advancedKey, on);
    await storage.setString(_key, customThemeId);
  }

  /// Advanced mode: applies INI text on top of the current seed. Returns errors, or an empty list.
  Future<List<String>> applyCustomIni(String text) async {
    final result = parseColorIni(text, generateColors(_seed));
    if (result.errors.isNotEmpty) return result.errors;

    _customIni = text;
    _advanced = true;
    _activate();
    await storage.setString(_iniKey, text);
    await storage.setBool(_advancedKey, true);
    await storage.setString(_key, customThemeId);
    return const [];
  }

  void _activate() {
    _custom = _preset(_resolve(_seed, _customIni, _advanced));
    value = _custom; // new instance, so listeners always fire
  }
}

late final ThemeController themeController;
