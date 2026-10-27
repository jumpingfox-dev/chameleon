import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/app_icons.dart';
import '../../core/storage/app_cache.dart';
import '../../core/focus/focus_rows.dart';
import '../../core/format/format.dart';
import '../../core/format/item_format.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import '../../core/jellyfin/list_each.dart';
import '../../core/platform/screen_type.dart';
import '../../core/platform/media_support.dart';
import '../downloads/download_button.dart';
import '../library/item_menu.dart';
import '../previews/trailers.dart';
import '../previews/trailer_screen.dart';
import 'expandable_text.dart';
import '../../widgets/hover_lift.dart';
import '../library/poster_card.dart';
import '../../core/focus/scroll_into_view.dart';
import '../../theme/theme.dart';
import '../../widgets/tappable.dart';
import '../../core/platform/page_insets.dart';
import '../../core/jellyfin/together.dart';

part 'detail_blocks.dart';
part 'detail_cards.dart';
part 'detail_sections.dart';

/// Bumped whenever a favorite is added or removed, so pages listing favorites can refresh.
final favoritesChanged = ValueNotifier<int>(0);

// ─── Navigation ──────────────────────────────────────────────────────────────

/// Where selecting an item goes. One place for every page, so they all behave the same.
void openItem(BuildContext context, JellyfinItem item) {
  switch (item.type) {
    case JellyfinItemKind.movie:
      showDetailPage(context, load: movieDetails(item.id), layout: const MovieLayout(), cacheKey: 'movie:${item.id}');
    case JellyfinItemKind.series:
      showDetailPage(
        context,
        load: seriesDetails(item.id),
        layout: const SeriesLayout(),
        cacheKey: 'series:${item.id}',
      );
    case JellyfinItemKind.season:
      openSeason(context, item);
    case JellyfinItemKind.episode:
      context.push('/play/${item.id}');
    case 'BoxSet':
      showDetailPage(
        context,
        load: collectionDetails(item.id),
        layout: const CollectionLayout(),
        cacheKey: 'collection:${item.id}',
      );
    case JellyfinItemKind.person:
      openPerson(context, item.id);
  }
}

/// Opens a person's page by id (cast rows and search results only have the id).
void openPerson(BuildContext context, String personId) =>
    showDetailPage(context, load: personDetails(personId), layout: const PersonLayout(), cacheKey: 'person:$personId');

/// Opens a show's page by id (an episode only has its show's id).
void openSeries(BuildContext context, String seriesId) => showDetailPage(
  context,
  load: seriesDetails(seriesId),
  layout: const SeriesLayout(),
  cacheKey: 'series:$seriesId',
);

/// Opens a season's page: its artwork over the show's backdrop, its episodes.
void openSeason(BuildContext context, JellyfinItem season) => showDetailPage(
  context,
  load: seasonDetails(season.id, (season.raw['SeriesId'] as String?) ?? ''),
  layout: const SeasonLayout(),
  cacheKey: 'season:${season.id}',
);

/// Plays an item: a movie (or episode) directly, a series from where you left off, or a
/// collection through from its first unwatched title.
Future<void> playItem(BuildContext context, JellyfinItem item) async {
  final router = GoRouter.of(context); // grab it before any await
  switch (item.type) {
    case JellyfinItemKind.series:
      final episode = await nextEpisodeFor(item.id);
      if (episode != null) router.push('/play/${episode.id}');
    case 'BoxSet':
      try {
        final data = await collectionDetails(item.id)(jellyfin.client!);
        playQueue(router, collectionQueue(data.children));
      } on JellyfinException {
        // Couldn't load the collection: nothing to play.
      }
    default:
      router.push('/play/${item.id}');
  }
}

/// The titles to play through for a collection, as item ids: in order from the first one
/// you haven't finished, or all of them in random order with [shuffle].
/// Only movies and videos play directly; a series inside a collection is left out.
List<String> collectionQueue(List<JellyfinItem> items, {bool shuffle = false}) {
  final playable = [
    for (final item in items)
      if (item.type == JellyfinItemKind.movie ||
          item.type == JellyfinItemKind.episode ||
          item.type == 'Video')
        item,
  ];
  if (shuffle) return [for (final item in playable) item.id]..shuffle();

  final firstUnwatched = playable.indexWhere(
        (item) => (item.raw['UserData'] as Map?)?['Played'] != true,
  );
  final from = firstUnwatched == -1 ? 0 : firstUnwatched; // all watched: from the top
  return [for (final item in playable.skip(from)) item.id];
}

