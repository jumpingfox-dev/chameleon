import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// assets/defaults.json is hand-edited, so make sure it still reads and has its sections.
void main() {
  test('defaults.json is valid and has every section', () {
    final json = jsonDecode(File('assets/defaults.json').readAsStringSync()) as Map<String, dynamic>;
    final appearance = json['appearance'] as Map;
    expect(appearance['fonts'], isA<Map>());
    expect(appearance['screensaver'], isA<Map>());
    expect(appearance['bottomBar'], hasLength(lessThanOrEqualTo(4)));
    expect(json['home'], isA<List>());
    final playback = json['playback'] as Map;
    for (final group in ['episodes', 'streamingQuality', 'seekingAndResuming', 'subtitles', 'audio', 'video', 'previews']) {
      expect(playback[group], isA<Map>(), reason: 'playback.$group');
    }
  });
}
