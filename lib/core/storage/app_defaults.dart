import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The app's default settings, from assets/defaults.json (see docs/defaults.md): what anyone
/// gets until they change something in Settings. The values in the code are only a fallback
/// for anything the file leaves out.
final appDefaults = AppDefaults._();

class AppDefaults {
  AppDefaults._();

  Map<String, dynamic> _json = const {};

  /// Call once at startup, before the settings load.
  Future<void> load() async {
    try {
      _json = jsonDecode(await rootBundle.loadString('assets/defaults.json')) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('assets/defaults.json: $e'); // missing or unreadable: the code's own defaults
    }
  }

  /// A section, e.g. 'playback', as written in the file (empty if it isn't there). [path] goes
  /// further in, e.g. ['appearance', 'screensaver'].
  Map<String, dynamic> section(String name, [List<String> path = const []]) {
    Object? value = _json[name];
    for (final key in path) {
      value = value is Map ? value[key] : null;
    }
    return value is Map<String, dynamic> ? value : const {};
  }

  /// A section's settings with its groups (the file is laid out like Settings: Playback's
  /// "episodes", "subtitles", ...) opened up into one level. A map that's a setting's own value
  /// (Playback's "skip") is kept as it is.
  Map<String, dynamic> settings(String name, [List<String> path = const [], Set<String> mapValues = const {}]) {
    final flat = <String, dynamic>{};
    void add(Map<String, dynamic> m) {
      for (final MapEntry(:key, :value) in m.entries) {
        if (value is Map<String, dynamic> && !mapValues.contains(key)) {
          add(value);
        } else {
          flat[key] = value;
        }
      }
    }

    add(section(name, path));
    return flat;
  }

  /// A string from the 'appearance' section (its groups opened up: 'fonts' and so on).
  String? appearance(String key) => switch (settings('appearance')[key]) {
    final String s => s,
    _ => null,
  };

  /// A list of strings: [key] in [sectionName], or a top-level list when [sectionName] is null.
  List<String>? strings(String key, {String? sectionName}) {
    final value = sectionName == null ? _json[key] : section(sectionName)[key];
    return value is List ? [for (final v in value) if (v is String) v] : null;
  }
}
