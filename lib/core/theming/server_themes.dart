import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../jellyfin/jellyfin_controller.dart';
import '../storage/app_defaults.dart';
import '../storage/storage.dart';
import '../../widgets/svg_raster.dart';
import '../../theme/palette.dart';
import 'server_theme_sheet.dart';

export 'server_theme_sheet.dart';

/// How a picture link did when it was last tried.
@immutable
class LinkCheck {
  const LinkCheck.working() : problem = null;
  const LinkCheck.broken(String this.problem);

  /// Why it didn't load ("couldn't reach it", "not found (404)", ...), or null if it did.
  final String? problem;

  bool get broken => problem != null;
}

/// A broken link in a theme: what it's for, its address, and why.
typedef BrokenLink = ({String what, String url, String problem});

/// The signed-in server's branding (Dashboard › General): the themes and defaults in its Custom
/// CSS (see docs/themes.md) and their pictures, its login disclaimer and its splash screen, all
/// saved on the device so they work offline.
///
/// On connecting to a server it reads what was saved for it, then fetches the CSS again and
/// saves the pictures the defaults and the current theme use. Picking a theme saves its
/// pictures; opening the theme picker checks every link ([checkLinks]).
///
/// Pictures are looked up theme first, then defaults, then the app's own (see [logo] and
/// [genrePicture]); a saved copy is used even if its link has stopped working.
class ServerThemes extends ChangeNotifier {
  ServerThemes._();

  /// What the signed-in server's CSS holds (as saved, until it's fetched again).
  ServerThemeSheet sheet = const ServerThemeSheet();

  /// Bumped when [sheet] changes (not on link checks), for the theme controller and the rest
  /// of the settings (the defaults' settings).
  final sheetChanged = ValueNotifier(0);

  /// The defaults' settings, and the theme in use's over those, over assets/defaults.json's.
  void _applyDefaults() => appDefaults.server = {
    ...sheet.defaults.settings,
    ...?sheet.themeNamed(_activeTheme)?.settings,
  };

  /// Bumped when the theme in use changes to one with settings of its own (or from one), so
  /// settings that follow them load again (see main.dart).
  final themeSettingsChanged = ValueNotifier(0);

  /// The server's login disclaimer (shown under signing in), if it has one.
  String? loginDisclaimer;

  /// The server's splash screen, saved on the device, if it has one turned on: shown behind its
  /// sign-in pages (see ServerBackdrop).
  File? get splash {
    final dir = _dir;
    if (dir == null) return null;
    final file = File('${dir.path}/splash');
    return file.existsSync() ? file : null;
  }

  String? _server;
  Directory? _dir; // this server's saved CSS and pictures
  final _links = <String, LinkCheck>{};

  /// The theme in use's name, if it's one of the server's (set by the theme controller). Its
  /// settings apply while it is (see [_applyDefaults]).
  String? get activeTheme => _activeTheme;
  String? _activeTheme;
  set activeTheme(String? name) {
    if (name == _activeTheme) return;
    final had = sheet.themeNamed(_activeTheme)?.settings.isNotEmpty ?? false;
    _activeTheme = name;
    final has = sheet.themeNamed(name)?.settings.isNotEmpty ?? false;
    if (had || has) {
      _applyDefaults();
      themeSettingsChanged.value++;
    }
  }

  /// Opens what's saved for [server] (the one signed in last), before the app's first frame, so
  /// a server theme's colors are there from the start.
  static Future<ServerThemes> load(String? server) async {
    _root = '${(await getApplicationSupportDirectory()).path}/server_themes';
    final themes = ServerThemes._();
    themes._open(server);
    // Someone signing in to another server: its branding at once, before the rest of the app
    // loads their settings (this listens first), so their theme and the logo are right from the
    // start.
    storage.user.addListener(themes._onUser);
    return themes;
  }

  /// Where every server's branding is saved.
  static late final String _root;

  void _onUser() {
    final user = storage.user.value;
    // Signed out: no server's branding, so everything's Chameleon's own defaults again. (A
    // server's sign-in pages still show its branding: see ServerBranding.)
    if (user == null) {
      if (_server != null) _open(null);
      return;
    }
    final server = user.substring(0, user.lastIndexOf('|'));
    if (server != _server) {
      _open(server);
      unawaited(refresh());
    }
  }

