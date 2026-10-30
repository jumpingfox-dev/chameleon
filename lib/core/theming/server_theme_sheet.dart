import 'package:material_ui/material_ui.dart';

import '../../theme/custom_colors.dart';
import '../../theme/palette.dart';
import '../../theme/theme_presets.dart';

// Themes and defaults written in a server's Custom CSS (see docs/themes.md).

/// The server's defaults: its logo, its genre pictures, and the theme people start on.
@immutable
class ServerDefaults {
  const ServerDefaults({this.theme, this.logo, this.genres = const {}, this.genreFolder, this.settings = const {}});

  /// The starting theme's name.
  final String? theme;

  /// Picture addresses, as written.
  final String? logo;
  final Map<String, String> genres; // by genre key (see genreKey)

  /// A folder of genre pictures, named after the genres (see [genreFolderFiles]).
  final String? genreFolder;

  /// Settings' defaults (as in assets/defaults.json), by their name there (camelCase, from
  /// `--heading-font` and so on), values as written. See AppDefaults.server.
  final Map<String, String> settings;

  bool get isEmpty => theme == null && logo == null && genres.isEmpty && genreFolder == null && settings.isEmpty;
}

/// One theme: its colors, and maybe its own logo, genre pictures and settings.
@immutable
class ServerTheme {
  const ServerTheme({
    required this.name,
    required this.colors,
    this.author,
    this.logo,
    this.genres = const {},
    this.genreFolder,
    this.settings = const {},
    this.problems = const [],
  });

  final String name;
  final String? author;
  final Palette colors;
  final String? logo;
  final Map<String, String> genres;

  /// A folder of genre pictures, named after the genres (see [genreFolderFiles]).
  final String? genreFolder;

  /// Its looks ([themeLookSettings]: fonts, icons, genre cards), as [ServerDefaults.settings]
  /// has them. Picking the theme makes them yours (see ServerThemeLooks).
  final Map<String, String> settings;

  /// What in it couldn't be read (a color that isn't one, say), for the theme picker.
  final List<String> problems;

  /// Its id among the app's themes.
  String get id => 'server:$name';

  /// Every picture address in it.
  Iterable<String> get urls => [?logo, ...genres.values];
}

/// What a server's CSS holds for Chameleon.
@immutable
class ServerThemeSheet {
  const ServerThemeSheet({this.defaults = const ServerDefaults(), this.themes = const []});

  final ServerDefaults defaults;
  final List<ServerTheme> themes;

  bool get isEmpty => defaults.isEmpty && themes.isEmpty;

  ServerTheme? themeNamed(String? name) => themes.where((t) => t.name == name).firstOrNull;

  /// The defaults name a starting theme that isn't here.
  bool get missingDefaultTheme => defaults.theme != null && themeNamed(defaults.theme) == null;
}

/// The addresses to look for [genre]'s picture at in [folder], in order: named by its key
/// (`science-fiction.png`), then by its name as it is (`Science Fiction.png`), as each kind of
/// picture.
List<String> genreFolderFiles(String folder, String genre) {
  final base = folder.endsWith('/') ? folder : '$folder/';
  return [
    for (final name in {genreKey(genre), genre})
      for (final ext in const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'svg']) '$base${Uri.encodeComponent(name)}.$ext',
  ];
}

/// How a genre's name is written in `--genre-<key>`: lower case, anything but letters and
/// digits as `-`. "Science Fiction" is `science-fiction`.
String genreKey(String genre) =>
    genre.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

/// The settings a theme can set: how the app looks. Everything else (playback, subtitles, Home's
/// sections...) belongs in the defaults, for everyone on the server whatever their theme.
const themeLookSettings = {'headingFont', 'bodyFont', 'icons', 'genreCards'};

final _comment = RegExp(r'/\*.*?\*/', dotAll: true);
final _rule = RegExp(r'([^{}]+)\{([^{}]*)\}');
final _themeSelector = RegExp(r'''\.chameleon-theme\s*\[\s*data-name\s*=\s*(["'])(.*?)\1\s*\]''');
final _declaration = RegExp(r'--([a-zA-Z0-9-]+)\s*:\s*([^;]*)');
final _url = RegExp(r'''^url\(\s*(["']?)(.*?)\1\s*\)$''');