/// Opens the player on the first of [ids], playing the rest after it.
void playQueue(GoRouter router, List<String> ids) {
  if (ids.isEmpty) return;
  router.push(
    Uri(path: '/play/${ids.first}', queryParameters: {'queue': ids.join(',')}).toString(),
  );
}

/// The episode to play next in a series: Jellyfin's "Next Up", or else the first episode
/// of the first regular season (skipping Specials).
///
/// _SeriesPlayButton below works this out again on its own, falling back to the first
/// *listed* season rather than skipping Specials. Left as two routines for this pass: folding
/// one into the other changes what Play does for a show whose first season is Specials,
/// which is a behaviour call rather than a tidy-up.
Future<JellyfinItem?> nextEpisodeFor(String seriesId) async {
  final client = jellyfin.client!;

  final nextUp = await client.tvShows.nextUp(
    enableTotalRecordCount: false,
    seriesId: seriesId,
    limit: 1,
    enableResumable: true,
  );
  if (nextUp.items.firstOrNull case final episode?) return episode;

  final seasons = (await client.tvShows.seasons(seriesId: seriesId)).items;
  final firstSeason =
      seasons
          .where((s) => ((s.raw['IndexNumber'] as int?) ?? 0) > 0)
          .firstOrNull ??
          seasons.firstOrNull;
  if (firstSeason == null) return null;

  final episodes = await client.tvShows.episodes(
    seriesId: seriesId,
    seasonId: firstSeason.id,
  );
  return episodes.items.firstOrNull;
}

/// A title's (or person's) page, opened over the page it was opened from, inside the tab: the
/// top bar stays. Back returns to where you were.
class _DetailRoute extends PageRouteBuilder<void> {
  _DetailRoute({required super.pageBuilder})
    : super(
        // The page's title, for the app's top bar (see detailTitleOf), once it's loaded.
        settings: RouteSettings(name: 'detail', arguments: ValueNotifier<String?>(null)),
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      );
}

/// Opens a detail layout as a page of its own in the current tab.
Future<void> showDetailPage(
  BuildContext context, {
  required DetailLoader load,
  required DetailLayout layout,
  String? cacheKey,
}) => Navigator.of(context).push(
  _DetailRoute(
    pageBuilder: (context, _, _) => _CloseOnNavigation(
      child: DetailPage(load: load, layout: layout, cacheKey: cacheKey),
    ),
  ),
);

/// The title of [route] if it's a detail page (a movie's, a show's, a person's, ...), or null.
/// It's null until the page has loaded, and the notifier tells when it changes.
ValueNotifier<String?>? detailTitleOf(Route<dynamic>? route) =>
    route is _DetailRoute ? route.settings.arguments as ValueNotifier<String?> : null;

/// Closes every open detail page, e.g. before going to a full page like a genre.
void closeDetailPages(BuildContext context) => Navigator.of(context).popUntil((route) => route is! _DetailRoute);

// ─── Data ────────────────────────────────────────────────────────────────────

/// What a detail page loads: the main item, the items that belong to it,
/// and anything extra a particular layout needs (seasons, tracks, ...).
class DetailData {
  const DetailData({
    required this.item,
    this.children = const [],
    this.extra = const {},
  });

  final JellyfinItem item;
  final List<JellyfinItem> children;
  final Map<String, Object?> extra;

  /// As saved in [appCache]. [extra] isn't saved: pages that use it aren't saved at all.
  static Object? toJson(DetailData d) =>
      {'item': itemToJson(d.item), 'children': itemsToJson(d.children)};

  static DetailData fromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return DetailData(item: itemFromJson(map['item']), children: itemsFromJson(map['children']));
  }
}

// ─── Loaders ─────────────────────────────────────────────────────────────────

typedef DetailLoader = Future<DetailData> Function(JellyfinClient client);

DetailLoader movieDetails(String id) =>
        (client) async => DetailData(item: (await client.items.byId(id))!);

DetailLoader collectionDetails(String id) => (client) async {
  final (collection, page) = await together2(
    client.items.byId(id),
    client.items.list(
      enableTotalRecordCount: false,
      parentId: id,
      // Just what's in the collection: a show, not its seasons and every episode as well.
      recursive: false,
      sortBy: const ['ProductionYear', 'SortName'],
      limit: 200,
      fields: const ['Genres', 'OfficialRating', 'ProductionYear'],
    ),
  );
  return DetailData(item: collection!, children: page.items);
};

