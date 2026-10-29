import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/storage/storage.dart';
import 'home_layout.dart';

/// How each of Home's sections is set up (a row's cog while editing Home), per person.
///
/// Settings are kept by section type, except for the types you can add more than once
/// (Collection, Genre), which are kept per row ([keyFor]).
class SectionSettings extends ChangeNotifier {
  SectionSettings() {
    reload();
  }

  static const _key = 'home_sections';

  Map<String, Map<String, dynamic>> _all = {};

  /// Loads what's saved for whoever is signed in now.
  void reload() {
    try {
      final raw = storage.getString(_key);
      _all = raw == null
          ? {}
          : {
              for (final MapEntry(:key, :value) in (jsonDecode(raw) as Map<String, dynamic>).entries)
                key: Map<String, dynamic>.from(value as Map),
            };
    } catch (_) {
      _all = {};
    }
    notifyListeners();
  }

  /// Where [module]'s settings are kept: its type's, or for a type that can be added more than
  /// once, its own.
  static String keyFor(HomeModule module) => module.type.allowsMultiple ? module.id : module.type.name;

  /// [key]'s settings.
  SectionOptions of(HomeModuleType type, String key) => SectionOptions._(this, type, key);

  /// [module]'s settings.
  SectionOptions forModule(HomeModule module) => of(module.type, keyFor(module));

  Object? _get(String key, String name) => _all[key]?[name];

  Future<void> _set(String key, String name, Object? value) async {
    final section = _all.putIfAbsent(key, () => {});
    if (value == null) {
      section.remove(name);
    } else {
      section[name] = value;
    }
    notifyListeners();
    await storage.setString(_key, jsonEncode(_all));
  }

  /// Forgets a row's settings (it's been removed from Home).
  Future<void> forget(String key) async {
    if (_all.remove(key) == null) return;
    notifyListeners();
    await storage.setString(_key, jsonEncode(_all));
  }

  /// Everything set for [key], to tell when a section's content needs loading again.
  String signature(String key) => jsonEncode(_all[key] ?? const {});
}

/// What Featured shows.
enum FeaturedKinds {
  all('Movies, shows and collections'),
  movies('Movies'),
  shows('Shows'),
  collections('Collections');

  const FeaturedKinds(this.label);
  final String label;
}

/// How the episode under a card in Continue Watching or Next Up is named, under the show's name.
enum EpisodeTitleStyle {
  both('S1:E5 · Episode name'),
  code('S1:E5'),
  name('Episode name');

  const EpisodeTitleStyle(this.label);
  final String label;
}

/// How My Media's and the Genres section's cards look.
enum CardLook {
  pictures('Jellyfin pictures'),
  icons('Icons');

  const CardLook(this.label);
  final String label;
}

/// Which genres the Genres section shows (when it isn't showing them all).
enum GenrePick {
  random('Random'),
  chosen('Chosen');

  const GenrePick(this.label);
  final String label;
}

/// The order Favorites shows things in.
enum FavoritesSort {
  random('Random', 'Random', false),
  name('Name', 'SortName', false),
  added('Date added', 'DateCreated', true),
  released('Release date', 'PremiereDate', true);

  const FavoritesSort(this.label, this.key, this.descending);
  final String label;
  final String key; // Jellyfin's SortBy
  final bool descending;
}

/// What Because You Watched is based on.
enum BecauseBasis {
  last('The last thing you watched'),
  random('Something you watched lately');

  const BecauseBasis(this.label);
  final String label;
}

/// One section's (or row's) settings, read with their defaults, and changed with [set].
class SectionOptions {
  const SectionOptions._(this._settings, this.type, this.key);

  final SectionSettings _settings;
  final HomeModuleType type;
  final String key;

  T _read<T>(String name, T fallback) => switch (_settings._get(key, name)) {
    final T value => value,
    _ => fallback,
  };

  E _enum<E extends Enum>(String name, List<E> values, E fallback) =>
      values.asNameMap()[_settings._get(key, name)] ?? fallback;

  Future<void> set(String name, Object? value) =>
      _settings._set(key, name, value is Enum ? value.name : value);

  // ── Every section ──

  /// Its title above it. The banner and Genres speak for themselves, so they start without.
  bool get showTitle =>
      _read('showTitle', !(type == HomeModuleType.carousel || type == HomeModuleType.genres));