  /// Follows the signed-in server from now on.
  void follow() {
    jellyfin.addListener(_onJellyfin);
    _onJellyfin();
  }

  void _onJellyfin() {
    final server = jellyfin.isConnected ? jellyfin.client?.baseUrl : null;
    if (server == null) return;
    if (server != _server) {
      _open(server);
      unawaited(refresh());
    } else if (!_fetched) {
      unawaited(refresh());
    } else if (!identical(jellyfin.genres, _genresLookedFor)) {
      unawaited(_lookInFolders()); // the genres are in (or changed): their pictures in the folders
    }
  }

  bool _fetched = false;

  /// Switches to [server]'s branding: as saved for it, or as its sign-in page just fetched.
  void _open(String? server) {
    _server = server;
    _fetched = false;
    _links.clear();
    _found = {};
    _genresLookedFor = null;
    sheet = const ServerThemeSheet();
    loginDisclaimer = null;
    if (server == null) {
      _dir = null;
      _applyDefaults();
      sheetChanged.value++;
      notifyListeners();
      return;
    }
    final dir = Directory('$_root/${_hash(server)}');
    _dir = dir;
    final saved = File('${dir.path}/custom.css');
    try {
      if (saved.existsSync()) {
        sheet = parseServerThemes(saved.readAsStringSync());
        final found = File('${dir.path}/folders.json');
        if (found.existsSync()) _found = _readFound(found.readAsStringSync());
        final branding = File('${dir.path}/branding.json');
        if (branding.existsSync()) loginDisclaimer = _disclaimerIn(jsonDecode(branding.readAsStringSync()));
      } else if (_brandingsNow[server] case final branding?) {
        // Nothing saved yet (signing in for the first time): what its sign-in page fetched.
        sheet = parseServerThemes((branding['CustomCss'] as String?) ?? '');
        loginDisclaimer = _disclaimerIn(branding);
      }
    } catch (e) {
      debugPrint('Saved server themes: $e');
    }
    _applyDefaults();
      sheetChanged.value++;
    notifyListeners();
  }

