import 'dart:async';
import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/app_icons.dart';
import '../../core/focus/focus_rows.dart';
import 'home_layout.dart';
import 'section_settings.dart';
import 'section_settings_form.dart';
import '../../core/format/item_format.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import '../../core/jellyfin/list_each.dart';
import '../../core/platform/page_insets.dart';
import '../../core/storage/app_cache.dart';
import '../../core/platform/screen_type.dart';
import '../detail/detail_page.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/nav_button.dart';
import '../../widgets/tappable.dart';
import '../library/genres.dart';
import '../library/item_menu.dart';
import '../library/poster_card.dart';
import '../../core/focus/scroll_into_view.dart';
import '../../theme/theme.dart';
import '../../widgets/remote_text_field.dart';
import '../../widgets/title_logo.dart';
import '../../core/theming/server_themes.dart';

// ─── Definitions ─────────────────────────────────────────────────────────────

/// What a section loaded: its items, and optionally a title that replaces the default
/// (e.g. "Because you watched Dune").
class HomeModuleContent {
  const HomeModuleContent(this.items, {this.title, this.more = false, this.anchor, this.signature});

  final List<JellyfinItem> items;
  final String? title;

  /// There may be more to load (it's loaded [HomePage.size] at a time, up to the section's limit).
  final bool more;

  /// What it's built around, kept for loading more (Because You Watched's title).
  final String? anchor;

  /// The section's settings it was loaded with (see SectionSettings.signature): different ones
  /// load it again.
  final String? signature;

  HomeModuleContent copyWith({List<JellyfinItem>? items, bool? more, String? signature}) => HomeModuleContent(
    items ?? this.items,
    title: title,
    more: more ?? this.more,
    anchor: anchor,
    signature: signature ?? this.signature,
  );

  static Object? toJson(HomeModuleContent c) => {
    'items': itemsToJson(c.items),
    'title': c.title,
    'more': c.more,
    'anchor': c.anchor,
    'signature': c.signature,
  };

  static HomeModuleContent fromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return HomeModuleContent(
      itemsFromJson(map['items']),
      title: map['title'] as String?,
      more: map['more'] == true,
      anchor: map['anchor'] as String?,
      signature: map['signature'] as String?,
    );
  }
}

/// Which part of a section to load: [limit] items from [start] on, after [shown] (the ones
/// already there, for random orders, which can't be paged: they're left out instead), around
/// [anchor] (see [HomeModuleContent.anchor]).
class HomePage {
  const HomePage({this.start = 0, this.limit = size, this.shown = const [], this.anchor});

  final int start;
  final int limit;
  final List<JellyfinItem> shown;
  final String? anchor;

  /// How many a section loads at a time, so a big limit never loads a lot at once.
  static const size = 10;

  List<String> get shownIds => [for (final i in shown) i.id];
}

/// Loads part of a section's content. [module] says what it shows (e.g. which collection).
typedef HomeModuleLoader = Future<HomeModuleContent> Function(
    JellyfinClient client,
    HomeModule module,
    HomePage page,
    );

/// What a kind of section shows and how to load it.
class HomeModuleSpec {
  const HomeModuleSpec({
    required this.title,
    required this.description,
    required this.icon,
    required this.load,
    this.view,
  });

  final String title;
  final String description;
  final IconData Function(AppIconSet icons) icon;
  final HomeModuleLoader load;

  /// A fixed default view, or null for posters on phones and thumbnails on wider screens.
  final LibraryView? view;
}

const _moviesAndShows = [JellyfinItemKind.movie, JellyfinItemKind.series];

/// [items] as a page's content: more to come if it came back full.
HomeModuleContent _page(List<JellyfinItem> items, HomePage page, {int? fetched, String? title, String? anchor}) =>
    HomeModuleContent(items, more: (fetched ?? items.length) >= page.limit, title: title, anchor: anchor);

/// Every section's definition. To add a new kind: add it to HomeModuleType, then here.
final homeModuleSpecs = <HomeModuleType, HomeModuleSpec>{
  HomeModuleType.carousel: HomeModuleSpec(
    title: 'Featured',
    description: 'A rotating banner of highlights',
    icon: (i) => i.featured,
    load: _featured,
  ),
  HomeModuleType.myMedia: HomeModuleSpec(
    title: 'My Media',
    description: 'Your libraries, as tiles',
    icon: (i) => i.folder,
    load: (_, _, _) async => const HomeModuleContent([]), // drawn from the libraries, already loaded
  ),
  HomeModuleType.genres: HomeModuleSpec(
    title: 'Genres',
    description: 'Your genres, as tiles',
    icon: (i) => i.genres,
    load: (_, _, _) async => const HomeModuleContent([]), // drawn from the genres, already loaded
  ),
  HomeModuleType.continueWatching: HomeModuleSpec(
    title: 'Continue Watching',
    description: "Movies and episodes you've started",
    icon: (i) => i.continueWatching,
    view: LibraryView.thumbnail,
    load: _continueWatching,
  ),
  HomeModuleType.nextUp: HomeModuleSpec(
    title: 'Next Up',
    description: "The next episode of shows you're watching",
    icon: (i) => i.shows,
    view: LibraryView.thumbnail,
    load: _nextUp,
  ),
  HomeModuleType.favorites: HomeModuleSpec(
    title: 'Favorites',
    description: 'Your favorite movies and shows',
    icon: (i) => i.favorite,
    load: _favorites,
  ),
  HomeModuleType.recentlyAdded: HomeModuleSpec(
    title: 'Recently Added',
    description: 'The newest movies and shows on your server',
    icon: (i) => i.recentlyAdded,
    load: (client, _, page) async {
      // The first ten quickly, a type at a time (see ListEach); after that, together.
      final items = page.start == 0
          ? await client.items.listEach(
              types: _moviesAndShows,
              sortBy: const ['DateCreated'],
              descending: true,
              limit: page.limit,
              fields: const ['RecursiveItemCount'],
            )
          : (await client.items.list(
              enableTotalRecordCount: false,
              includeItemTypes: _moviesAndShows,
              recursive: true,
              sortBy: const ['DateCreated'],
              descending: true,
              startIndex: page.start,
              limit: page.limit,
              fields: const ['RecursiveItemCount'],
            )).items;
      return _page(items, page);
    },
  ),
  HomeModuleType.recentlyAddedMovies: HomeModuleSpec(
    title: 'Recently Added Movies',
    description: 'The newest movies on your server',
    icon: (i) => i.movies,
    load: (client, _, page) async => _page(
      (await client.items.list(
        enableTotalRecordCount: false,
        includeItemTypes: const [JellyfinItemKind.movie],
        recursive: true,
        sortBy: const ['DateCreated'],
        descending: true,
        startIndex: page.start,
        limit: page.limit,
      )).items,
      page,
    ),
  ),
  HomeModuleType.recentlyAddedSeries: HomeModuleSpec(
    title: 'Recently Added Shows',
    description: 'Shows with the newest episodes',
    icon: (i) => i.shows,
    load: (client, _, page) async => _page(
      (await client.items.list(
        enableTotalRecordCount: false,
        includeItemTypes: const [JellyfinItemKind.series],
        recursive: true,
        sortBy: const ['DateLastContentAdded'],
        descending: true,
        startIndex: page.start,
        limit: page.limit,
        fields: const ['RecursiveItemCount'],
      )).items,
      page,
    ),
  ),
  HomeModuleType.suggested: HomeModuleSpec(
    title: 'Suggested For You',
    description: 'Picks based on what you watch',
    icon: (i) => i.suggested,
    load: _suggested,
  ),
  HomeModuleType.becauseYouWatched: HomeModuleSpec(
    title: 'Because You Watched…',
    description: 'More like something you watched',
    icon: (i) => i.becauseYouWatched,
    load: _becauseYouWatched,
  ),
  HomeModuleType.collection: HomeModuleSpec(
    title: 'Collection',
    description: 'The movies in a collection you choose',
    icon: (i) => i.collection,
    load: _collection,
  ),
  HomeModuleType.genre: HomeModuleSpec(
    title: 'Genre',
    description: 'Movies and shows from a genre you choose',
    icon: (i) => i.genres,
    load: _genre,
  ),
};