DetailLoader personDetails(String id) => (client) async {
  final (person, page) = await together2(
    client.items.byId(id),
    client.items.listEach(
      personIds: [id],
      types: const [JellyfinItemKind.movie, JellyfinItemKind.series],
      sortBy: const ['ProductionYear', 'SortName'],
      descending: true,
    ),
  );
  return DetailData(item: person!, children: page);
};

DetailLoader seriesDetails(String id) => (client) async {
  final (series, seasons) = await together2(client.items.byId(id), client.tvShows.seasons(seriesId: id));
  // Regular seasons in order, with "Specials" (season 0) at the end.
  final ordered = [...seasons.items]
    ..sort((a, b) {
      final ai = (a.raw['IndexNumber'] as int?) ?? 0,
          bi = (b.raw['IndexNumber'] as int?) ?? 0;
      if (ai == 0) return 1;
      if (bi == 0) return -1;
      return ai.compareTo(bi);
    });
  return DetailData(item: series!, children: ordered);
};

/// A season, its show (for the backdrop, the trailer and a cast when the season has none) in
/// [DetailData.extra]'s 'series', and its episodes.
DetailLoader seasonDetails(String id, String seriesId) => (client) async {
  final (season, series, episodes) = await together3(
    client.items.byId(id),
    client.items.byId(seriesId),
    client.tvShows.episodes(seriesId: seriesId, seasonId: id, fields: const ['Overview']),
  );
  return DetailData(item: season!, children: episodes.items, extra: {'series': series});
};

// ─── Layouts ─────────────────────────────────────────────────────────────────

/// How a detail page looks. Each kind of page gets its own subclass,
/// free to lay things out however it wants.
abstract class DetailLayout {
  const DetailLayout();

  /// Text in the page's header, if any.
  String? headerTitle(DetailData data) => null;

  /// The page's content, as slivers.
  List<Widget> buildSlivers(BuildContext context, DetailData data);

  /// True if the page draws its own header (a backdrop, a photo) instead of a title row.
  bool get noAppBar => false;

  /// Space above the page's content.
  double get topPadding => 24;

  /// The item whose backdrop fills the top of the page, behind everything, if any.
  JellyfinItem? backdropOf(DetailData data) => null;

  /// True if [backdropOf]'s picture isn't the page's own, so it's shown blurred (a person's).
  bool get blurBackdrop => false;

  /// True if the page leaves its sides to each part (they're all [_BackdropScope]-aware), so
  /// rows can scroll to the screen's edge.
  bool get edgeToEdge => false;
}

/// A person, over a backdrop from their best-rated title: photo, name, birth and death,
/// biography, then rows of the movies and shows they're in.
class PersonLayout extends DetailLayout {
  const PersonLayout();

  @override
  List<Widget> buildSlivers(BuildContext context, DetailData data) {
    final movies = [for (final i in data.children) if (i.type == JellyfinItemKind.movie) i];
    final shows = [for (final i in data.children) if (i.type != JellyfinItemKind.movie) i];
    return [
      SliverToBoxAdapter(child: _PersonHero(person: data.item, movies: movies.length, shows: shows.length)),
      if (movies.isNotEmpty) SliverToBoxAdapter(child: _ItemRow(title: 'Movies', items: movies)),
      if (shows.isNotEmpty) SliverToBoxAdapter(child: _ItemRow(title: 'Shows', items: shows)),
      SliverToBoxAdapter(child: _PersonCollections(titles: data.children)),
    ];
  }

  /// Their best-rated title's, blurred.
  @override
  JellyfinItem? backdropOf(DetailData data) => _personBackdrop(data.children);

  @override
  bool get blurBackdrop => true;

  @override
  bool get edgeToEdge => true;

  @override
  bool get noAppBar => true;

}

/// A collection, over its backdrop: logo, details (count, years, age rating, description,
/// genres) and its movies.
class CollectionLayout extends DetailLayout {
  const CollectionLayout();

  @override
  List<Widget> buildSlivers(BuildContext context, DetailData data) => [
    SliverToBoxAdapter(child: _HeroTitle(item: data.item)),
    SliverToBoxAdapter(
      child: _CollectionInfoCard(collection: data.item, items: data.children),
    ),
  ];

