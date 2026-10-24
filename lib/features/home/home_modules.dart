import 'dart:async';
import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/app_icons.dart';
import '../../core/focus/focus_rows.dart';
import 'home_layout.dart';
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
import '../library/item_menu.dart';
import '../library/poster_card.dart';
import '../previews/frames_preview.dart';
import '../../core/focus/scroll_into_view.dart';
import '../../theme/theme.dart';
import '../../widgets/remote_text_field.dart';

// ─── Definitions ─────────────────────────────────────────────────────────────

/// What a section loaded: its items, and optionally a title that replaces the default
/// (e.g. "Because you watched Dune").
class HomeModuleContent {
  const HomeModuleContent(this.items, {this.title});

  final List<JellyfinItem> items;
  final String? title;

  static Object? toJson(HomeModuleContent c) => {'items': itemsToJson(c.items), 'title': c.title};

  static HomeModuleContent fromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return HomeModuleContent(itemsFromJson(map['items']), title: map['title'] as String?);
  }
}

/// Loads a section's content. [module] says what it shows (e.g. which collection).
typedef HomeModuleLoader = Future<HomeModuleContent> Function(
    JellyfinClient client,
    HomeModule module,
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
    load: (_, _) async => const HomeModuleContent([]), // drawn from the libraries, already loaded
  ),
  HomeModuleType.continueWatching: HomeModuleSpec(
    title: 'Continue Watching',
    description: "Movies and episodes you've started",
    icon: (i) => i.continueWatching,
    view: LibraryView.thumbnail,
    load: (client, _) async => HomeModuleContent(
      (await client.items.resume(mediaTypes: const ['Video'], limit: 20)).items,
    ),
  ),
  HomeModuleType.nextUp: HomeModuleSpec(
    title: 'Next Up',
    description: "The next episode of shows you're watching",
    icon: (i) => i.shows,
    view: LibraryView.thumbnail,
    load: (client, _) async => HomeModuleContent(
      (await client.tvShows.nextUp(
        enableTotalRecordCount: false,
        limit: 20,
        enableResumable: false,
      )) // in-progress episodes are in Continue Watching
          .items
          .where((item) => item.type == JellyfinItemKind.episode && !hiddenFromNextUp().contains(item.id))
          .toList(),
    ),
  ),
  HomeModuleType.favorites: HomeModuleSpec(
    title: 'Favorites',
    description: 'Your favorite movies and shows',
    icon: (i) => i.favorite,
    load: (client, _) async => HomeModuleContent(
      await client.items.listEach(
        filters: const ['IsFavorite'],
        types: const [..._moviesAndShows, 'BoxSet'],
        sortBy: const['Random'],
        limit: 30,
        fields: const ['RecursiveItemCount'],
      ),
    ),
  ),
  HomeModuleType.recentlyAdded: HomeModuleSpec(
    title: 'Recently Added',
    description: 'The newest movies and shows on your server',
    icon: (i) => i.recentlyAdded,
    load: (client, _) async => HomeModuleContent(
      await client.items.listEach(
        types: _moviesAndShows,
        sortBy: const ['DateCreated'],
        descending: true,
        limit: 30,
        fields: const ['RecursiveItemCount'],
      ),
    ),
  ),
  HomeModuleType.recentlyAddedMovies: HomeModuleSpec(
    title: 'Recently Added Movies',
    description: 'The newest movies on your server',
    icon: (i) => i.movies,
    load: (client, _) async => HomeModuleContent(
      (await client.items.list(
        enableTotalRecordCount: false,
        includeItemTypes: const [JellyfinItemKind.movie],
        recursive: true,
        sortBy: const ['DateCreated'],
        descending: true,
        limit: 30,
      )).items,
    ),
  ),
  HomeModuleType.recentlyAddedSeries: HomeModuleSpec(
    title: 'Recently Added Shows',
    description: 'Shows with the newest episodes',
    icon: (i) => i.shows,
    load: (client, _) async => HomeModuleContent(
      (await client.items.list(
        enableTotalRecordCount: false,
        includeItemTypes: const [JellyfinItemKind.series],
        recursive: true,
        sortBy: const ['DateLastContentAdded'],
        descending: true,
        limit: 30,
        fields: const ['RecursiveItemCount'],
      )).items,
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
    description: 'More like the last thing you watched',
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

/// A random handful of movies and shows that have backdrop art to show off.
Future<HomeModuleContent> _featured(JellyfinClient client, HomeModule _) async {
  final items = await client.items.listEach(
    types: _moviesAndShows,
    sortBy: const ['Random'],
    limit: 30, // more than needed, since some won't have a backdrop
    fields: const ['Overview'],
  );
  final withArt = items
      .where(
        (item) => (item.raw['BackdropImageTags'] as List?)?.isNotEmpty ?? false,
  )
      .take(8)
      .toList();
  return HomeModuleContent(withArt);
}

/// Jellyfin's suggestions for this user, or a random mix when there isn't enough history yet.
Future<HomeModuleContent> _suggested(
    JellyfinClient client,
    HomeModule _,
    ) async {
  var items = (await client.suggestions.list(
    enableTotalRecordCount: false,
    mediaType: const ['Video'],
    type: _moviesAndShows,
    limit: 30,
  )).items;
  if (items.isEmpty) {
    items = await client.items.listEach(
      types: _moviesAndShows,
      sortBy: const ['Random'],
      limit: 30,
      fields: const ['RecursiveItemCount'],
    );
  }
  return HomeModuleContent(items);
}

/// Titles similar to the last movie or show you watched: same kind, sharing its genres.
Future<HomeModuleContent> _becauseYouWatched(
    JellyfinClient client,
    HomeModule _,
    ) async {
  final last = (await client.items.list(
    enableTotalRecordCount: false,
    filters: const ['IsPlayed'],
    includeItemTypes: const [JellyfinItemKind.movie, JellyfinItemKind.episode],
    recursive: true,
    sortBy: const ['DatePlayed'],
    descending: true,
    limit: 1,
  )).items.firstOrNull;
  if (last == null) return const HomeModuleContent([]);

  final isEpisode = last.type == JellyfinItemKind.episode;
  final baselineId = isEpisode ? last.raw['SeriesId'] as String? : last.id;
  if (baselineId == null) return const HomeModuleContent([]);
  final baseline = await client.items.byId(baselineId);
  if (baseline == null) return const HomeModuleContent([]);

  final title = 'Because You Watched ${baseline.name}';
  final genres =
  ((baseline.raw['Genres'] as List?)?.cast<String>() ?? const <String>[])
      .take(2)
      .toList();
  if (genres.isEmpty) return HomeModuleContent(const [], title: title);

  final similar = await client.items.list(
    enableTotalRecordCount: false,
    genres: genres,
    includeItemTypes: [
      isEpisode ? JellyfinItemKind.series : JellyfinItemKind.movie,
    ],
    excludeItemIds: [baseline.id],
    recursive: true,
    sortBy: const ['Random'],
    limit: 20,
    fields: const ['RecursiveItemCount'],
  );
  return HomeModuleContent(similar.items, title: title);
}

/// The movies in the chosen collection, in release order.
Future<HomeModuleContent> _collection(
    JellyfinClient client,
    HomeModule module,
    ) async {
  final id = module.param;
  if (id == null) return const HomeModuleContent([]);
  final page = await client.items.list(
    enableTotalRecordCount: false,
    parentId: id,
    // Just what's in the collection: a show, not its seasons and every episode as well.
    recursive: false,
    sortBy: const ['ProductionYear', 'SortName'],
    limit: 50,
    fields: const ['RecursiveItemCount'],
  );
  return HomeModuleContent(page.items, title: module.label);
}

/// A random mix of movies and shows from the chosen genre.
Future<HomeModuleContent> _genre(
    JellyfinClient client,
    HomeModule module,
    ) async {
  final genre = module.param;
  if (genre == null) return const HomeModuleContent([]);
  final items = await client.items.listEach(
    genres: [genre],
    types: _moviesAndShows,
    sortBy: const ['Random'],
    limit: 30,
    fields: const ['RecursiveItemCount'],
  );
  return HomeModuleContent(items, title: genre);
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

  @override
  void initState() {
    super.initState();
    favoritesChanged.addListener(_load);
    homeVisible.addListener(_refreshIfStale);
    watchProgressChanged.addListener(_onWatched);

    _content = appCache.peek(_cacheKey(widget.module.id), fromJson: HomeModuleContent.fromJson);
    if (!appCache.isFresh(_cacheKey(widget.module.id))) _load();
  }

  @override
  void dispose() {
    favoritesChanged.removeListener(_load);
    homeVisible.removeListener(_refreshIfStale);
    watchProgressChanged.removeListener(_onWatched);
    _widen.dispose();
    _rowScroll.dispose();
    super.dispose();
  }

  void _onWatched() {
    if (widget.module.type.followsProgress) _load();
  }

  void _refreshIfStale() {
    if (!appCache.isFresh(_cacheKey(widget.module.id))) _load();
  }

  Future<void> _load() async {
    final client = jellyfin.client;
    if (client == null) return;
    try {
      final content = await _spec.load(client, widget.module);
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
    if (widget.module.type != HomeModuleType.carousel)
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
    IconButton(
      onPressed: () => homeLayout.remove(widget.module.id),
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

    // Loaded and empty: hidden entirely, unless you're editing (then it says so).
    if (!widget.editing &&
        (isMyMedia
            ? jellyfin.libraries.isEmpty
            : _error == null && (_content?.items.isEmpty ?? false))) {
      return const SizedBox.shrink();
    }

    final title =
        _content?.title ?? module.label ?? module.param ?? _spec.title;
    final captions =
        module.type == HomeModuleType.continueWatching ||
            module.type == HomeModuleType.nextUp;

    return ScrollIntoViewOnFocus(
      child: Padding(
        padding: const EdgeInsets.only(
          bottom: 24,
        ), // every visible section: the same gap below it
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            if (!isCarousel || widget.editing)
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
              _MyMediaRow(sides: _rowSides(context))
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
      content = _Carousel(items: items);
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
            final card = Focus(
              // Doesn't take focus itself: notices the card getting it, and scrolls the row.
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (focused) {
                if (focused) _keepInSlot(context, i, tileWidth);
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
                  ? tileWidth + (imageHeight * 16 / 9 - tileWidth) * _widenCurve.transform(_widen.value)
                  : tileWidth,
              child: captions
                  ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: imageHeight, child: card),
                  _TileCaption(items[i]),
                ],
              )
                  : card,
            );
          },
        ),
      );
    }

    // Scrolled along with a remote, the card before the first one in view would peek out of
    // the margin as a sliver. Phones keep rows running to the edge, for swiping.
    if (!ScreenType.of(context).isPhone) {
      content = ClipRect(clipper: _LeftMarginClipper(pageSides(context).left / 2), child: content);
    }
    return SizedBox(height: rowHeight, child: content);
  }

  /// The space between a row's tiles.
  static const _rowGap = 4.0;

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

  /// A tile's width in a row. Bigger on wider screens (a TV is watched from across the room),
  /// where posters and thumbnails are the same height, so a poster widened for its preview is
  /// a thumbnail's size. Phones keep theirs.
  static double _tileWidth(BuildContext context, LibraryView view) {
    final isPhone = ScreenType.of(context).isPhone;
    return switch (view) {
      LibraryView.poster => isPhone ? 150.0 : PosterCard.height * 2 / 3, // 147 × 220
      LibraryView.thumbnail => isPhone ? 280.0 : PosterCard.height * 16 / 9, // 391 × 220
    };
  }

  /// A row's padding at its ends: the first card in line with the section's title, and the
  /// same room after the last one when the row is scrolled to its end.
  static EdgeInsets _rowSides(BuildContext context) {
    final sides = pageSides(context);
    return sides.copyWith(right: sides.left);
  }
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
  const _Carousel({required this.items});

  final List<JellyfinItem> items;

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  static const _interval = Duration(seconds: 8);

  /// While someone's on the carousel it holds still, unless they've been idle this long
  /// (probably walked away), after which it resumes advancing.
  static const _idleResume = Duration(seconds: 45);

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  bool _engaged = false; // focus or pointer is on the carousel
  bool _stills = false; // the showing slide's stills are playing

  /// The showing slide's stills have played through: they aren't started again.
  bool _stillsDone = false;

  /// After the stills: the slide stays one interval, then the next comes.
  Timer? _afterStills;
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
    _afterStills?.cancel();
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
      // Stills playing hold the slide until they're finished (see _onStillsFinished).
      if (_stills || _stillsDone) return; // after them, _afterStills moves on
      final idle = DateTime.now().difference(_lastInteraction);
      if (_engaged && idle < _idleResume) return; // someone's here: hold still
      _goTo(_page + 1);
    });
  }

  void _setEngaged(bool engaged) {
    if (engaged != _engaged && mounted) setState(() => _engaged = engaged); // the stills follow it
    _touch();
    if (!engaged) _restartTimer(); // leaving: a full 8 seconds before the next slide
  }

  /// The showing slide's stills have played through once: the backdrop comes back, the slide
  /// stays one interval, then the next comes. Its own stills start after the usual moment.
  void _onStillsFinished() {
    setState(() {
      _stills = false;
      _stillsDone = true;
    });
    _afterStills?.cancel();
    _afterStills = Timer(_interval, () => _goTo(_page + 1));
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
                  _stills = false; // the last slide's stills stopped with it
                  _stillsDone = false;
                  _afterStills?.cancel();
                  _restartTimer();
                  if (refocus != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) refocus.requestFocus();
                    });
                  }
                },
                itemBuilder: (context, i) => _CarouselSlide(
                  item: widget.items[i],
                  // The showing slide's stills, while someone's on the carousel.
                  previewing: _engaged && i == _page && !_stillsDone,
                  onStills: (playing) {
                    if (i != _page) return;
                    _stills = playing;
                    if (!playing) _restartTimer(); // a full interval before the next slide
                  },
                  onStillsFinished: () {
                    if (i == _page) _onStillsFinished();
                  },
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
    this.previewing = false,
    this.onStills,
    this.onStillsFinished,
  });

  final JellyfinItem item;
  final bool previewing;

  /// Told when this slide's stills start (true) and stop (false) showing.
  final ValueChanged<bool>? onStills;

  /// Told when this slide's stills have played through once.
  final VoidCallback? onStillsFinished;
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
            // After a moment on the carousel, stills from the title in place of the backdrop
            // (under the fades, so the text stays readable). Not on phones, which have no focus
            // or hover.
            if (!isPhone && FramesPreview.supports(item))
              FramesPreview(
                item: item,
                active: widget.previewing,
                onShowing: widget.onStills,
                onFinished: widget.onStillsFinished,
              ),
            // Everything over the artwork, stills or not.
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
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isPhone ? 180 : 360,
                            maxHeight: isPhone ? 48 : 96,
                          ),
                          child: logoTag != null
                              ? Image.network(
                            client.images.url(
                              itemId: item.id,
                              type: JellyfinImagesApi.typeLogo,
                              tag: logoTag,
                              fillWidth: 720,
                            ),
                            fit: BoxFit.contain,
                            alignment: Alignment.bottomLeft,
                            // The name instead, if the logo won't load (a saved page can ask for
                            // one the server has since replaced).
                            errorBuilder: (_, _, _) => title,
                          )
                              : title,
                        ),
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
  const _TileCaption(this.item);

  final JellyfinItem item;

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
    final title = isEpisode
        ? (item.raw['SeriesName'] as String?) ?? item.name
        : item.name;

    final subtitle = isEpisode
        ? episodeLabel(item.raw['ParentIndexNumber'], item.raw['IndexNumber'], item.name)
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
class _LeftMarginClipper extends CustomClipper<Rect> {
  const _LeftMarginClipper(this.left);