// ─── Loaders ─────────────────────────────────────────────────────────────────

/// A random handful (as many as set, up to ten) of what's set to be featured that has backdrop
/// art to show off. All at once: there are only a few.
Future<HomeModuleContent> _featured(JellyfinClient client, HomeModule module, HomePage _) async {
  final options = sectionSettings.forModule(module);
  final types = switch (options.featuredKinds) {
    FeaturedKinds.all => [..._moviesAndShows, 'BoxSet'],
    FeaturedKinds.movies => const [JellyfinItemKind.movie],
    FeaturedKinds.shows => const [JellyfinItemKind.series],
    FeaturedKinds.collections => const ['BoxSet'],
  };
  final items = await client.items.listEach(
    types: types,
    sortBy: const ['Random'],
    limit: 30, // more than needed, since some won't have a backdrop
    fields: const ['Overview'],
  );
  final withArt = items
      .where((item) => (item.raw['BackdropImageTags'] as List?)?.isNotEmpty ?? false)
      .take(options.limit)
      .toList();
  return HomeModuleContent(withArt);
}

/// What you're partway through, leaving out what you haven't touched in a while if that's set.
Future<HomeModuleContent> _continueWatching(JellyfinClient client, HomeModule module, HomePage page) async {
  final raw = (await client.items.resume(mediaTypes: const ['Video'], startIndex: page.start, limit: page.limit)).items;
  final days = sectionSettings.forModule(module).continueCutoffDays;
  final since = days == null ? null : DateTime.now().subtract(Duration(days: days));
  final items = [
    for (final item in raw)
      if (since == null ||
          (DateTime.tryParse(((item.raw['UserData'] as Map?)?['LastPlayedDate'] as String?) ?? '')?.isAfter(since) ??
              false))
        item,
  ];
  return _page(items, page, fetched: raw.length);
}

/// Your Jellyfin account's own Next Up settings (as its web app keeps them): how many days back
/// it looks, and whether it offers rewatching. Asked once a session.
Future<({int days, bool rewatching})>? _serverNextUp;

Future<({int days, bool rewatching})> _nextUpPrefs(JellyfinClient client) => _serverNextUp ??= () async {
  try {
    final prefs = await jellyfin.getJson(
      '/DisplayPreferences/usersettings',
      query: {'userId': client.userId!, 'client': 'emby'},
    );
    final custom = (prefs as Map)['CustomPrefs'] as Map? ?? const {};
    return (
      days: int.tryParse('${custom['maxDaysForNextUp'] ?? ''}') ?? 365,
      rewatching: '${custom['enableRewatchingInNextUp']}'.toLowerCase() == 'true',
    );
  } catch (_) {
    _serverNextUp = null; // ask again next time
    return (days: 365, rewatching: false); // Jellyfin's own defaults
  }
}();

/// The next episode of shows you're watching (not ones partway, which are in Continue Watching).
Future<HomeModuleContent> _nextUp(JellyfinClient client, HomeModule module, HomePage page) async {
  final options = sectionSettings.forModule(module);
  final server = (options.nextUpCutoff == 'server' || options.nextUpRewatching == 'server')
      ? await _nextUpPrefs(client)
      : null;
  final days = switch (options.nextUpCutoff) {
    'server' => server!.days,
    final int d => d,
    _ => null, // never
  };
  final rewatching = switch (options.nextUpRewatching) {
    'on' => true,
    'off' => false,
    _ => server!.rewatching,
  };
  final raw = (await client.tvShows.nextUp(
    enableTotalRecordCount: false,
    startIndex: page.start,
    limit: page.limit,
    enableResumable: false, // in-progress episodes are in Continue Watching
    enableRewatching: rewatching,
    nextUpDateCutoff: days == null ? null : DateTime.now().subtract(Duration(days: days)).toUtc().toIso8601String(),
  )).items;
  final hidden = hiddenFromNextUp();
  final items = [
    for (final item in raw)
      if (item.type == JellyfinItemKind.episode && !hidden.contains(item.id)) item,
  ];
  return _page(items, page, fetched: raw.length);
}

/// Your favorites: the kinds and order set.
Future<HomeModuleContent> _favorites(JellyfinClient client, HomeModule module, HomePage page) async {
  final options = sectionSettings.forModule(module);
  final kinds = options.favoriteKinds;
  if (kinds.isEmpty) return const HomeModuleContent([]);
  final sort = options.favoritesSort;
  final random = sort == FavoritesSort.random;
  final items = (await client.items.list(
    enableTotalRecordCount: false,
    filters: const ['IsFavorite'],
    includeItemTypes: kinds,
    recursive: true,
    sortBy: [sort.key, if (!random) 'SortName'],
    descending: sort.descending,
    // A random order can't be paged: what's shown is left out instead.
    startIndex: random ? 0 : page.start,
    excludeItemIds: random ? page.shownIds : const [],
    limit: page.limit,
    fields: const ['RecursiveItemCount'],
  )).items;
  return _page(items, page);
}

/// Jellyfin's suggestions for this user, or a random mix when there isn't enough history yet.
Future<HomeModuleContent> _suggested(JellyfinClient client, HomeModule _, HomePage page) async {
  if (page.anchor != 'random') {
    final items = (await client.suggestions.list(
      enableTotalRecordCount: false,
      mediaType: const ['Video'],
      type: _moviesAndShows,
      startIndex: page.start,
      limit: page.limit,
    )).items;
    if (items.isNotEmpty || page.start > 0) return _page(items, page);
  }
  final items = await client.items.listEach(
    types: _moviesAndShows,
    sortBy: const ['Random'],
    excludeItemIds: page.shownIds,
    limit: page.limit,
    fields: const ['RecursiveItemCount'],
  );
  return _page(items, page, anchor: 'random');
}

/// Titles similar to something you watched (the last thing, or one of the last few): same kind,
/// sharing its genres.
Future<HomeModuleContent> _becauseYouWatched(JellyfinClient client, HomeModule module, HomePage page) async {
  JellyfinItem? baseline;
  if (page.anchor case final id?) {
    baseline = await client.items.byId(id);
  } else {
    final random = sectionSettings.forModule(module).becauseBasis == BecauseBasis.random;
    final recent = (await client.items.list(
      enableTotalRecordCount: false,
      filters: const ['IsPlayed'],
      includeItemTypes: const [JellyfinItemKind.movie, JellyfinItemKind.episode],
      recursive: true,
      sortBy: const ['DatePlayed'],
      descending: true,
      limit: random ? 10 : 1,
    )).items;
    if (recent.isEmpty) return const HomeModuleContent([]);
    final last = random ? recent[math.Random().nextInt(recent.length)] : recent.first;
    final baselineId = last.type == JellyfinItemKind.episode ? last.raw['SeriesId'] as String? : last.id;
    if (baselineId == null) return const HomeModuleContent([]);
    baseline = await client.items.byId(baselineId);
  }
  if (baseline == null) return const HomeModuleContent([]);

  final title = 'Because You Watched ${baseline.name}';
  final genres = ((baseline.raw['Genres'] as List?)?.cast<String>() ?? const <String>[]).take(2).toList();
  if (genres.isEmpty) return HomeModuleContent(const [], title: title, anchor: baseline.id);

  final similar = await client.items.list(
    enableTotalRecordCount: false,
    genres: genres,
    includeItemTypes: [baseline.type == JellyfinItemKind.series ? JellyfinItemKind.series : JellyfinItemKind.movie],
    excludeItemIds: [baseline.id, ...page.shownIds],
    recursive: true,
    sortBy: const ['Random'],
    limit: page.limit,
    fields: const ['RecursiveItemCount'],
  );
  return _page(similar.items, page, title: title, anchor: baseline.id);
}

