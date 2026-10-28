import 'package:chameleon/core/theming/server_theme_sheet.dart';
import 'package:flutter/material.dart' show Brightness, Color;
import 'package:flutter_test/flutter_test.dart';

const _css = '''
/* Someone's web theme, which Chameleon leaves alone */
.skinHeader { background: #000 !important; }

/* chameleon-defaults
   version: 1 */
.chameleon-defaults {
  --theme: "House";
  --logo: url("https://example.com/logo.png");
  --genre-action: url(https://example.com/action.jpg);
  --genre-Science-Fiction: url('file:///sdcard/sci-fi.png');
}

/* chameleon-theme: House
   author: jflores
   version: 1 */
.chameleon-theme[data-name="House"] {
  --seed: 270-280-8-1;
  --accent: #7c4dff;
  --brightness: light;
  --primary-foreground: #ffffff;
  --genre-horror: url("http://192.168.4.2/horror.jpg");
  --card: not-a-color;
}

.chameleon-theme[data-name='Plain'] { --background: hsl(220, 20%, 8%); }
''';

void main() {
  final sheet = parseServerThemes(_css);

  test('the defaults: starting theme, logo and genre pictures', () {
    expect(sheet.defaults.theme, 'House');
    expect(sheet.defaults.logo, 'https://example.com/logo.png');
    expect(sheet.defaults.genres, {
      'action': 'https://example.com/action.jpg',
      'science-fiction': 'file:///sdcard/sci-fi.png',
    });
    expect(sheet.missingDefaultTheme, isFalse);
  });

  test('themes: name, author, colors, pictures and what couldn\'t be read', () {
    expect(sheet.themes.map((t) => t.name), ['House', 'Plain']);
    final house = sheet.themeNamed('House')!;
    expect(house.author, 'jflores');
    expect(house.id, 'server:House');
    expect(house.colors.primary, const Color(0xFF7C4DFF));
    expect(house.colors.primaryForeground, const Color(0xFFFFFFFF));
    expect(house.colors.brightness, Brightness.light);
    expect(house.genres, {'horror': 'http://192.168.4.2/horror.jpg'});
    expect(house.problems, hasLength(1));
    expect(sheet.themeNamed('Plain')!.author, isNull);
  });

  test('seeds with or without padded hues', () {
    expect(parseServerThemes('.chameleon-theme[data-name="A"] { --seed: 150-20-8-2; }').themes.single.problems, isEmpty);
    expect(parseServerThemes('.chameleon-theme[data-name="A"] { --seed: 15002082; }').themes.single.problems, isEmpty);
    expect(parseServerThemes('.chameleon-theme[data-name="A"] { --seed: 400-20-8-2; }').themes.single.problems, hasLength(1));
  });

  test("the defaults' settings, by their names in defaults.json", () {
    final d = parseServerThemes('''
      .chameleon-defaults {
        --theme: "House";
        --heading-font: "Outfit";
        --bottom-bar: home, search, settings;
        --autoplay-next: false;
        --skip-intro: auto;
      }
    ''').defaults;
    expect(d.settings, {
      'headingFont': '"Outfit"',
      'bottomBar': 'home, search, settings',
      'autoplayNext': 'false',
      'skipIntro': 'auto',
    });
  });

  test('genre names become keys', () {
    expect(genreKey('Science Fiction'), 'science-fiction');
    expect(genreKey('Talk-Show'), 'talk-show');
    expect(genreKey('Action & Adventure'), 'action-adventure');
  });

  test('nothing for Chameleon, or a missing starting theme', () {
    expect(parseServerThemes('.skinHeader { color: red; }').isEmpty, isTrue);
    expect(parseServerThemes('.chameleon-defaults { --theme: "Gone"; }').missingDefaultTheme, isTrue);
  });
}
