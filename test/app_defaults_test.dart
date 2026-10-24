import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// assets/defaults.json is hand-edited, so make sure it still reads and has its sections.
void main() {
  test('defaults.json is valid and has every section', () {
    final json = jsonDecode(File('assets/defaults.json').readAsStringSync()) as Map<String, dynamic>;
    expect(json['appearance'], isA<Map>());
    expect(json['home'], isA<List>());
    expect(json['playback'], isA<Map>());
    expect(json['screensaver'], isA<Map>());
    expect((json['appearance'] as Map)['bottomBar'], hasLength(lessThanOrEqualTo(4)));
  });
}