/// The movies in the chosen collection, in release order.
Future<HomeModuleContent> _collection(JellyfinClient client, HomeModule module, HomePage page) async {
  final id = module.param;
  if (id == null) return const HomeModuleContent([]);
  final items = (await client.items.list(
    enableTotalRecordCount: false,
    parentId: id,
    // Just what's in the collection: a show, not its seasons and every episode as well.
    recursive: false,
    sortBy: const ['ProductionYear', 'SortName'],
    startIndex: page.start,
    limit: page.limit,
    fields: const ['RecursiveItemCount'],
  )).items;
  return _page(items, page, title: module.label);
}

/// A random mix of movies and shows from the chosen genre.
Future<HomeModuleContent> _genre(JellyfinClient client, HomeModule module, HomePage page) async {
  final genre = module.param;
  if (genre == null) return const HomeModuleContent([]);
  final items = await client.items.listEach(
    genres: [genre],
    types: _moviesAndShows,
    sortBy: const ['Random'],
    excludeItemIds: page.shownIds,
    limit: page.limit,
    fields: const ['RecursiveItemCount'],
  );
  return _page(items, page, title: genre);
}

// ─── Cache ───────────────────────────────────────────────────────────────────

/// A section's content in [appCache], by section id (two Genre sections show different things).
/// Saved, so Home opens with what it showed last time and refreshes from there.
String _cacheKey(String moduleId) => 'home:$moduleId';

/// Bumped when Home becomes visible again, so stale sections can refresh.
final homeVisible = ValueNotifier<int>(0);

/// Forgets every section's content, e.g. on sign-out.
void clearHomeCache() => appCache.invalidateWhere((key) => key.startsWith('home:'));

/// Bumped after something's been watched, so the sections that follow your progress reload.
final watchProgressChanged = ValueNotifier<int>(0);

/// After playing something: Continue Watching and Next Up reload, since your progress changed.
/// Everything else keeps what it showed (the random sections especially), so Home looks the
/// same as when you left it.
void refreshWatchProgress() {
  final ids = {
    for (final module in homeLayout.value)
      if (module.type.followsProgress) module.id,
  };
  appCache.invalidateWhere((key) => ids.any((id) => key == _cacheKey(id)));
  watchProgressChanged.value++;
}

extension on HomeModuleType {
  /// Shows what you're partway through or up to next, so it changes as you watch.
  bool get followsProgress => this == HomeModuleType.continueWatching || this == HomeModuleType.nextUp;
}

// ─── Section view ────────────────────────────────────────────────────────────

/// One section on the home screen: its title (with edit controls in edit mode) and its content.
class HomeModuleView extends StatefulWidget {
  const HomeModuleView({
    super.key,
    required this.module,
    required this.editing,
    required this.isFirst,
    required this.isLast,
  });

  final HomeModule module;
  final bool editing;
  final bool isFirst;
  final bool isLast;

  @override
  State<HomeModuleView> createState() => _HomeModuleViewState();
}

