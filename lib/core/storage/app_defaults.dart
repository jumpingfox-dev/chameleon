import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The app's default settings, from assets/defaults.json (see docs/defaults.md): what anyone
/// gets until they change something in Settings. The values in the code are only a fallback
/// for anything the file leaves out.
///
/// A server can set its own in its Custom CSS ([server], see docs/themes.md), which take
/// precedence over the file's.
final appDefaults = AppDefaults._();

class AppDefaults {
  AppDefaults._();

  Map<String, dynamic> _json = const {};

  /// The signed-in server's defaults, from its Custom CSS: each setting's name (as in the file,
  /// camelCase) and its value as written. Set as its branding is read.
  Map<String, String> server = const {};

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
    // The server's, over the file's.
    for (final MapEntry(:key, :value) in flat.entries.toList()) {
      if (value is Map<String, dynamic>) {
        // A setting that's a map (Playback's "skip"): one value each, as skipIntro, skipRecap, ...
        flat[key] = {
          for (final MapEntry(key: part, value: v) in value.entries)
            part: _fromServer('$key${part[0].toUpperCase()}${part.substring(1)}', v) ?? v,
        };
      } else if (_fromServer(key, value) case final v?) {
        flat[key] = v;
      }
    }
    return flat;
  }

  /// The server's value for [key], read as the same kind as the file's [like] (true or false, a
  /// number, a list or text), or null if it doesn't set one.
  Object? _fromServer(String key, Object? like) {
    final raw = server[key];
    if (raw == null) return null;
    final text = raw.trim().replaceAll(RegExp(r'''^["']|["']$'''), '').trim();
    return switch (like) {
      bool _ => switch (text.toLowerCase()) {
        'true' || 'yes' || 'on' => true,
        'false' || 'no' || 'off' => false,
        _ => null,
      },
      int _ => int.tryParse(text),
      num _ => num.tryParse(text),
      List _ => [
        for (final s in text.split(RegExp(r'[,\s]+')))
          if (s.replaceAll(RegExp(r'''["']'''), '').isNotEmpty) s.replaceAll(RegExp(r'''["']'''), ''),
      ],
      _ => text,
    };
  }

  /// A string from the 'appearance' section (its groups opened up: 'fonts' and so on).
  String? appearance(String key) => switch (settings('appearance')[key] ?? _fromServer(key, '')) {
    final String s => s,
    _ => null,
  };

  /// A list of strings: [key] in [sectionName], or a top-level list when [sectionName] is null.
  List<String>? strings(String key, {String? sectionName}) {
    final value = _fromServer(key, const <String>[]) ?? (sectionName == null ? _json[key] : section(sectionName)[key]);
    return value is List ? [for (final v in value) if (v is String) v] : null;
  }
}