  final double left;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(left, -size.height, size.width * 2, size.height * 2);

  @override
  bool shouldReclip(_LeftMarginClipper old) => old.left != left;
}

// ─── My Media ────────────────────────────────────────────────────────────────

/// Your libraries as colored tiles, each with its icon and name, opening the library.
class _MyMediaRow extends StatelessWidget {
  const _MyMediaRow({required this.sides});

  final EdgeInsets sides; // the row's padding at its ends

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
    final isPhone = ScreenType.of(context).isPhone;
    final width = isPhone ? 150.0 : 210.0;
    final height = width * 9 / 16;
    final libraries = jellyfin.libraries;
    return SizedBox(
      height: height + 36,
      child: FocusRow(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: sides,
          clipBehavior: Clip.none, // a focused tile grows past the row's ends
          itemCount: libraries.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final library = libraries[i];
            return SizedBox(
              width: width,
              child: Tappable(
                onPress: () => context.go('/home/library/${library.id}'),
                semanticsLabel: library.name,
                builder: (context, states, child) {
                  final active = isHighlighted(states);
                  return Column(
                    spacing: 8,
                    children: [
                      AnimatedScale(
                        scale: active ? 1.05 : 1,
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: width,
                          height: height,
                          decoration: BoxDecoration(
                            color: _colors[i % _colors.length],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: active ? context.colors.onSurface : const Color(0x00000000),
                              width: 2.5,
                            ),
                          ),
                          child: child,
                        ),
                      ),
                      Text(
                        library.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyLarge,
                      ),
                    ],
                  );
                },
                child: Icon(libraryIcon(library.collectionType), size: height * 0.42, color: const Color(0xFFFFFFFF)),
              ),
            );
          },
        ),
      ),
    );
  }
}