class _HomeModuleViewState extends State<HomeModuleView>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  HomeModuleContent? _content;
  String? _error;
  final _rowScroll = ScrollController();

  /// The poster playing its stills, widening to 16:9 for them (and narrowing back after).
  int? _widened;
  late final _widen = AnimationController(vsync: this, duration: _widenDuration)
    ..addListener(_onWidenTick)
    ..addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) setState(() => _widened = null);
    });

  /// Near the screen's right edge, a poster widens to the left instead: the row scrolls along
  /// with it, from [_shiftFrom] by [_shift] in all, so its right edge stays where it is.
  double _shiftFrom = 0;
  double _shift = 0;

  HomeModuleSpec get _spec => homeModuleSpecs[widget.module.type]!;

  /// The section's view: your choice if you've changed it; otherwise its fixed default;
  /// otherwise posters on phones and thumbnails on wider screens.
  LibraryView _viewFor(BuildContext context) =>
      LibraryView.values.asNameMap()[widget.module.view] ??
          _spec.view ??
          (ScreenType.of(context).isPhone
              ? LibraryView.poster
              : LibraryView.thumbnail);

  /// Keeps this section alive when it scrolls off-screen, so it isn't rebuilt and reloaded.
  @override
  bool get wantKeepAlive => true;

  /// This section's settings.
  SectionOptions get _options => sectionSettings.forModule(widget.module);

  /// Its settings as they are now, to tell when they've changed (see HomeModuleContent.signature).
  String get _signature => sectionSettings.signature(widget.module);

  @override
  void initState() {
    super.initState();
    favoritesChanged.addListener(_onFavorites);
    homeVisible.addListener(_refreshIfStale);
    watchProgressChanged.addListener(_onWatched);
    sectionSettings.addListener(_onSettings);
    _rowScroll.addListener(_onRowScroll);

    final cached = appCache.peek(_cacheKey(widget.module.id), fromJson: HomeModuleContent.fromJson);
    // Loaded with other settings: not shown, loaded again.
    _content = cached?.signature == _signature ? cached : null;
    if (_content == null || !_fresh) _load();
  }

  @override
  void dispose() {
    favoritesChanged.removeListener(_onFavorites);
    homeVisible.removeListener(_refreshIfStale);
    watchProgressChanged.removeListener(_onWatched);
    sectionSettings.removeListener(_onSettings);
    _widen.dispose();
    _rowScroll.dispose();
    super.dispose();
  }

  void _onWatched() {
    if (widget.module.type.followsProgress) _load();
  }

  /// A favorite added or removed: just Favorites shows it now. The rest keep what they have
  /// until they're due (see [_fresh]).
  void _onFavorites() {
    if (widget.module.type == HomeModuleType.favorites) _load();
  }

  /// How long Home keeps what it's showing before asking again: so it stays put while you
  /// come and go, rather than changing under you.
  static const _keepFor = Duration(minutes: 20);

  bool get _fresh => appCache.isFresh(_cacheKey(widget.module.id), within: _keepFor);

  void _refreshIfStale() {
    if (!_fresh) _load();
  }

  /// Its settings changed: loaded again with them (just redrawn, for those that only change how
  /// it looks).
  void _onSettings() {
    if (!mounted) return;
    if (_content != null && _content!.signature != _signature) {
      _load();
    } else {
      setState(() {});
    }
  }

  /// The first [HomePage.size] (or fewer, if it's set to show fewer).
  Future<void> _load() async {
    final client = jellyfin.client;
    if (client == null) return;
    final signature = _signature;
    final limit = _options.limit;
    try {
      final first = await _spec.load(client, widget.module, HomePage(limit: math.min(HomePage.size, limit)));
      final content = first.copyWith(
        items: first.items.take(limit).toList(),
        more: first.more && first.items.length < limit,
        signature: signature,
      );
      appCache.put(_cacheKey(widget.module.id), content, toJson: HomeModuleContent.toJson);
      if (mounted) {
        setState(() {
          _content = content;
          _error = null;
        });
      }
    } on JellyfinException catch (e) {
      if (mounted && _content == null) setState(() => _error = describeJellyfinError(e));
    }
  }

  bool _loadingMore = false;

  /// Near the row's end: the next [HomePage.size], up to its limit.
  void _onRowScroll() {
    if (!_rowScroll.hasClients || _rowScroll.position.extentAfter > 600) return;
    _loadMore();
  }

  Future<void> _loadMore() async {
    final client = jellyfin.client;
    final content = _content;
    if (client == null || content == null || !content.more || _loadingMore) return;
    final limit = _options.limit;
    final have = content.items.length;
    if (have >= limit) return;
    _loadingMore = true;
    try {
      final next = await _spec.load(
        client,
        widget.module,
        HomePage(start: have, limit: math.min(HomePage.size, limit - have), shown: content.items, anchor: content.anchor),
      );
      if (!mounted || !identical(content, _content)) return; // loaded again meanwhile
      final ids = {for (final i in content.items) i.id};
      final items = [...content.items, for (final i in next.items) if (!ids.contains(i.id)) i].take(limit).toList();
      final grown = content.copyWith(items: items, more: next.more && items.length < limit);
      appCache.put(_cacheKey(widget.module.id), grown, toJson: HomeModuleContent.toJson);
      setState(() => _content = grown);
    } on JellyfinException {
      // Leave it as it is; scrolling there again tries again.
    } finally {
      _loadingMore = false;
    }
  }

  /// Moves this section [by] places, and keeps it in view: the button you pressed stays
  /// focused, so the page follows it.
  Future<void> _move(int by) async {
    await homeLayout.move(widget.module.id, by);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.3,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// View toggle, move up, move down and remove: shown next to the title in edit mode.
  List<Widget> _editControls(BuildContext context) => [
    // Not for the banner, My Media or Genres, which have one look each.
    if (!const {HomeModuleType.carousel, HomeModuleType.myMedia, HomeModuleType.genres}.contains(widget.module.type))
      IconButton(
        onPressed: () => homeLayout.setView(
          widget.module.id,
          (_viewFor(context) == LibraryView.poster
              ? LibraryView.thumbnail
              : LibraryView.poster)
              .name,
        ),
        // Shows the view you'll switch *to*, like the library pages.
        icon: _viewFor(context) == LibraryView.poster
            ? const AspectIcon(width: 18, height: 10)
            : const AspectIcon(width: 11, height: 16),
      ),
    IconButton(
      onPressed: widget.isFirst ? null : () => _move(-1),
      icon: Icon(appIcons.moveUp, fill: 1),
    ),
    IconButton(
      onPressed: widget.isLast ? null : () => _move(1),
      icon: Icon(appIcons.moveDown, fill: 1),
    ),
    // Its settings (a Collection or Genre row's own).
    IconButton(
      onPressed: () => showSectionSettings(context, widget.module, _content?.title ?? widget.module.label ?? _spec.title),
      icon: Icon(appIcons.settings, fill: 1),
    ),
    IconButton(
      onPressed: () {
        homeLayout.remove(widget.module.id);
        if (widget.module.type.allowsMultiple) sectionSettings.forget(widget.module.id);
      },
      icon: Icon(
          appIcons.remove,
          color: context.colors.error,
          fill: 1
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final module = widget.module;
    final isCarousel = module.type == HomeModuleType.carousel;
    final isMyMedia = module.type == HomeModuleType.myMedia;
    final isGenres = module.type == HomeModuleType.genres;

    // Loaded and empty: hidden entirely, unless you're editing (then it says so).
    if (!widget.editing &&
        (isMyMedia
            ? jellyfin.libraries.isEmpty
            : isGenres
            ? jellyfin.genres.isEmpty
            : _error == null && (_content?.items.isEmpty ?? false))) {
      return const SizedBox.shrink();
    }

    final title =
        _content?.title ?? module.label ?? module.param ?? _spec.title;
    // Continue Watching and Next Up name what's in them under the cards, if set to; Favorites
    // names its seasons and episodes, as the Favorites page does.
    final options = _options;
    final captions =
        (module.type.followsProgress && (options.episodeTitles || options.movieTitles)) ||
        (module.type == HomeModuleType.favorites && (_content?.items.any((i) => options.favoriteNamed(i.type ?? '')) ?? false));

    return ScrollIntoViewOnFocus(
      child: Padding(
        padding: const EdgeInsets.only(
          bottom: 24,
        ), // every visible section: the same gap below it
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            // Its title if it's set to show one (the banner and Genres start without); always
            // while editing.
            if (_options.showTitle || widget.editing)
              Padding(
                padding: pageSides(
                  context,
                  extra: 16, // in line with the first card, which grows away from the edge
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: context.text.titleLarge,
                      ),
                    ),
                    if (widget.editing)
                      FocusRow(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: _editControls(context),
                        ),
                      ),
                  ],
                ),
              ),
            if (isCarousel)
            // The banner is a rounded card, so it keeps a margin rather than running to the edge.
              Padding(padding: pageSides(context), child: _carousel(context))
            else if (isMyMedia)
              _MyMediaRow(sides: _rowSides(context), editing: widget.editing, look: _options.look, named: _options.cardNames)
            else if (isGenres)
              _GenresRow(sides: _rowSides(context), editing: widget.editing, options: _options)
            else
              _row(context, _viewFor(context), captions: captions),
          ],
        ),
      ),
    );
  }

  Widget _carousel(BuildContext context) {
    final isPhone = ScreenType.of(context).isPhone;
    final items = _content?.items;
    final muted = context.text.bodyMedium?.copyWith(
      color: context.colors.onSurfaceVariant,
    );

    final Widget content;
    if (widget.editing || (items == null && _error == null)) {
      // Editing (just the layout, no artwork) or still loading: the banner's shape.
      content = const _Pulsing(child: _PlaceholderBanner());
    } else if (_error != null) {
      content = Center(child: Text(_error!, style: muted));
    } else if (items == null) {
      content = const SizedBox.shrink();
    } else if (items.isEmpty) {
      content = Center(child: Text('Nothing to feature yet', style: muted));
    } else {
      content = _Carousel(items: items, interval: Duration(seconds: _options.featuredSeconds));
    }

    return AspectRatio(aspectRatio: isPhone ? 16 / 9 : 21 / 9, child: content);
  }

  Widget _row(BuildContext context, LibraryView view, {bool captions = false}) {
    final tileWidth = _tileWidth(context, view);
    final imageHeight = view == LibraryView.poster
        ? tileWidth * 3 / 2
        : tileWidth * 9 / 16;

    final rowHeight = imageHeight + (captions ? _TileCaption.heightOf(context) : 0);
    final muted = context.text.bodyMedium?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    final items = _content?.items;

    Widget content;
    if (widget.editing || (items == null && _error == null)) {
      // Editing (just the layout, no artwork) or still loading: tiles' shapes in their place.
      content = _Pulsing(
        child: _PlaceholderRow(
          tileWidth: tileWidth,
          imageHeight: imageHeight,
          captions: captions,
        ),
      );
    } else if (_error != null) {
      content = Padding(
        padding: pageSides(context),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(_error!, style: muted),
        ),
      );
    } else if (items == null) {
      content = const SizedBox.shrink();
    } else if (items.isEmpty) {
      content = Align(
        alignment: Alignment.center,
        child: Text('Nothing here yet', style: muted),
      ); // edit mode only
    } else {
      content = FocusRow(
        child: ListView.separated(
          controller: _rowScroll,
          scrollDirection: Axis.horizontal,
          // Inside the list, so the first card starts in line with the title
          // but cards can still scroll right to the screen's edge.
          padding: _rowSides(context),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: _rowGap),
          itemBuilder: (context, i) {
            // (Every card the row's shape: a picture of another shape sits whole in it; see
            // PosterCard.)
            final width = tileWidth;
            final card = Focus(
              // Doesn't take focus itself: notices the card getting it, and scrolls the row.
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (focused) {
                if (focused) _keepInSlot(context, i, width);
              },
              child: PosterCard(
                item: items[i],
                view: view,
                preview: !widget.module.type.followsProgress, // none in Continue Watching or Next Up
                onPreviewShowing: (showing) => _onPreviewShowing(context, i, showing, view, imageHeight),
                // The first card grows away from the screen's left edge, the last away from its right.
                anchor: i == 0
                    ? Alignment.centerLeft
                    : i == items.length - 1
                    ? Alignment.centerRight
                    : Alignment.center,
                // Continue Watching and Next Up play straight away. Hold any card for more.
                onPress: widget.module.type.followsProgress
                    ? () => playFromProgress(context, items[i])
                    : () => openItem(context, items[i]),
                // Their menus can take things off the list.
                menuList: switch (widget.module.type) {
                  HomeModuleType.continueWatching => ItemMenuList.continueWatching,
                  HomeModuleType.nextUp => ItemMenuList.nextUp,
                  _ => null,
                },
              ),
            );
            // A poster playing its stills widens to 16:9 in its place, pushing the rest along.
            return SizedBox(
              width: view == LibraryView.poster && _widened == i
                  ? width + (imageHeight * 16 / 9 - width) * _widenCurve.transform(_widen.value)
                  : width,
              child: captions
                  ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: imageHeight, child: card),
                  _TileCaption(items[i], options: _options, favorites: widget.module.type == HomeModuleType.favorites),
                ],
              )
                  : card,
            );
          },
        ),
      );
    }

    return SizedBox(height: rowHeight, child: content);
  }

  /// The space between a row's tiles.
  static const _rowGap = CardRows.gap;

  static const _widenDuration = Duration(milliseconds: 250);

  static const _widenCurve = Curves.easeOutCubic;

  /// Card [index]'s stills started or stopped showing. In a poster row, the poster widens for
  /// it (or narrows back): to the right, or near the screen's edge, to the left.
  void _onPreviewShowing(BuildContext context, int index, bool showing, LibraryView view, double imageHeight) {
    if (!mounted || view != LibraryView.poster) return;
    if (showing) {
      _shift = 0;
      if (_rowScroll.hasClients) {
        final position = _rowScroll.position;
        final sides = _rowSides(context);
        final step = _tileWidth(context, view) + _rowGap;
        final right = sides.left + index * step + imageHeight * 16 / 9 - position.pixels;
        // Too near the edge to widen to the right: it widens to the left, all the way.
        final overflows = right > position.viewportDimension - sides.right;
        _shiftFrom = position.pixels;
        _shift = overflows ? imageHeight * 16 / 9 - _tileWidth(context, view) : 0;
      }
      setState(() => _widened = index);
      _widen.forward(from: 0);
    } else if (_widened == index) {
      _shift = 0;
      _widen.reverse();
    }
  }

  void _onWidenTick() {
    setState(() {}); // the poster's width
    if (_shift > 0 && _widen.status == AnimationStatus.forward && _rowScroll.hasClients) {
      _rowScroll.jumpTo(_shiftFrom + _shift * _widenCurve.transform(_widen.value));
    }
  }

  /// With a remote or keyboard, scrolls the row so card [index] sits where the last card that
  /// fits whole on screen sits when the row is at its start (the third, say). Focus moves along
  /// the first few without the row moving; after that, each next card slides into that same
  /// spot, and going back works the same way.
  void _keepInSlot(BuildContext context, int index, double tileWidth) {
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
    if (!_rowScroll.hasClients) return;
    final position = _rowScroll.position;
    final step = tileWidth + _rowGap;
    final start = _rowSides(context).left; // the row's padding before the first card
    final slot = math.max(0, ((position.viewportDimension - start - tileWidth) / step).floor());
    final offset = ((index - slot) * step).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((offset - position.pixels).abs() < 0.5) return;
    position.animateTo(offset, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
  }

  static double _tileWidth(BuildContext context, LibraryView view) => CardRows.tileWidth(context, view);

  static EdgeInsets _rowSides(BuildContext context) => CardRows.sides(context);
}