  @override
  JellyfinItem? backdropOf(DetailData data) => data.item;

  @override
  bool get edgeToEdge => true;

  @override
  bool get noAppBar => true;
}

/// A movie, over its backdrop: logo, details (year, runtime, age rating, score, Play,
/// description, genres, cast), the collections it's in, more like it, and its media info.
class MovieLayout extends DetailLayout {
  const MovieLayout();

  @override
  List<Widget> buildSlivers(BuildContext context, DetailData data) => [
    SliverToBoxAdapter(child: _HeroTitle(item: data.item)),
    SliverToBoxAdapter(child: _MovieInfoCard(movie: data.item)),
    SliverToBoxAdapter(child: _RelatedRows(item: data.item)),
    SliverToBoxAdapter(child: _MediaInfo(item: data.item)),
  ];

  @override
  JellyfinItem? backdropOf(DetailData data) => data.item;

  @override
  bool get edgeToEdge => true;

  @override
  bool get noAppBar => true;
}

/// A series, over its backdrop: logo, details (years, seasons, age rating, score, description,
/// genres), its seasons as a row of posters (each opening its own page), then the collections
/// it's in and more like it.
class SeriesLayout extends DetailLayout {
  const SeriesLayout();

  @override
  List<Widget> buildSlivers(BuildContext context, DetailData data) => [
    SliverToBoxAdapter(child: _HeroTitle(item: data.item)),
    SliverToBoxAdapter(
      child: _SeriesInfoCard(series: data.item, seasons: data.children),
    ),
    if (data.children.isNotEmpty)
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: pageSides(context, extra: 12), child: const _CardDivider()),
            // Named underneath: a season's poster doesn't always say which it is.
            _ItemRow(title: 'Seasons', items: data.children, view: LibraryView.poster, top: 8, captioned: true),
          ],
        ),
      ),
    SliverToBoxAdapter(child: _RelatedRows(item: data.item)),
  ];

  @override
  JellyfinItem? backdropOf(DetailData data) => data.item;

  @override
  bool get edgeToEdge => true;

  @override
  bool get noAppBar => true;
}

/// A season, over its show's backdrop: the season's poster, Play, Trailer, Favorite and Mark
/// as watched, its description, the cast, then its episodes.
class SeasonLayout extends DetailLayout {
  const SeasonLayout();

  JellyfinItem _series(DetailData data) => (data.extra['series'] as JellyfinItem?) ?? data.item;

  @override
  List<Widget> buildSlivers(BuildContext context, DetailData data) => [
    SliverToBoxAdapter(child: _SeasonHero(season: data.item, series: _series(data))),
    SliverToBoxAdapter(
      child: _SeasonInfoCard(season: data.item, series: _series(data), episodes: data.children),
    ),
  ];

  @override
  JellyfinItem? backdropOf(DetailData data) => _series(data);

  @override
  bool get edgeToEdge => true;

  @override
  bool get noAppBar => true;
}

// To add a new kind of page later, add a layout here, for example:
//
// class AlbumLayout extends DetailLayout {
//   const AlbumLayout();
//
//   @override
//   List<Widget> buildSlivers(BuildContext context, DetailData data) => [
//     // cover art, artist, track list...
//   ];
// }

// ─── The page ────────────────────────────────────────────────────────────────