  /// How many it shows at most.
  int get limit => _read('limit', switch (type) {
    HomeModuleType.carousel => 8,
    HomeModuleType.collection => 50,
    HomeModuleType.continueWatching || HomeModuleType.nextUp || HomeModuleType.becauseYouWatched => 20,
    _ => 30,
  }).clamp(1, type == HomeModuleType.carousel ? maxFeatured : maxItems);

  /// The most any row shows, whatever's chosen; and the banner's most.
  static const maxItems = 100;
  static const maxFeatured = 10;

  /// The choices for [limit].
  List<int> get limitOptions => type == HomeModuleType.carousel
      ? [for (var n = 1; n <= maxFeatured; n++) n]
      : const [10, 20, 30, 50, 100];

  // ── Featured ──

  FeaturedKinds get featuredKinds => _enum('kinds', FeaturedKinds.values, FeaturedKinds.all);

  /// Seconds on each slide.
  int get featuredSeconds => _read('seconds', 8);
  static const featuredSecondsOptions = [5, 8, 10, 15, 20];

  // ── My Media ──

  CardLook get look => _enum('look', CardLook.values, CardLook.pictures);

  /// My Media and Genres: each card's name under it, as Continue Watching's are.
  bool get cardNames => _read('cardNames', false);

  // ── Genres ──

  /// How many genres: null for all of them.
  int? get genreCount => _settings._get(key, 'genreCount') as int?;

  GenrePick get genrePick => _enum('pick', GenrePick.values, GenrePick.random);

  List<String> get chosenGenres => [
    for (final g in (_settings._get(key, 'chosen') as List?) ?? const []) ?(g is String ? g : null),
  ];

  // ── Continue Watching, Next Up ──

  bool get episodeTitles => _read('episodeTitles', true);
  EpisodeTitleStyle get episodeTitleStyle => _enum('episodeTitleStyle', EpisodeTitleStyle.values, EpisodeTitleStyle.both);

  /// Movies show their name in their thumbnail already, so they start without one.
  bool get movieTitles => _read('movieTitles', false);

  /// Continue Watching: leave out what hasn't been touched in this many days (null: never).
  int? get continueCutoffDays => _settings._get(key, 'cutoffDays') as int?;
  static const continueCutoffOptions = <int?>[null, 30, 90, 180];

  /// Next Up: leave out shows not watched in this many days: 'server' (your Jellyfin account's
  /// "Max days in Next Up"), 'never', or a number.
  Object get nextUpCutoff => _settings._get(key, 'cutoff') ?? 'server';
  static const nextUpCutoffOptions = <Object>['server', 'never', 30, 90, 180, 365];

  /// Next Up: shows you've watched through, again ('server': your Jellyfin account's setting).
  String get nextUpRewatching => _read('rewatching', 'server');
  static const nextUpRewatchingOptions = ['server', 'on', 'off'];

  // ── Favorites ──

  /// Which kinds of favorites, by Jellyfin item type.
  List<String> get favoriteKinds {
    final saved = _settings._get(key, 'kinds');
    if (saved is List) return [for (final k in saved) ?(k is String ? k : null)];
    return const ['Movie', 'Series', 'BoxSet'];
  }

  static const favoriteKindOptions = {
    'Movie': 'Movies',
    'Series': 'Shows',
    'BoxSet': 'Collections',
    'Season': 'Seasons',
    'Episode': 'Episodes',
  };

  /// Favorites: whether [kind] (a Jellyfin item type) is named under its card. Seasons and
  /// episodes are, to start with (their pictures don't say which show); the rest aren't.
  bool favoriteNamed(String kind) => switch ((_settings._get(key, 'names') as Map?)?[kind]) {
    final bool named => named,
    _ => kind == 'Season' || kind == 'Episode',
  };

  Future<void> setFavoriteNamed(String kind, bool named) => _settings._set(key, 'names', {
    ...?(_settings._get(key, 'names') as Map?)?.cast<String, dynamic>(),
    kind: named,
  });

  FavoritesSort get favoritesSort => _enum('sort', FavoritesSort.values, FavoritesSort.random);

  // ── Because You Watched ──

  BecauseBasis get becauseBasis => _enum('basis', BecauseBasis.values, BecauseBasis.last);
}

late final SectionSettings sectionSettings;