// ─── Adding sections ─────────────────────────────────────────────────────────

/// Shown at the bottom of the home screen in edit mode: the sections you can add,
/// and a way back to the default layout.
class AddHomeModules extends StatelessWidget {
  const AddHomeModules({super.key});

  /// Collection and Genre sections need a choice first; everything else is added directly.
  Future<void> _add(BuildContext context, HomeModuleType type) async {
    final client = jellyfin.client;
    if (client == null) return;

    switch (type) {
      case HomeModuleType.collection:
        final picked = await _showOptionPicker(
          context,
          title: 'Choose a collection',
          options: client.items
              .list(
            enableTotalRecordCount: false,
            includeItemTypes: const ['BoxSet'],
            recursive: true,
            sortBy: const ['SortName'],
            limit: 500,
          )
              .then((page) => [for (final c in page.items) (c.id, c.name)]),
        );
        if (picked != null) await homeLayout.add(type, param: picked.$1, label: picked.$2);

      case HomeModuleType.genre:
        final picked = await _showOptionPicker(
          context,
          title: 'Choose a genre',
          options: Future.value([for (final g in jellyfin.genres) (g, g)]),
        );
        if (picked != null) await homeLayout.add(type, param: picked.$1, label: picked.$2);

      default:
        await homeLayout.add(type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = homeLayout.available;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text('Add a section', style: context.text.titleLarge),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in available)
              OutlinedButton(
                onPressed: () => _add(context, type),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    Icon(homeModuleSpecs[type]!.icon(appIcons), size: 18, fill: 1),
                    Text(homeModuleSpecs[type]!.title),
                  ],
                ),
              ),
          ],
        ),
        TextButton(
          onPressed: () => homeLayout.reset(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Icon(appIcons.reset, size: 18, fill: 1),
              const Text('Reset to default layout'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shows a searchable list of (value, label) options and returns the one picked, or null.
Future<(String, String)?> _showOptionPicker(
    BuildContext context, {
      required String title,
      required Future<List<(String, String)>> options,
    }) {
  return showGeneralDialog<(String, String)>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: context.colors.scrim,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, _, _) => Center(
      child: _OptionPicker(title: title, options: options),
    ),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _OptionPicker extends StatefulWidget {
  const _OptionPicker({required this.title, required this.options});

  final String title;
  final Future<List<(String, String)>> options;

  @override
  State<_OptionPicker> createState() => _OptionPickerState();
}

class _OptionPickerState extends State<_OptionPicker> {
  final _search = TextEditingController();
  List<(String, String)>? _all;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {})); // filter as you type
    widget.options.then(
          (options) {
        if (mounted) setState(() => _all = options);
      },
      onError: (_) {
        if (mounted) setState(() => _error = "Couldn't load the list.");
      },
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final muted = context.text.bodyMedium?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    final query = _search.text.trim().toLowerCase();
    final shown = _all
        ?.where((o) => o.$2.toLowerCase().contains(query))
        .toList();

    final Widget list;
    if (_error != null) {
      list = Center(child: Text(_error!, style: muted));
    } else if (shown == null) {
      list = const Center(child: CircularProgressIndicator());
    } else if (shown.isEmpty) {
      list = Center(child: Text('Nothing found', style: muted));
    } else {
      list = ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: shown.length,
        itemBuilder: (context, i) => ListTile(
          dense: true,
          shape: const StadiumBorder(),
          onTap: () => Navigator.of(context).pop(shown[i]),
          title: Text(
            shown[i].$2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return SizedBox(
      width: math.min(420, size.width - 32),
      height: math.min(560, size.height * 0.8),
      child: Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(widget.title, style: context.text.titleLarge),
              RemoteTextField(
                autofocus: true,
                builder: (context, focusNode, highlighted) => TextField(
                  controller: _search,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    hintText: 'Search',
                    border: searchFieldBorder,
                    enabledBorder: highlighted ? remoteFieldBorder(context, searchFieldBorder) : null,
                  ),
                ),
              ),
              Expanded(child: list),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        )),
    );
  }
}

// ─── Carousel ────────────────────────────────────────────────────────────────

/// A rotating banner of featured items. Advances on its own; arrows, dots and swiping move it by hand.
class _Carousel extends StatefulWidget {
  const _Carousel({required this.items, this.interval = const Duration(seconds: 8)});

  final List<JellyfinItem> items;

  /// How long each slide stays.
  final Duration interval;

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  Duration get _interval => widget.interval;

  /// While someone's on the carousel it holds still, unless they've been idle this long
  /// (probably walked away), after which it resumes advancing.
  static const _idleResume = Duration(seconds: 45);

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  bool _engaged = false; // focus or pointer is on the carousel
  DateTime _lastInteraction = DateTime.now();

  /// Each slide's own buttons. (Not one pair handed from slide to slide: a focused button whose
  /// node is swapped can stay drawn as focused, leaving two lit at once.)
  late var _playFocus = _nodes('Carousel Play');
  late var _infoFocus = _nodes('Carousel More info');

  List<FocusNode> _nodes(String label) => [for (final _ in widget.items) FocusNode(debugLabel: label)];

  @override
  void didUpdateWidget(_Carousel old) {
    super.didUpdateWidget(old);
    if (widget.items.length == old.items.length) return;
    // A different number of slides (refreshed): new buttons for them, after this frame lets go
    // of the old ones.
    final stale = [..._playFocus, ..._infoFocus];
    _playFocus = _nodes('Carousel Play');
    _infoFocus = _nodes('Carousel More info');
    if (_page >= widget.items.length) _page = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final node in stale) {
        node.dispose();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    for (final node in [..._playFocus, ..._infoFocus]) {
      node.dispose();
    }
    super.dispose();
  }

  void _touch() => _lastInteraction = DateTime.now();

  /// Starts the countdown to the next slide again, e.g. after someone moves it by hand.
  void _restartTimer() {
    _timer?.cancel();
    if (widget.items.length < 2) return;
    _timer = Timer.periodic(_interval, (_) {
      final idle = DateTime.now().difference(_lastInteraction);
      if (_engaged && idle < _idleResume) return; // someone's here: hold still
      _goTo(_page + 1);
    });
  }

  void _setEngaged(bool engaged) {
    if (engaged != _engaged && mounted) setState(() => _engaged = engaged);
    _touch();
    if (!engaged) _restartTimer(); // leaving: a full 8 seconds before the next slide
  }

  /// Slides to a page, wrapping around at either end.
  void _goTo(int page) {
    if (!_controller.hasClients) return;
    final count = widget.items.length;
    _controller.animateToPage(
      ((page % count) + count) % count,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
    );
  }

  /// → from More info goes to the next slide, ← from Play to the previous one.
  /// Between the two buttons, arrows move focus as usual.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    _touch(); // any key press counts as someone being here
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight && _infoFocus[_page].hasFocus) {
      _goTo(_page + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && _playFocus[_page].hasFocus) {
      _goTo(_page - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;

    return MouseRegion(
      onEnter: (_) => _setEngaged(true),
      onExit: (_) => _setEngaged(false),
      onHover: (_) => _touch(),
      child: Focus(
        // Doesn't take focus itself; notices focus on its buttons, and handles ←/→ from them.
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: _setEngaged,
        onKeyEvent: _onKey,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: count,
                onPageChanged: (page) {
                  // The button that had focus: the new slide's matching one gets it.
                  final refocus = _playFocus[_page].hasFocus
                      ? _playFocus[page]
                      : _infoFocus[_page].hasFocus
                      ? _infoFocus[page]
                      : null;
                  setState(() => _page = page);
                  _restartTimer();
                  if (refocus != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) refocus.requestFocus();
                    });
                  }
                },
                itemBuilder: (context, i) => _CarouselSlide(
                  item: widget.items[i],
                  playFocus: _playFocus[i],
                  infoFocus: _infoFocus[i],
                ),
              ),

              // ── Dots ──
              if (count > 1)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Row(
                    spacing: 6,
                    children: [
                      for (var i = 0; i < count; i++)
                        GestureDetector(
                          onTap: () => _goTo(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: i == _page ? 20 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? const Color(0xFFFFFFFF)
                                  : const Color(0x80FFFFFF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One slide: the backdrop, a fade for readability, and the logo, details, Play and More info.
class _CarouselSlide extends StatefulWidget {
  const _CarouselSlide({
    required this.item,
    this.playFocus,
    this.infoFocus,
  });

  final JellyfinItem item;
  final FocusNode? playFocus;
  final FocusNode? infoFocus;

  @override
  State<_CarouselSlide> createState() => _CarouselSlideState();
}

class _CarouselSlideState extends State<_CarouselSlide> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final client = jellyfin.client!;
    final isPhone = ScreenType.of(context).isPhone;
    final backdropTag = (item.raw['BackdropImageTags'] as List).first as String;
    final logoTag = item.imageTags['Logo'];
    final overview = (item.raw['Overview'] as String?)?.trim();
    final year = item.raw['ProductionYear'];
    final rating = item.raw['OfficialRating'] as String?;
    final facts = [
      if (year != null) '$year',
      if (rating != null && rating.isNotEmpty) rating,
    ].join('  ·  ');
    const white = Color(0xFFFFFFFF);
    final title = Text(
      item.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: context.text.headlineSmall?.copyWith(color: white),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        // Click or tap anywhere on the slide to open it. Not focusable: with a remote,
        // the Play and More info buttons are the way in, so ↑ from them goes straight past.
        behavior: HitTestBehavior.opaque,
        onTap: () => openItem(context, item),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              client.images.url(
                itemId: item.id,
                type: JellyfinImagesApi.typeBackdrop,
                tag: backdropTag,
                fillWidth: 1920,
                quality: 90,
              ),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, _, _) =>
                  ColoredBox(color: context.colors.surfaceContainerHighest),
            ),
            // Everything over the artwork. (No preview here: the banner keeps its backdrop.)
            Positioned.fill(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: [0.0, 0.65],
                      colors: [Color(0xCC000000), Color(0x00000000)],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.5, 1.0],
                      colors: [Color(0x00000000), Color(0x99000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: isPhone ? 16 : 32,
                  bottom: isPhone ? 16 : 32,
                  right: isPhone ? 80 : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        // (The name instead, if the logo won't load: a saved page can ask for one the
                        // server has since replaced.)
                        if (logoTag != null)
                          TitleLogo(itemId: item.id, tag: logoTag, size: TitleLogo.banner(isPhone), fallback: title)
                        else
                          ConstrainedBox(constraints: BoxConstraints(maxWidth: isPhone ? 180 : 360), child: title),
                        if (facts.isNotEmpty)
                          Text(
                            facts,
                            style: context.text.bodyMedium?.copyWith(
                              color: const Color(0xCCFFFFFF),
                            ),
                          ),
                        if (!isPhone && overview != null && overview.isNotEmpty)
                          Text(
                            overview,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyLarge?.copyWith(
                              color: const Color(0xE6FFFFFF),
                            ),
                          ),
                        if (!isPhone)
                          FocusRow(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 8,
                              children: [
                                FilledButton(
                                  style: actionButtonStyle,
                                  focusNode: widget.playFocus,
                                  onPressed: () => playItem(context, item),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    spacing: 8,
                                    children: [Icon(appIcons.play, size: 18, fill: 1), const Text('Play')],
                                  ),
                                ),
                                FilledButton.tonal(
                                  style: actionButtonStyle,
                                  focusNode: widget.infoFocus,
                                  onPressed: () => openItem(context, item),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    spacing: 8,
                                    children: [Icon(appIcons.info, size: 18, fill: 1), const Text('More info')],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                  ],
                ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Under a Continue Watching or Next Up tile: the show (or movie) name, then
/// "S1:E2 · Episode name" for episodes, or the year for movies.
class _TileCaption extends StatelessWidget {
  const _TileCaption(this.item, {required this.options, this.favorites = false});

  final JellyfinItem item;

  /// In Favorites: each kind named if it's set to be (seasons and episodes as on the Favorites
  /// page; the rest by name and year).
  final bool favorites;

  /// Whether episodes and movies are named, and how (see SectionOptions).
  final SectionOptions options;

  static const _top = 6.0; // between the artwork and the title
  static const _gap = 2.0; // between the title and the line under it

  static TextStyle? _titleStyle(BuildContext context) =>
      context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
  static TextStyle? _subtitleStyle(BuildContext context) =>
      context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);

  /// The room a caption takes, measured with the fonts and text size in use, so a bigger
  /// system font size or a taller font doesn't overflow the row.
  static double heightOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag', style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return _top + line(_titleStyle(context)) + _gap + line(_subtitleStyle(context));
  }

  @override
  Widget build(BuildContext context) {
    final isEpisode = item.type == JellyfinItemKind.episode;
    final isSeason = item.type == JellyfinItemKind.season;
    // Not named: the room left empty, so the cards stay in line.
    if (favorites ? !options.favoriteNamed(item.type ?? '') : (isEpisode ? !options.episodeTitles : !options.movieTitles)) {
      return const SizedBox.shrink();
    }
    final title = isEpisode || isSeason
        ? (item.raw['SeriesName'] as String?) ?? item.name
        : item.name;

    final subtitle = isSeason
        ? item.name
        : isEpisode && favorites
        ? episodeLabel(item.raw['ParentIndexNumber'], item.raw['IndexNumber'], item.name)
        : isEpisode
        ? switch (options.episodeTitleStyle) {
            EpisodeTitleStyle.both => episodeLabel(item.raw['ParentIndexNumber'], item.raw['IndexNumber'], item.name),
            EpisodeTitleStyle.code =>
              seasonEpisode(item.raw['ParentIndexNumber'], item.raw['IndexNumber']) ?? item.name,
            EpisodeTitleStyle.name => item.name,
          }
        : item.raw['ProductionYear']?.toString();

    return Padding(
      // Lines the text up with the artwork, which sits slightly inset until hovered.
      padding: const EdgeInsets.fromLTRB(8, _top, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: _gap,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _titleStyle(context),
          ),
          if (subtitle != null && subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _subtitleStyle(context),
            ),
        ],
      ),
    );
  }
}
/// [card] as is; or, [named], at [height] with [name] under it.
Widget _named(bool named, double height, String name, Widget card) => !named
    ? card
    : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [SizedBox(height: height, child: card), _NameCaption(name)],
      );

/// A card's name under it (My Media's and Genres', if set to), as [_TileCaption] lays out its
/// first line.
class _NameCaption extends StatelessWidget {
  const _NameCaption(this.name);

  final String name;

  /// The room it takes.
  static double heightOf(BuildContext context) => _TileCaption._top + lineHeightOf(context, _TileCaption._titleStyle(context)) + 1;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, _TileCaption._top, 4, 0),
    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _TileCaption._titleStyle(context)),
  );
}

// ─── Placeholders ────────────────────────────────────────────────────────────

/// Fades [child] gently in and out, to show something is on its way.
class _Pulsing extends StatefulWidget {
  const _Pulsing({required this.child});

  final Widget child;

  @override
  State<_Pulsing> createState() => _PulsingState();
}

class _PulsingState extends State<_Pulsing> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);
  late final _opacity = Tween(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _opacity, child: widget.child);
}