/// Reads the defaults and themes from [css], ignoring everything else in it.
ServerThemeSheet parseServerThemes(String css) {
  // Authors, from each theme's comment ("chameleon-theme: Name" then "author: ...").
  final authors = <String, String>{};
  for (final c in _comment.allMatches(css)) {
    final text = c.group(0)!;
    final name = RegExp(r'chameleon-theme:\s*(.+)').firstMatch(text)?.group(1)?.trim();
    final author = RegExp(r'author:\s*(.+)').firstMatch(text)?.group(1)?.trim();
    if (name != null && author != null) authors[name.replaceAll(RegExp(r'\s*\*/$'), '')] = author;
  }

  var defaults = const ServerDefaults();
  final themes = <ServerTheme>[];
  for (final rule in _rule.allMatches(css.replaceAll(_comment, ' '))) {
    final selector = rule.group(1)!.trim();
    final props = {
      for (final d in _declaration.allMatches(rule.group(2)!)) d.group(1)!.toLowerCase(): d.group(2)!.trim(),
    };
    if (selector == '.chameleon-defaults') {
      defaults = ServerDefaults(
        theme: _string(props['theme']),
        logo: _link(props['logo']),
        genres: _genres(props),
        genreFolder: _link(props['genre-folder']),
        settings: _settings(props, const {'theme'}),
      );
    } else if (_themeSelector.firstMatch(selector) case final match?) {
      final name = match.group(2)!.trim();
      if (name.isEmpty || themes.any((t) => t.name == name)) continue; // the first of a name wins
      final (colors, problems) = _colors(props);
      final settings = _settings(props, {'seed', 'brightness', ..._colorNames});
      for (final key in settings.keys.where((k) => !themeLookSettings.contains(k))) {
        problems.add('--${_kebab(key)} belongs in .chameleon-defaults, not a theme');
      }
      themes.add(
        ServerTheme(
          name: name,
          author: authors[name],
          colors: colors,
          logo: _link(props['logo']),
          genres: _genres(props),
          genreFolder: _link(props['genre-folder']),
          settings: {
            for (final MapEntry(:key, :value) in settings.entries)
              if (themeLookSettings.contains(key)) key: value,
          },
          problems: problems,
        ),
      );
    }
  }
  return ServerThemeSheet(defaults: defaults, themes: themes);
}

/// The settings in [props], by their names in assets/defaults.json (camelCase, from
/// `--heading-font` and so on): everything but pictures and [skip].
Map<String, String> _settings(Map<String, String> props, Set<String> skip) => {
  for (final MapEntry(:key, :value) in props.entries)
    if (key != 'logo' && !skip.contains(key) && (!key.startsWith('genre-') || key == 'genre-cards'))
      key.replaceAllMapped(RegExp('-([a-z0-9])'), (m) => m[1]!.toUpperCase()): value,
};

/// A setting's name as it's written in CSS: `headingFont` is `heading-font`.
String _kebab(String name) => name.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');

/// The color tokens' names in CSS (primary-foreground for primaryForeground), and what they set.
final _colorTokens = {
  for (final key in colorTokens.keys) key.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m[0]!.toLowerCase()}'): key,
  'accent': 'primary',
};
Iterable<String> get _colorNames => _colorTokens.keys;

/// `"text"`, `'text'` or `text`.
String? _string(String? value) {
  if (value == null) return null;
  final unquoted = value.replaceAll(RegExp(r'''^["']|["']$'''), '').trim();
  return unquoted.isEmpty ? null : unquoted;
}

/// `url("...")`, `url(...)`, or a bare address.
String? _link(String? value) {
  if (value == null) return null;
  final url = _url.firstMatch(value)?.group(2) ?? _string(value);
  return url == null || url.trim().isEmpty ? null : url.trim();
}

Map<String, String> _genres(Map<String, String> props) => {
  for (final MapEntry(:key, :value) in props.entries)
    if (key.startsWith('genre-') && key != 'genre-folder' && key != 'genre-cards') genreKey(key.substring(6)): ?_link(value),
};

/// The theme's colors: its seed's (or the Default theme's), with its own on top.
(Palette, List<String>) _colors(Map<String, String> props) {
  final problems = <String>[];
  var colors = themePresets.first.colors;
  if (props['seed'] case final seed?) {
    final parsed = ThemeSeed.parse(_string(seed) ?? '');
    if (parsed == null) {
      problems.add('--seed "$seed" isn\'t a seed code');
    } else {
      colors = generateColors(parsed);
    }
  }
  switch (_string(props['brightness'])) {
    case null:
      break;
    case 'light':
      colors = withBrightness(colors, true);
    case 'dark':
      colors = withBrightness(colors, false);
    case final other:
      problems.add('--brightness "$other" should be light or dark');
  }
  for (final MapEntry(:key, :value) in props.entries) {
    final token = _colorTokens[key];
    if (token == null) continue;
    final color = parseColor(_string(value) ?? '');
    if (color == null) {
      problems.add('--$key "$value" isn\'t a color');
    } else {
      colors = colorTokens[token]!.set(colors, color);
    }
  }
  return (colors, problems);
}
