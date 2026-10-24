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

  /// A section, e.g. 'playback', as written in the file (empty if it isn't there).
  Map<String, dynamic> section(String name) => switch (_json[name]) {
    final Map<String, dynamic> m => m,
    _ => const {},
  };

  /// A string from the 'appearance' section.
  String? appearance(String key) => switch (section('appearance')[key]) {
    final String s => s,
    _ => null,
  };

  /// A list of strings: [key] in [sectionName], or a top-level list when [sectionName] is null.
  List<String>? strings(String key, {String? sectionName}) {
    final value = sectionName == null ? _json[key] : section(sectionName)[key];
    return value is List ? [for (final v in value) if (v is String) v] : null;
  }
}