/// A plain block standing in for artwork or a line of text.
class _PlaceholderBlock extends StatelessWidget {
  const _PlaceholderBlock({this.width, this.height, this.radius = 8, this.color});

  final double? width;
  final double? height;
  final double radius;
  final Color? color; // lighter, for lines drawn over a larger block

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color ?? context.colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// A row's tiles, without their artwork: the same sizes and spacing as the real ones, and
/// title lines under them where the row has captions. Not focusable: nothing to open yet.
class _PlaceholderRow extends StatelessWidget {
  const _PlaceholderRow({
    required this.tileWidth,
    required this.imageHeight,
    required this.captions,
  });

  final double tileWidth;
  final double imageHeight;
  final bool captions;

  @override
  Widget build(BuildContext context) => ListView.separated(
    scrollDirection: Axis.horizontal,
    physics: const NeverScrollableScrollPhysics(),
    padding: _HomeModuleViewState._rowSides(context),
    itemCount: 12, // more than fit, so the row runs off the edge like a real one
    separatorBuilder: (_, _) => const SizedBox(width: 4),
    itemBuilder: (context, i) => SizedBox(
      width: tileWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Where a resting card's artwork sits (the first one's against the row's start).
            padding: PosterCard.restInset(imageHeight, anchor: i == 0 ? Alignment.centerLeft : Alignment.center),
            child: _PlaceholderBlock(height: imageHeight - PosterCard.restInset(imageHeight).vertical),
          ),
          if (captions) ...[
            // Where _TileCaption puts the title and the line under it.
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _PlaceholderBlock(width: tileWidth * 0.6, height: 12, radius: 4),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _PlaceholderBlock(width: tileWidth * 0.3, height: 10, radius: 4),
            ),
          ],
        ],
      ),
    ),
  );
}