/// A detail page: loads its data, shows loading and errors, and hands the result to a layout.
class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.load, required this.layout, this.cacheKey});

  /// Fetches the page's data. Called on open and on "Try again".
  final DetailLoader load;

  final DetailLayout layout;

  /// When set, the page's data is cached under this key and reused for 10 minutes.
  final String? cacheKey;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  DetailData? _data;
  bool _loading = true;
  String? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();

    // Show cached data straight away; refresh quietly if it's old.
    final key = widget.cacheKey;
    final cached = key == null ? null : appCache.peek(key, fromJson: DetailData.fromJson);
    if (cached != null) {
      _data = cached;
      _loading = false;
      _focusFirst();
    }
    if (key == null || !appCache.isFresh(key)) _load(silent: cached != null);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _start.dispose();
    super.dispose();
  }

  /// [silent] refreshes in the background, keeping current content on screen instead of a spinner.
  Future<void> _load({bool silent = false}) async {
    final client = jellyfin.client;
    if (client == null) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await widget.load(client);
      if (widget.cacheKey case final key?) {
        appCache.put(key, data, toJson: data.extra.isEmpty ? DetailData.toJson : null);
      }
      if (mounted) {
        final first = _data == null;
        setState(() => _data = data);
        if (first) _focusFirst();
      }
    } on JellyfinException catch (e) {
      if (mounted && !silent) setState(() => _error = describeJellyfinError(e)); // keep cached content on failure
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Where a page starts with a remote or keyboard: its Play button, or a person's first title
  /// ([_StartsHere]). Not while a touch screen is in use (a tablet too), which has nothing to show
  /// focus for.
  final _start = FocusNode(canRequestFocus: false, skipTraversal: true);

  /// Once the content is in, focus goes to where the page starts ([_start]), or else the first
  /// thing on it, unless the remote already moved it somewhere on the page.
  void _focusFirst() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
      final scope = FocusScope.of(context);
      final focused = FocusManager.instance.primaryFocus;
      if (focused != null && focused != scope && focused.ancestors.contains(scope)) return;
      final start = _start.traversalDescendants.firstOrNull;
      if (start != null) {
        start.requestFocus();
      } else {
        scope.nextFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Its name in the app's top bar.
    if (detailTitleOf(ModalRoute.of(context)) case final title?) {
      final name = _data?.item.name;
      if (title.value != name) WidgetsBinding.instance.addPostFrameCallback((_) => title.value = name);
    }
    final topPadding = widget.layout.topPadding;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null || _data == null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Text(_error ?? 'Nothing to show'),
            FilledButton(
              onPressed: _load,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    } else {
      body = CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: topPadding)),
          ...widget.layout.buildSlivers(context, _data!),
          // Room under the last section, so its last row can come up off the bottom edge.
          SliverToBoxAdapter(child: SizedBox(height: pageBottom(context, 64))),
        ],
      );
    }

    body = _StartFocus(node: _start, child: body);

    // Back is in the app's top bar (TVs use the remote's; computers can also use Esc or the
    // mouse's back button, see _GoBackKeys).
    final backdrop = _data == null ? null : widget.layout.backdropOf(_data!);
    if (widget.layout.noAppBar) {
      final Widget page;
      if (!widget.layout.edgeToEdge) {
        page = Padding(padding: pageSides(context, extra: 12), child: body);
      } else {
        // No side padding here: each part adds its own, so rows can scroll to the screen's edge.
        page = Stack(
          children: [
            if (backdrop != null)
              Positioned.fill(
                child: _PageBackdrop(item: backdrop, scroll: _scroll, blurred: widget.layout.blurBackdrop),
              ),
            _BackdropScope(child: body),
          ],
        );
      }
      return Scaffold(body: _GoBackKeys(child: page));
    }

    final title = _data == null ? null : widget.layout.headerTitle(_data!);

    return Scaffold(
      // Moved down by the same room as other pages get above their content.
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight + pageTop(context) - 12),
        child: Padding(
          padding: EdgeInsets.only(top: pageTop(context) - 12),
          child: AppBar(
            automaticallyImplyLeading: false, // Back is in the app's top bar
            title: title == null ? null : Text(title),
          ),
        ),
      ),
      body: _GoBackKeys(
        child: Padding(padding: pageSides(context, extra: 12), child: body),
      ),
    );
  }
}

/// Esc, or a mouse's back button, goes back from a page.
class _GoBackKeys extends StatelessWidget {
  const _GoBackKeys({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (event.buttons & kBackMouseButton != 0) Navigator.of(context).maybePop();
    },
    child: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: child, // (the page focuses its start, so Esc works straight away)
    ),
  );
}

/// Hands [_StartsHere] the page's start node.
class _StartFocus extends InheritedWidget {
  const _StartFocus({required this.node, required super.child});

  final FocusNode node;

  @override
  bool updateShouldNotify(_StartFocus old) => old.node != node;
}

/// Marks where a page starts with a remote or keyboard: the first thing in [child] that takes
/// focus (Play, or a person's first title). One per page.
class _StartsHere extends StatelessWidget {
  const _StartsHere({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final node = context.dependOnInheritedWidgetOfExactType<_StartFocus>()?.node;
    if (node == null) return child;
    return Focus(focusNode: node, canRequestFocus: false, skipTraversal: true, child: child);
  }
}
