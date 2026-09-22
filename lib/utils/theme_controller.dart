import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_presets.dart';

class ThemeController extends ValueNotifier<ThemePreset> {
  ThemeController._(super.value);

  static const _key = 'selected_theme';

  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_key);
    final preset = themePresets.firstWhere(
          (p) => p.id == savedId,
      orElse: () => themePresets.first, // fallback if nothing saved or theme was removed
    );
    return ThemeController._(preset);
  }

  Future<void> select(ThemePreset preset) async {
    value = preset; // notifies listeners, so the UI updates immediately
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, preset.id);
  }
}

late final ThemeController themeController;