/// The featured banner without its artwork: the banner's shape, with lines where its title
/// and description go.
class _PlaceholderBanner extends StatelessWidget {
  const _PlaceholderBanner();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const _PlaceholderBlock(radius: 12),
      Positioned(
        left: 32,
        bottom: 32,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            _PlaceholderBlock(width: 220, height: 40, radius: 6, color: context.colors.surfaceContainerHighest),
            _PlaceholderBlock(width: 320, height: 12, radius: 4, color: context.colors.surfaceContainerHighest),
            _PlaceholderBlock(width: 260, height: 12, radius: 4, color: context.colors.surfaceContainerHighest),
          ],
        ),
      ),
    ],
  );
}

/// Hides everything in the first [left] pixels of a row, and nothing else (a focused card can
/// still grow past the row's top and bottom).
// ─── My Media ────────────────────────────────────────────────────────────────

/// Your libraries as tiles of their own artwork (or a colored tile with its icon and name,
/// without any), each opening the library.
/// Ten of the server's genres, picked at random (once per launch, so they don't shuffle as you
/// scroll), as tiles like the Genres page's.
class _GenresRow extends StatefulWidget {
  const _GenresRow({required this.sides, required this.options, this.editing = false});

  final EdgeInsets sides; // the row's padding at its ends

