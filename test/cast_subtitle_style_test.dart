import 'package:chameleon/core/cast/cast_controller.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Google Fonts go to the nearest Cast font family', () {
    expect(castFontFamilyOf('Noto Sans'), TextTrackFontGenericFamily.sansSerif);
    expect(castFontFamilyOf('Plus Jakarta Sans'), TextTrackFontGenericFamily.sansSerif);
    expect(castFontFamilyOf('Noto Serif'), TextTrackFontGenericFamily.serif);
    expect(castFontFamilyOf('Merriweather'), TextTrackFontGenericFamily.serif);
    expect(castFontFamilyOf('Roboto Mono'), TextTrackFontGenericFamily.monospacedSansSerif);
    expect(castFontFamilyOf('Dancing Script'), TextTrackFontGenericFamily.cursive);
    expect(castFontFamilyOf('Comic Neue'), TextTrackFontGenericFamily.casual);
    expect(castFontFamilyOf('Alegreya SC'), TextTrackFontGenericFamily.smallCapitals);
  });
}
