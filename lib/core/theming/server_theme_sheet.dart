import 'package:material_ui/material_ui.dart';

import '../../theme/custom_colors.dart';
import '../../theme/palette.dart';
import '../../theme/theme_presets.dart';

// Themes and defaults written in a server's Custom CSS (see docs/themes.md).

/// The server's defaults: its logo, its genre pictures, and the theme people start on.
@immutable
class ServerDefaults {
  const ServerDefaults({this.theme, this.logo, this.genres = const {}});

  /// The starting theme's name.
  final String? theme;

  /// Picture addresses, as written.
  final String? logo;
  final Map<String, String> genres; // by genre key (see genreKey)

  bool get isEmpty => theme == null && logo == null && genres.isEmpty;
}

/// One theme: its colors, and maybe its own logo and genre pictures.
@immutable
class ServerTheme {
  const ServerTheme({
    required this.name,
    required this.colors,
    this.author,
    this.logo,
    this.genres = const {},
    this.problems = const [],
  });

  final String name;
  final String? author;
  final Palette colors;
  final String? logo;
  final Map<String, String> genres;

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

/// How a genre's name is written in `--genre-<key>`: lower case, anything but letters and
/// digits as `-`. "Science Fiction" is `science-fiction`.
String genreKey(String genre) =>
    genre.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

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
      );
    } else if (_themeSelector.firstMatch(selector) case final match?) {
      final name = match.group(2)!.trim();
      if (name.isEmpty || themes.any((t) => t.name == name)) continue; // the first of a name wins
      final (colors, problems) = _colors(props);
      themes.add(
        ServerTheme(
          name: name,
          author: authors[name],
          colors: colors,
          logo: _link(props['logo']),
          genres: _genres(props),
          problems: problems,
        ),
      );
    }
  }
  return ServerThemeSheet(defaults: defaults, themes: themes);
}

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
    if (key.startsWith('genre-')) genreKey(key.substring(6)): ?_link(value),
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
  // CSS's kebab-case names for the color tokens (primary-foreground for primaryForeground).
  final tokens = {
    for (final key in colorTokens.keys) key.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m[0]!.toLowerCase()}'): key,
    'accent': 'primary',
  };
  for (final MapEntry(:key, :value) in props.entries) {
    final token = tokens[key];
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