  /// How many genres, and which (see SectionOptions).
  final SectionOptions options;

  /// Editing Home: just the tiles' shapes, as other sections show.
  final bool editing;

  @override
  State<_GenresRow> createState() => _GenresRowState();
}

class _GenresRowState extends State<_GenresRow> {
  final _scroll = ScrollController();

  static const _gap = genreCardGap;

  /// The server's genres shuffled once a launch, so a random pick doesn't change as you scroll.
  static List<String>? _shuffled;
  static List<String>? _shuffledFrom;

  /// The genres to show: all of them; or as many as set, picked at random or from the ones
  /// chosen (in the server's order).
  List<String> _pick(List<String> genres) {
    final count = widget.options.genreCount;
    if (count == null) return genres;
    if (widget.options.genrePick == GenrePick.chosen) {
      final chosen = widget.options.chosenGenres.toSet();
      return genres.where(chosen.contains).take(count).toList();
    }
    if (!identical(genres, _shuffledFrom)) {
      _shuffledFrom = genres;
      _shuffled = [...genres]..shuffle();
    }
    return _shuffled!.take(count).toList();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// With a remote, as the other rows do: tile [index] sits in the last slot that fits whole,
  /// so the row moves under it and it never runs to the screen's edge.
  void _keepInSlot(int index, double width) {
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final step = width + _gap;
    final slot = math.max(0, ((position.viewportDimension - widget.sides.left - width) / step).floor());
    final offset = ((index - slot) * step).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((offset - position.pixels).abs() < 0.5) return;
    position.animateTo(offset, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([genreCards, serverThemes]), // the cards' style, and a theme's pictures
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    // 4.5 across, as My Media (2.3 on phones).
    final width = _shortcutWidth(context);
    final height = width / genreCardAspect();
    final genres = _pick(jellyfin.genres);
    // Editing (just the layout): the tiles' shapes, pulsing, as the other sections show them.
    if (widget.editing) {
      return SizedBox(
        height: height,
        child: _Pulsing(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: widget.sides,
            itemCount: 10,
            separatorBuilder: (_, _) => const SizedBox(width: _gap),
            itemBuilder: (_, _) => _PlaceholderBlock(width: width, height: height, radius: 12),
          ),
        ),
      );
    }
    final named = widget.options.cardNames;
    return SizedBox(
      height: height + (named ? _NameCaption.heightOf(context) : 0),
      child: FocusRow(
        child: ListView.separated(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none, // a focused card grows past the row's ends
          padding: widget.sides, // the first in line with the sections' titles
          itemCount: genres.length,
          separatorBuilder: (_, _) => const SizedBox(width: _gap),
          itemBuilder: (context, i) => SizedBox(
            width: width,
            child: Focus(
              // Doesn't take focus itself: notices the tile getting it, and scrolls the row.
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (focused) {
                if (focused) _keepInSlot(i, width);
              },
              child: named
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: height, child: GenreTile(genre: genres[i], nameInside: false)),
                        _NameCaption(genres[i]),
                      ],
                    )
                  : GenreTile(genre: genres[i]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The width of My Media's and the Genres section's cards: 4.5 across on wider screens (the half
/// says there's more), beside a pinned menu too; 2.3 on phones.
double _shortcutWidth(BuildContext context) =>
    CardRows.acrossWidth(context, ScreenType.of(context).isPhone ? 2.3 : 4.5, spacing: genreCardGap);

class _MyMediaRow extends StatelessWidget {
  const _MyMediaRow({required this.sides, this.editing = false, this.look = CardLook.pictures, this.named = false});

  /// Each library's name under its card.
  final bool named;

  /// The libraries' own pictures from Jellyfin, or icon cards.
  final CardLook look;

  final EdgeInsets sides; // the row's padding at its ends

  /// Editing Home: just the tiles' shapes, as other sections show.
  final bool editing;

  /// Tile colors, in turn.
  static const _colors = [
    Color(0xFF6876F2),
    Color(0xFFD81E6A),
    Color(0xFFD9822B),
    Color(0xFF1B8A4C),
    Color(0xFF8E44AD),
    Color(0xFF1E88C8),
  ];

  @override
  Widget build(BuildContext context) {
    // The same size, spacing and look as Home's genre cards (see _shortcutWidth).
    final width = _shortcutWidth(context);
    final height = width * 9 / 16;
    final libraries = jellyfin.libraries;
    // Editing (just the layout), or the libraries not in yet: the tiles' shapes, as the other
    // sections show them.
    if (editing || libraries.isEmpty) {
      return SizedBox(
        height: height,
        child: _Pulsing(child: _PlaceholderRow(tileWidth: width, imageHeight: height, captions: false)),
      );
    }
    return SizedBox(
      height: height + (named ? _NameCaption.heightOf(context) : 0),
      child: FocusRow(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: sides,
          clipBehavior: Clip.none, // a focused tile grows past the row's ends
          itemCount: libraries.length,
          separatorBuilder: (_, _) => const SizedBox(width: genreCardGap),
          itemBuilder: (context, i) {
            final library = libraries[i];
            return SizedBox(
              width: width,
              child: _named(
                named,
                height,
                library.name,
                Tappable(
                onPress: () => context.go('/home/library/${library.id}'),
                semanticsLabel: library.name,
                // Like a genre card: the whole tile, growing a little when focused, with the focus
                // border over the artwork's edge.
                builder: (context, states, child) {
                  final active = isHighlighted(states);
                  return AnimatedScale(
                    scale: active ? 1.04 : 1,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: active ? cardHoverShadow : const [], // lifted off the page
                      ),
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: active ? context.colors.primary : context.colors.primary.withValues(alpha: 0), width: 3),
                      ),
                      child: child,
                    ),
                  );
                },
                // Icons: a card of its own color with its kind's icon.
                child: look == CardLook.icons
                    ? IconCard(name: library.name, icon: libraryIcon(library.collectionType), showName: !named)
                    :
                // The library's own artwork from Jellyfin; its icon if it has none.
                Image.network(
                  jellyfin.client!.images.url(
                    itemId: library.id,
                    type: JellyfinImagesApi.typePrimary,
                    fillWidth: (width * View.of(context).devicePixelRatio).round(),
                    quality: 90,
                  ),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  // A placeholder, pulsing, until the artwork arrives.
                  frameBuilder: (context, child, frame, loaded) =>
                      loaded || frame != null ? child : const _Pulsing(child: _PlaceholderBlock()),
                  // (Jellyfin's own library pictures have the name on them, so it isn't repeated.)
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: _colors[i % _colors.length],
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 6,
                      children: [
                        Icon(libraryIcon(library.collectionType), size: height * 0.36, color: const Color(0xFFFFFFFF)),
                        if (!named)
                          Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            library.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleMedium?.copyWith(color: const Color(0xFFFFFFFF)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ),
            );
          },
        ),
      ),
    );
  }
}