  /// Fetches the server's branding again (its CSS, login disclaimer and splash screen), and
  /// saves the pictures the defaults and the current theme use. Kept as it was if the server
  /// can't be reached.
  Future<void> refresh() async {
    final server = _server, dir = _dir;
    if (server == null || dir == null) return;
    List<String> previous; // the current theme's pictures, as it was
    bool splashOn;
    try {
      final res = await http.get(Uri.parse('$server/Branding/Configuration')).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 || server != _server) return;
      final branding = jsonDecode(res.body) as Map<String, dynamic>;
      final css = (branding['CustomCss'] as String?) ?? '';
      _fetched = true;
      await dir.create(recursive: true);
      await File('${dir.path}/custom.css').writeAsString(css);
      await File('${dir.path}/branding.json').writeAsString(res.body);
      previous = sheet.themeNamed(activeTheme)?.urls.toList() ?? const [];
      sheet = parseServerThemes(css);
      loginDisclaimer = _disclaimerIn(branding);
      splashOn = branding['SplashscreenEnabled'] == true;
      _applyDefaults();
      sheetChanged.value++;
      notifyListeners();
    } catch (e) {
      debugPrint('Server branding: $e'); // offline: what was saved
      return;
    }
    await _saveSplash(on: splashOn);
    await _lookInFolders(save: false);
    await _saveAll(_inUse(activeTheme));
    await _tidy(keepAlso: previous);
  }

  /// Every picture the defaults and [theme] use: their own, and what was found in their genre
  /// folders.
  List<String> _inUse(String? theme) {
    final t = sheet.themeNamed(theme);
    return [
      ...sheet.defaults.urls,
      ...?t?.urls,
      for (final folder in [?sheet.defaults.genreFolder, ?t?.genreFolder]) ...?_found[folder]?.values.nonNulls,
    ];
  }

  /// Saves [theme]'s pictures (and the defaults'), when it's picked: looking in its genre folder
  /// first, if it has one.
  Future<void> saveTheme(String name) async {
    await _lookInFolders(save: false, theme: name);
    await _saveAll(_inUse(name));
  }

  // ─── Genre folders ─────────────────────────────────────────────────────────

  /// What's been found in each genre folder (see [genreFolderFiles]): by folder, each genre's
  /// picture address, or null for none there. Saved with the server's branding.
  Map<String, Map<String, String?>> _found = {};

  /// When each folder was last looked through.
  final _lookedAt = <String, DateTime>{};

  /// The genres the folders were last looked through for.
  List<String>? _genresLookedFor;

  /// How long what's found in a folder is trusted before it's looked through again.
  static const _lookAgainAfter = Duration(days: 1);

  static Map<String, Map<String, String?>> _readFound(String json) {
    try {
      return {
        for (final MapEntry(:key, :value) in (jsonDecode(json) as Map<String, dynamic>).entries)
          key: Map<String, String?>.from(value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  /// Looks through the defaults' genre folder and [theme]'s (the current one's) for each of the
  /// server's genres, unless that was done lately for these genres. With [save], saves what it
  /// finds for offline (otherwise the caller does).
  Future<void> _lookInFolders({bool save = true, String? theme}) async {
    final server = _server, dir = _dir;
    final genres = jellyfin.genres;
    if (server == null || dir == null || genres.isEmpty) return;
    _genresLookedFor = genres;
    final folders = {?sheet.defaults.genreFolder, ?sheet.themeNamed(theme ?? activeTheme)?.genreFolder};
    var changed = false;
    for (final folder in folders) {
      final known = _found[folder] ?? {};
      final fresh = _lookedAt[folder] != null && DateTime.now().difference(_lookedAt[folder]!) < _lookAgainAfter;
      final missing = [for (final g in genres) if (!known.containsKey(genreKey(g))) g];
      if (fresh && missing.isEmpty) continue;
      final lookFor = fresh ? missing : genres;
      // A few genres at a time, each trying its names and kinds in order.
      final results = <String, String?>{};
      for (var i = 0; i < lookFor.length; i += 6) {
        final batch = lookFor.skip(i).take(6).toList();
        final hits = await Future.wait([for (final g in batch) _firstThere(genreFolderFiles(folder, g))]);
        for (final (j, g) in batch.indexed) {
          results[genreKey(g)] = hits[j];
        }
        if (server != _server) return;
      }
      _found[folder] = {...known, ...results};
      _lookedAt[folder] = DateTime.now();
      changed = true;
    }
    if (!changed || server != _server) return;
    try {
      await dir.create(recursive: true);
      await File('${dir.path}/folders.json').writeAsString(jsonEncode(_found));
    } catch (e) {
      debugPrint('Genre folders: $e');
    }
    notifyListeners();
    if (save) await _saveAll(_inUse(activeTheme));
  }

  /// The first of [urls] there is a file at, or null.
  static Future<String?> _firstThere(List<String> urls) async {
    for (final url in urls) {
      if (await _isThere(url)) return url;
    }
    return null;
  }

  static Future<bool> _isThere(String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme == 'file') return File(uri.toFilePath()).existsSync();
      final res = await http.head(uri).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Tries every link in the CSS, for the theme picker's warnings.
  Future<void> checkLinks() async {
    final urls = {...sheet.defaults.urls, for (final t in sheet.themes) ...t.urls};
    await Future.wait([for (final url in urls) _fetch(url, save: false)]);
  }

  /// The server whose branding this is (normalized), if any.
  String? get server => _server;

  /// Servers' branding (Dashboard › General) as asked of them for their sign-in pages, which
  /// don't need anyone signed in: one request each.
  static final _brandings = <String, Future<Map<String, dynamic>?>>{};

  /// The same, once they're in.
  static final _brandingsNow = <String, Map<String, dynamic>>{};

  /// Pictures loaded in this run, by address, for showing straight away (an SVG turned into a
  /// picture, say, before it's saved).
  static final _loaded = <String, ImageProvider>{};

  static Future<Map<String, dynamic>?> _brandingOf(String server, {bool fresh = false}) {
    final url = normalizeServerUrl(server);
    if (fresh) {
      _brandings.remove(url);
      _logos.remove(url);
    }
    return _brandings[url] ??= () async {
      try {
        final res = await http.get(Uri.parse('$url/Branding/Configuration')).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) throw http.ClientException('${res.statusCode}');
        return _brandingsNow[url] = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        _brandings.remove(url); // try again next time
        return null;
      }
    }();
  }

  /// [server]'s splash screen, for behind its sign-in pages: the saved copy for the server signed
  /// in to; any other's fetched (if it has one turned on). Null if there's none.
  static Future<ImageProvider?> splashOf(String server) async {
    final url = normalizeServerUrl(server);
    if (url == serverThemes.server) {
      if (serverThemes.splash case final file?) return FileImage(file);
    }
    final branding = await _brandingOf(url);
    return branding?['SplashscreenEnabled'] == true ? NetworkImage('$url/Branding/Splashscreen') : null;
  }

  /// A server's login disclaimer, from its branding (asked of a server you're signing in to; no
  /// need to be signed in). Null if it has none, or can't be reached.
  static Future<String?> disclaimerOf(String server) async => _disclaimerIn(await _brandingOf(server));

  static final _logos = <String, Future<List<ImageProvider>>>{};

  /// Everything [server]'s sign-in pages show of its branding, loaded (see [SignInBranding]).
  /// [fresh] asks the server again rather than reusing what it said earlier in this run.
  static Future<SignInBranding> signInBrandingOf(String server, {bool fresh = false}) async {
    final url = normalizeServerUrl(server);
    final branding = await _brandingOf(url, fresh: fresh);
    // Signed in to it already ("Who's watching?", adding an account): your own theme stays.
    final signedIn = url == serverThemes.server && jellyfin.isConnected;
    final sheet = branding == null
        ? (signedIn ? serverThemes.sheet : const ServerThemeSheet())
        : parseServerThemes((branding['CustomCss'] as String?) ?? '');
    final (logo, splash) = await (logoOf(url), splashOf(url)).wait;
    return SignInBranding(
      logo: logo,
      splash: splash,
      disclaimer: _disclaimerIn(branding) ?? (signedIn ? serverThemes.loginDisclaimer : null),
      colors: signedIn ? null : sheet.themeNamed(sheet.defaults.theme)?.colors,
    );
  }

  /// [server]'s logo for its sign-in pages, as [logo] lists them: for the server signed in to,
  /// its (with your theme's); for any other, its starting theme's and its defaults' (nobody's
  /// signed in to pick another), loaded and ready (an SVG turned into a picture). Empty for
  /// Chameleon's own.
  static Future<List<ImageProvider>> logoOf(String server) {
    final url = normalizeServerUrl(server);
    if (url == serverThemes.server && serverThemes.logo.isNotEmpty) return Future.value(serverThemes.logo);
    return _logos[url] ??= () async {
      final branding = await _brandingOf(url);
      if (branding == null) {
        _logos.remove(url); // try again next time
        return const <ImageProvider>[];
      }
      final sheet = parseServerThemes((branding['CustomCss'] as String?) ?? '');
      final links = [sheet.themeNamed(sheet.defaults.theme)?.logo, sheet.defaults.logo].nonNulls;
      return [
        for (final link in links)
          if ((await _loadPicture(link)).picture case final picture?) _loaded[link] = MemoryImage(picture),
      ];
    }();
  }

  static String? _disclaimerIn(Object? branding) {
    final text = branding is Map ? (branding['LoginDisclaimer'] as String?)?.trim() : null;
    return text == null || text.isEmpty ? null : text;
  }

  /// The widest a saved splash screen is kept: a 1080p screen's.
  static const _splashWidth = 1920;

  /// Saves the server's splash screen ([on]), or forgets it (off). One saved before stays if it
  /// can't be fetched now.
  Future<void> _saveSplash({required bool on}) async {
    final server = _server, dir = _dir;
    if (server == null || dir == null) return;
    final file = File('${dir.path}/splash');
    if (!on) {
      if (file.existsSync()) await file.delete();
      return;
    }
    try {
      final res = await http.get(Uri.parse('$server/Branding/Splashscreen')).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200 || server != _server) return;
      final picture = await _shrink(res.bodyBytes, maxWidth: _splashWidth);
      if (picture != null) await file.writeAsBytes(picture);
    } catch (e) {
      debugPrint('Server splash screen: $e');
    }
  }

  // ─── Looking pictures up ───────────────────────────────────────────────────

  /// The pictures to try for the logo, in order: the current theme's, then the defaults'. Empty
  /// for the app's own.
  List<ImageProvider> get logo =>
      _candidates([sheet.themeNamed(activeTheme)?.logo, sheet.defaults.logo]);

  /// The pictures to try for [genre], in order (as [logo]).
  List<ImageProvider> genrePicture(String genre) {
    final key = genreKey(genre);
    final theme = sheet.themeNamed(activeTheme);
    // The theme's own, then what's in its folder; then the defaults' own, then their folder's.
    return _candidates([
      theme?.genres[key],
      if (theme?.genreFolder case final folder?) _found[folder]?[key],
      sheet.defaults.genres[key],
      if (sheet.defaults.genreFolder case final folder?) _found[folder]?[key],
    ]);
  }

  /// Each address's saved copy if there is one; else the address itself, unless it's known not to
  /// work.
  List<ImageProvider> _candidates(List<String?> urls) => [
    for (final url in urls.nonNulls)
      // Fetched this run first: the saved copy can be an older picture at the same address (and
      // Flutter keeps showing what it decoded from that file, even once it's saved over).
      if (_loaded[url] case final picture?)
        picture
      else if (_savedFile(url) case final file?)
        FileImage(file)
      // (Not an SVG straight from its address: it has to be turned into a picture first.)
      else if (!(_links[url]?.broken ?? false) && !_isSvgLink(url))
        ?_provider(url),
  ];

  static bool _isSvgLink(String url) => Uri.tryParse(url)?.path.toLowerCase().endsWith('.svg') ?? false;

  ImageProvider? _provider(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.scheme == 'file') return FileImage(File(uri.toFilePath()));
    return NetworkImage(url);
  }

  // ─── Warnings ──────────────────────────────────────────────────────────────

  /// A genre folder with none of the server's genres' pictures in it (looked through, at least
  /// once), as a broken link.
  List<BrokenLink> _emptyFolder(String? folder) {
    final found = folder == null ? null : _found[folder];
    if (folder == null || found == null || found.isEmpty || found.values.any((u) => u != null)) return const [];
    return [(what: 'Genre folder', url: folder, problem: 'none of your genres has a picture in it')];
  }

  /// [theme]'s links that don't work (its own and the defaults' it relies on).
  List<BrokenLink> brokenLinks(ServerTheme theme) => [
    ..._emptyFolder(theme.genreFolder),
    if (theme.logo case final url? when _links[url]?.broken ?? false) (what: 'Logo', url: url, problem: _links[url]!.problem!),
    for (final MapEntry(key: genre, value: url) in theme.genres.entries)
      if (_links[url]?.broken ?? false) (what: 'Genre: $genre', url: url, problem: _links[url]!.problem!),
  ];

  /// The defaults' links that don't work.
  List<BrokenLink> get brokenDefaults {
    final d = sheet.defaults;
    return [
      ..._emptyFolder(d.genreFolder),
      if (d.logo case final url? when _links[url]?.broken ?? false) (what: 'Logo', url: url, problem: _links[url]!.problem!),
      for (final MapEntry(key: genre, value: url) in d.genres.entries)
        if (_links[url]?.broken ?? false) (what: 'Genre: $genre', url: url, problem: _links[url]!.problem!),
    ];
  }

  // ─── Saving pictures ───────────────────────────────────────────────────────

  /// The widest a saved picture is kept: about the most any is drawn.
  static const _maxWidth = 1000;

  Future<void> _saveAll(Iterable<String> urls) async {
    await Future.wait([for (final url in urls.toSet()) _fetch(url, save: true)]);
  }

  /// Loads [url], noting whether it works, and with [save] keeps a copy (no wider than
  /// [_maxWidth]). A copy saved before stays if it doesn't load now.
  Future<void> _fetch(String url, {required bool save}) async {
    final server = _server, dir = _dir;
    final (:picture, :problem) = await _loadPicture(url);
    if (picture != null) _loaded[url] = MemoryImage(picture);
    if (picture != null && save && dir != null && server == _server) {
      try {
        await Directory('${dir.path}/pictures').create(recursive: true);
        await File(_path(dir, url)).writeAsBytes(picture);
      } catch (e) {
        debugPrint('Saving a theme picture: $e');
      }
    }
    if (server != _server) return;
    _links[url] = problem == null ? const LinkCheck.working() : LinkCheck.broken(problem);
    notifyListeners();
  }

  /// The picture at [url], ready to show: an SVG turned into one, and no wider than
  /// [_maxWidth]. Or why it can't be had.
  static Future<({Uint8List? picture, String? problem})> _loadPicture(String url) async {
    try {
      Uint8List bytes;
      final uri = Uri.parse(url);
      if (uri.scheme == 'file') {
        final file = File(uri.toFilePath());
        if (!file.existsSync()) return (picture: null, problem: "the file isn't on this device");
        bytes = await file.readAsBytes();
      } else if (uri.scheme == 'http' || uri.scheme == 'https') {
        final res = await http.get(uri).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) {
          return (
            picture: null,
            problem: res.statusCode == 404 ? 'not found (404)' : 'the server answered ${res.statusCode}',
          );
        }
        bytes = res.bodyBytes;
      } else {
        return (picture: null, problem: "it isn't a web address or a file");
      }
      // An SVG becomes a picture here (see SvgRaster), as wide as any is kept.
      if (SvgRaster.looksLikeSvg(bytes)) {
        final png = await SvgRaster.toPng(utf8.decode(bytes, allowMalformed: true), width: _maxWidth.toDouble());
        if (png == null) return (picture: null, problem: "the SVG couldn't be read");
        bytes = png;
      }
      final picture = await _shrink(bytes);
      return picture == null
          ? (picture: null, problem: "it isn't a picture Chameleon can show (PNG, JPEG, WebP, GIF or SVG)")
          : (picture: picture, problem: null);
    } on TimeoutException {
      return (picture: null, problem: "couldn't reach it (it took too long)");
    } on SocketException {
      return (picture: null, problem: "couldn't reach it");
    } catch (e) {
      return (picture: null, problem: "couldn't load it ($e)");
    }
  }

  /// [bytes] as a picture no wider than [_maxWidth] (as PNG if it had to be shrunk), or null if
  /// it isn't a picture.
  static Future<Uint8List?> _shrink(Uint8List bytes, {int maxWidth = _maxWidth}) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      if (width <= maxWidth) {
        descriptor.dispose();
        buffer.dispose();
        return bytes;
      }
      final codec = await descriptor.instantiateCodec(targetWidth: maxWidth);
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      return png?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  File? _savedFile(String url) {
    final dir = _dir;
    if (dir == null) return null;
    final file = File(_path(dir, url));
    return file.existsSync() ? file : null;
  }

  static String _path(Directory dir, String url) => '${dir.path}/pictures/${_hash(url)}';

  /// Deletes saved pictures the CSS no longer mentions, except the current theme's ([keepAlso]:
  /// as it was, even if it's gone from the CSS).
  Future<void> _tidy({List<String> keepAlso = const []}) async {
    final dir = _dir;
    if (dir == null) return;
    final keep = {
      for (final url in [
        ...sheet.defaults.urls,
        for (final t in sheet.themes) ...t.urls,
        for (final found in _found.values) ...found.values.nonNulls,
        ...keepAlso,
      ])
        _hash(url),
    };
    final pictures = Directory('${dir.path}/pictures');
    if (!pictures.existsSync()) return;
    await for (final entry in pictures.list()) {
      final name = entry.uri.pathSegments.last;
      if (!keep.contains(name)) await entry.delete();
    }
  }

  /// A short, stable name for [text] (64-bit FNV-1a, as hex).
  static String _hash(String text) {
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final b in text.codeUnits) {
      h = ((h ^ BigInt.from(b)) * prime) & mask;
    }
    return h.toRadixString(16);
  }
}

/// What a server's sign-in pages show of its branding: its logo, splash screen, login disclaimer,
/// and its starting theme's colors (unless you're signed in to it, when yours stay).
@immutable
class SignInBranding {
  const SignInBranding({this.logo = const [], this.splash, this.disclaimer, this.colors});

  /// Chameleon's own: no server yet.
  static const none = SignInBranding();

  final List<ImageProvider> logo;
  final ImageProvider? splash;
  final String? disclaimer;
  final Palette? colors;
}

extension on ServerDefaults {
  Iterable<String> get urls => [?logo, ...genres.values];
}

late final ServerThemes serverThemes;
