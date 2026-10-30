part of 'detail_page.dart';

// ─── Backdrop behind the whole page (collections, movies, series) ─────────────

/// Marks a page drawn over its title's backdrop: info cards then leave out their card, so the
/// details sit straight on the artwork.
class _BackdropScope extends InheritedWidget {
  const _BackdropScope({required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_BackdropScope>() != null;

  @override
  bool updateShouldNotify(_BackdropScope oldWidget) => false;
}

/// [item]'s backdrop behind the whole page. The picture stays put as the page scrolls; its fade
/// scrolls with the page ([scroll]), so the details always sit on it, however light the picture
/// is: clear at the top, darkening down to the details, and dimmed behind everything under them.
class _PageBackdrop extends StatelessWidget {
  const _PageBackdrop({required this.item, required this.scroll, this.blurred = false});

  final JellyfinItem item;
  final ScrollController scroll;

  /// Blurred: a backdrop that isn't the page's own (a person's, from one of their titles), so
  /// it sets a mood rather than showing a scene.
  final bool blurred;

  /// How much of the page's color is over the picture under the details: enough for any text to
  /// read, with the picture still faintly there.
  static const _dim = 0.9;

  /// How tall the artwork is on a phone [size]: 16:9 across its width, but no more than most of
  /// its height. Elsewhere it fills the page.
  static double heightIn(Size size) => math.min(size.width * 9 / 16, size.height * 0.9);

  @override
  Widget build(BuildContext context) {
    final tag = (item.raw['BackdropImageTags'] as List?)?.firstOrNull as String?;
    final background = Theme.of(context).scaffoldBackgroundColor;
    if (tag == null) return const SizedBox.shrink();
    final (:top, :length) = _fade(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The whole page (the top half, on a phone), the picture zoomed in as far as it needs to
        // fill it.
        final height = ScreenType.of(context).isPhone ? constraints.maxHeight / 2 : constraints.maxHeight;
        final pixels = View.of(context).physicalSize.width / MediaQuery.sizeOf(context).width;
        final image = Image.network(
          jellyfin.client!.images.url(
            itemId: item.id,
            type: JellyfinImagesApi.typeBackdrop,
            tag: tag,
            // Blurred, a small copy will do: it's cheap to blur, and to fetch.
            fillWidth: blurred ? 480 : ((constraints.maxWidth * pixels / 320).ceil() * 320).clamp(640, 3840),
            quality: 90,
          ),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            // ── The picture, staying put ──
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: height,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (blurred)
                      // A small picture, blurred a little and dimmed: light enough for a TV to draw.
                      // Clipped: a blur spreads past the picture's edges.
                      ClipRect(
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12, tileMode: TileMode.clamp),
                          child: image,
                        ),
                      )
                    else
                      image,
                    if (blurred) ColoredBox(color: background.withValues(alpha: 0.35)),
                    // Its foot fades into the page, so where a short one ends never shows as an edge.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.75, 1],
                          colors: [background.withValues(alpha: 0), background],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── The fade, scrolling with the page ──
            AnimatedBuilder(
              animation: scroll,
              builder: (context, _) {
                final start = top - (scroll.hasClients ? scroll.offset : 0.0);
                if (start >= constraints.maxHeight) return const SizedBox.shrink();
                // One box from the fade's start to the bottom (two meeting would leave a seam): the
                // fade over its first [length], then the dim on down.
                final box = constraints.maxHeight - start;
                final end = (length / box).clamp(0.0, 1.0);
                return Stack(
                  children: [
                    Positioned(
                      top: start,
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            // A long, gentle fade, so its start never shows as an edge.
                            stops: [
                              for (final t in const [0.0, 0.3, 0.55, 0.75, 1.0]) t * end,
                              1,
                            ],
                            colors: [
                              background.withValues(alpha: 0),
                              background.withValues(alpha: 0.25),
                              background.withValues(alpha: 0.55),
                              background.withValues(alpha: 0.75),
                              background.withValues(alpha: _dim),
                              background.withValues(alpha: _dim),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Where the backdrop's fade starts, down the page (before it scrolls), and how long it is. Over
/// the room above the details, so the picture shows clearly there, and as dark as it gets a
/// little below where the details start.
({double top, double length}) _fade(BuildContext context) {
  // A phone's: down the lower half of its half-page picture, as dark as it gets at its foot.
  if (ScreenType.of(context).isPhone) {
    final half = MediaQuery.sizeOf(context).height / 2;
    return (top: half * 0.5, length: half * 0.5);
  }
  // The details' top (see _SplitHero): the fade 3/4 of the way by then.
  final details = _heroTop + _splitTop(context);
  return (top: details - 200, length: 280.0);
}

/// Above the first part of a title's page (DetailLayout.topPadding), and under its logo.
const _heroTop = 24.0;
const _heroBottom = 8.0;

/// How tall the room for the artwork above a title's details is, its logo (or name) at the
/// bottom: on TVs and tablets, down to where a season's poster or a person's photo ends on their
/// pages (see [_heroPoster]), so the logo sits as low as those do, further over the fade, where
/// it's easier to read; and never up by the top bar's buttons.
double _heroRoom(BuildContext context, {bool hasBackdrop = true}) {
  final room = _artworkRoom(context, hasBackdrop: hasBackdrop);
  // Phones: the logo at the foot of the artwork's room itself, close under the fade (lower, the
  // backdrop is short enough on a phone to leave a gap between the two).
  if (ScreenType.of(context).isPhone) return math.max(room, _clearOfTopBar(context) + _HeroTitle.logoBox(context));
  final (:above, :posterHeight) = _heroPoster(context, room);
  return above + posterHeight;
}

/// The room for a page's backdrop above the details: most of it on phones, half of it elsewhere
/// (with the logo or picture at its foot running on down, more of the details show at first).
double _artworkRoom(BuildContext context, {bool hasBackdrop = true}) => hasBackdrop
    ? _PageBackdrop.heightIn(MediaQuery.sizeOf(context)) * (ScreenType.of(context).isPhone ? 0.7 : 0.5)
    : 0.0;

/// The top of a page over its backdrop: room to see the artwork, with the title's logo (or
/// name) at the bottom left.
class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.item});

  final JellyfinItem item;

  /// The tallest a logo gets (a season's poster and a person's photo start where its top would be).
  static double logoBox(BuildContext context) => TitleLogo.hero(ScreenType.of(context).isPhone).height;

  /// The title's logo, or its name where it has none, at the size a page's top has it, or as big
  /// as [room] allows.
  static Widget mark(BuildContext context, JellyfinItem item, {Size? room}) {
    final isPhone = ScreenType.of(context).isPhone;
    final logoTag = item.imageTags['Logo'];
    final name = Text(
      item.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: context.text.headlineMedium?.copyWith(
        color: const Color(0xFFFFFFFF),
        shadows: const [Shadow(blurRadius: 8, color: Color(0x99000000))],
      ),
    );
    if (logoTag == null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: room?.width ?? (isPhone ? 220 : 400)),
        child: name,
      );
    }
    return room == null
        ? TitleLogo(itemId: item.id, tag: logoTag, size: TitleLogo.hero(isPhone), fallback: name)
        : TitleLogo.upTo(
            itemId: item.id,
            tag: logoTag,
            size: room,
            fallback: name,
            // In the middle, on a phone (see _SplitHero).
            alignment: isPhone ? Alignment.topCenter : Alignment.topLeft,
          );
  }

  @override
  Widget build(BuildContext context) {
    final hasBackdrop = ((item.raw['BackdropImageTags'] as List?)?.isNotEmpty ?? false);
    final height = _heroRoom(context, hasBackdrop: hasBackdrop);
    return Padding(
      padding: pageSides(context, extra: 12).copyWith(bottom: _heroBottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Align(alignment: Alignment.bottomLeft, child: mark(context, item)),
      ),
    );
  }
}

/// Where a title's details end (see [_SplitHero]): on TVs and tablets their buttons most of the way
/// down the screen, so the artwork has the rest, and the next row's heading just shows below; on
/// phones, just clear of the bottom bar.
double _splitBottom(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  return (ScreenType.of(context).isPhone ? height - pageBottom(context, 24) : height * 0.83) - _heroTop;
}

/// About where a title's details start: [_splitBottom], less a logo at its tallest and the rest
/// at their usual size. For the backdrop's fade.
double _splitTop(BuildContext context) {
  // A phone's: its logo (or picture) over the foot of the half-page picture.
  if (ScreenType.of(context).isPhone) {
    final half = MediaQuery.sizeOf(context).height / 2;
    return math.max(half - _SplitHero.logoHeight(context) * 0.6, _clearOfTopBar(context));
  }
  return math.max(_splitBottom(context) - _SplitHero.logoHeight(context) - 20 - 40, _clearOfTopBar(context));
}

/// The top of a title's page on TVs and tablets, over its backdrop, in two rows:
///
///     LOGO                 | 2024  1h 34m  R  ★ 6.7
///                          | Description...
///     ▶ Play  ♡  ▶▶  ✓     | Genre  Genre  Genre
///
/// The logo (or a season's poster: [title], given the most room it can have) and what the title
/// is start along the same line; the buttons and the genres along the next. The buttons show
/// just their icons, so they stay on one line.
class _SplitHero extends StatelessWidget {
  const _SplitHero({
    required this.title,
    required this.about,
    this.description,
    this.titleSize,
    this.buttons,
    this.genres,
  });

  final Widget Function(Size room) title;
  final Widget? buttons; // none on a person's page
  final List<Widget> about; // what it is
  final Widget? genres;

  /// Under [about], filling the rest of the room beside [title] with as much as fits; "Read
  /// more" scrolls the rest in the same room (see [ExpandableText.fill]).
  final String? description;

  /// How big [title] is (a season's poster, a person's photo), if not a logo at its biggest: the
  /// details start just past it, and [about] and [description] have at most its height.
  final Size? titleSize;

  static const _gap = 48.0;

  /// The tallest a logo gets: a fifth of the page. On a phone, a season's poster and a person's
  /// photo are this tall too.
  static double logoHeight(BuildContext context) => MediaQuery.sizeOf(context).height * 0.2;

  /// On a phone, the most room the description has under the rest, before "Read more".
  static double descriptionHeight(BuildContext context) => MediaQuery.sizeOf(context).height * 0.18;

  @override
  Widget build(BuildContext context) => ScreenType.of(context).isPhone
      // A phone's: from the foot of the picture down.
      ? Padding(
          // A picture taller than a logo (a season's poster) ends where the logo would, so it
          // reaches further up the backdrop instead.
          padding: pageSides(context, extra: 12).copyWith(
            top: math.max(
              _splitTop(context) - math.max(0.0, (titleSize?.height ?? 0) - logoHeight(context)),
              _clearOfTopBar(context),
            ),
            bottom: 8,
          ),
          child: _stacked(context),
        )
      : Padding(
    padding: pageSides(context, extra: 12).copyWith(top: _clearOfTopBar(context), bottom: 8),
    // Down to [_splitBottom], from the bottom up (a taller description runs on down instead).
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: _splitBottom(context) - _clearOfTopBar(context)),
      child: Align(alignment: Alignment.bottomLeft, child: _rows(context)),
    ),
  );

  /// A phone's: one under another, as wide as the page. The logo (or picture) in the middle, then
  /// what it is, the buttons, the description, the genres.
  Widget _stacked(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _IconActions(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Center(child: title(titleSize ?? Size(constraints.maxWidth * 0.85, logoHeight(context)))),
          ...about,
          ?buttons,
          if (description case final text? when text.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: descriptionHeight(context)),
              child: ExpandableText.fill(text, style: context.text.bodyLarge),
            ),
          ?genres,
        ],
      ),
    ),
  );

  Widget _rows(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final left = titleSize?.width ?? (constraints.maxWidth - _gap) / 3;
      // As big as fits beside the description, and no taller than [logoHeight].
      final room = titleSize ?? Size(left, logoHeight(context));
      // [bottom]: both along the row's foot (what a title is, right above its genres).
      Widget row(Widget a, Widget? b, {bool bottom = false}) => Row(
        crossAxisAlignment: bottom ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        spacing: _gap,
        children: [
          SizedBox(
            width: left,
            child: Align(alignment: bottom ? Alignment.bottomLeft : Alignment.topLeft, child: a),
          ),
          Expanded(child: b ?? const SizedBox.shrink()),
        ],
      );
      return _IconActions(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 20,
          children: [
            // One row for a remote: ↑/↓ go past it (the photo to the titles under it), → from the
            // picture reaches "Read more".
            FocusRow(
              child: row(
                title(room),
                // Only as tall as it needs, up to the picture's height (a longer description
                // then ends in "Read more"), and down at the foot of the row.
                bottom: true,
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: room.height),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      ...about,
                      if (description case final text? when text.isNotEmpty)
                        Flexible(child: ExpandableText.fill(text, style: context.text.bodyLarge)),
                    ],
                  ),
                ),
              ),
            ),
            if (buttons != null || genres != null) row(buttons ?? const SizedBox.shrink(), genres),
          ],
        ),
      );
    },
  );
}

/// The top of a season's page over its show's backdrop: room to see the artwork, with the
/// season's poster (or the show's, if it has none) at the bottom left, where a title's logo goes.
class _SeasonHero extends StatelessWidget {
  const _SeasonHero({required this.season, required this.series});

  final JellyfinItem season;
  final JellyfinItem series;

  /// How tall [poster] is.
  static double posterHeight(BuildContext context, JellyfinItem series) {
    final hasBackdrop = ((series.raw['BackdropImageTags'] as List?)?.isNotEmpty ?? false);
    return _heroPoster(context, _artworkRoom(context, hasBackdrop: hasBackdrop)).posterHeight;
  }

  /// The season's poster (or the show's, if it has none), lifted off the artwork.
  static Widget poster(BuildContext context, JellyfinItem season, JellyfinItem series) {
    final posterHeight = _SeasonHero.posterHeight(context, series);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: DetailPoster(item: season.imageTags['Primary'] != null ? season : series, width: posterHeight * 2 / 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBackdrop = ((series.raw['BackdropImageTags'] as List?)?.isNotEmpty ?? false);
    final (:above, posterHeight: _) = _heroPoster(context, _artworkRoom(context, hasBackdrop: hasBackdrop));
    return Padding(
      padding: pageSides(context, extra: 12).copyWith(top: above, bottom: 8),
      child: Align(alignment: Alignment.bottomLeft, child: poster(context, season, series)),
    );
  }
}

/// Where a poster (a season's) or a photo (a person's) goes at the top of a page, in place of a
/// title's logo, given the room for the artwork above the details ([room]): its top where the
/// top of a show's logo would sit (the logo's box sits at the bottom of the same room), so it
/// starts as low and runs on down past it, clear of the top bar; and its height.
({double above, double posterHeight}) _heroPoster(BuildContext context, double room) {
  final isPhone = ScreenType.of(context).isPhone;
  return (
    above: math.max(room - _HeroTitle.logoBox(context), _clearOfTopBar(context)),
    // On a phone, 300 tall (less on a short screen): it ends where a logo would, growing up from
    // there (see _SplitHero).
    posterHeight: isPhone
        ? math.min(300.0, MediaQuery.sizeOf(context).height * 0.4)
        : (room * 0.85).clamp(180.0, 300.0),
  );
}

/// How far down a page's own artwork (a logo, a poster) starts at the least: below the app's top
/// bar and the status bar, however tall those are on this device, with a little room.
double _clearOfTopBar(BuildContext context) => TopBarSpace.of(context) + 16;

// ─── A person ────────────────────────────────────────────────────────────────

/// The top of a person's page, laid out like a title's: their photo and name where a title's
/// logo goes, over the backdrop, then when and where they were born (and died), how many of
/// their titles you have, and their biography.
class _PersonHero extends StatelessWidget {
  const _PersonHero({required this.person, required this.movies, required this.shows});

  final JellyfinItem person;
  final int movies;
  final int shows;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  /// Whole years from [from] to [to].
  static int _age(DateTime from, DateTime to) =>
      to.year - from.year - (to.month < from.month || (to.month == from.month && to.day < from.day) ? 1 : 0);

  /// "Born March 3, 1970 (age 55) in Dublin, Ireland", and "Died ..." when there's a date.
  List<String> get _lifeLines {
    final born = DateTime.tryParse((person.raw['PremiereDate'] as String?) ?? '');
    final died = DateTime.tryParse((person.raw['EndDate'] as String?) ?? '');
    final place = ((person.raw['ProductionLocations'] as List?)?.firstOrNull as String?)?.trim();
    return [
      if (born != null)
        [
          'Born ${_date(born)}',
          if (died == null) '(age ${_age(born, DateTime.now())})',
          if (place != null && place.isNotEmpty) 'in $place',
        ].join(' ')
      else if (place != null && place.isNotEmpty)
        'Born in $place',
      if (died != null) ['Died ${_date(died)}', if (born != null) '(age ${_age(born, died)})'].join(' '),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = ScreenType.of(context).isPhone;
    final muted = context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant);
    final bio = (person.raw['Overview'] as String?)?.trim();
    final counts = [
      if (movies > 0) '$movies ${movies == 1 ? 'movie' : 'movies'}',
      if (shows > 0) '$shows ${shows == 1 ? 'show' : 'shows'}',
    ];
    // The photo sized as a season's poster is, where a title's logo goes.
    final (above: _, :posterHeight) = _heroPoster(context, _artworkRoom(context));
    final shadow = const [Shadow(blurRadius: 8, color: Color(0x99000000))];

    // Their photo where a title's logo goes, their name and details beside it (under it, on a
    // phone).
    return _SplitHero(
        // Where the page starts with a remote; selecting it shows the photo full size.
        title: (_) => _StartsHere(child: _PersonPortrait(person: person, height: posterHeight)),
        titleSize: Size(posterHeight * 2 / 3, posterHeight),
        about: [
          Text(
            person.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (isPhone ? context.text.headlineMedium : context.text.displaySmall)?.copyWith(
              color: const Color(0xFFFFFFFF),
              shadows: shadow,
            ),
          ),
          for (final line in _lifeLines) Text(line, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (counts.isNotEmpty) Text('${counts.join(' · ')} in your library', style: muted),
        ],
        description: bio,
      );
  }
}

/// A person's photo as a rounded rectangle, lit up under the remote or pointer. Selecting it
/// shows it full size.
class _PersonPortrait extends StatelessWidget {
  const _PersonPortrait({required this.person, required this.height});

  final JellyfinItem person;
  final double height;

  String? _url(double height) {
    final tag = person.imageTags['Primary'];
    if (tag == null) return null;
    return jellyfin.client!.images.url(
      itemId: person.id,
      type: JellyfinImagesApi.typePrimary,
      tag: tag,
      fillHeight: height.round(),
      quality: 90,
    );
  }

  Widget _picture(BuildContext context, double height) {
    final url = _url(height * 2);
    return url == null
        ? ColoredBox(
            color: context.colors.surfaceContainerHighest,
            child: Center(
              child: Text(
                initialsOf(person.name),
                style: context.text.headlineSmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ),
          )
        : Image.network(url, fit: BoxFit.cover, alignment: Alignment.topCenter);
  }

  void _showFull(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final height = size.height * 0.8;
    showDialog<void>(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: height,
              width: math.min(height * 2 / 3, size.width * 0.9),
              child: _picture(context, height),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Tappable(
    onPress: () => _showFull(context),
    semanticsLabel: 'Photo of ${person.name}',
    builder: (context, states, child) {
      final active = isHighlighted(states);
      return AnimatedScale(
        scale: active ? 1.05 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: height,
          width: height * 2 / 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 4))],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? context.colors.primary : context.colors.primary.withValues(alpha: 0),
              width: PosterCard.borderWidth,
            ),
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
        ),
      );
    },
    child: _picture(context, height),
  );
}

// ─── Collections it's in, and more like it ───────────────────────────────────

/// A collection and what else is in it.
typedef _CollectionRow = ({JellyfinItem collection, List<JellyfinItem> items});

/// Every collection on the server, kept for a few minutes.
Future<List<JellyfinItem>>? _allCollections;
DateTime _allCollectionsAt = DateTime(0);

Future<List<JellyfinItem>> _collections() {
  if (_allCollections == null || DateTime.now().difference(_allCollectionsAt) > const Duration(minutes: 10)) {
    _allCollectionsAt = DateTime.now();
    _allCollections = () async {
      final json = await jellyfin.getJson(
        '/Items',
        query: {
          'userId': jellyfin.client!.userId!,
          'IncludeItemTypes': 'BoxSet',
          'Recursive': 'true',
          'Fields': 'ProviderIds',
          'EnableTotalRecordCount': 'false',
        },
      );
      return [for (final j in ((json as Map)['Items'] as List)) JellyfinItem.fromJson(j as Map<String, dynamic>)];
    }();
    _allCollections!.catchError((Object _) {
      _allCollections = null; // try again next time
      return const <JellyfinItem>[];
    });
  }
  return _allCollections!;
}

Future<List<JellyfinItem>> _collectionItems(String collectionId) async => (await jellyfin.client!.items.list(
  enableTotalRecordCount: false,
  parentId: collectionId,
  recursive: false,
  sortBy: const ['ProductionYear', 'SortName'],
  limit: 200,
  fields: const ['ProductionYear'],
)).items;

/// What's in every collection: collection id → its titles. Built once (every collection
/// looked through, a few at a time) and kept for half an hour, so a title's or a person's page
/// can find their collections straight away, however many there are.
Future<Map<String, List<JellyfinItem>>>? _collectionContents;
DateTime _collectionContentsAt = DateTime(0);

Future<Map<String, List<JellyfinItem>>> _contentsOfCollections() {
  if (_collectionContents == null ||
      DateTime.now().difference(_collectionContentsAt) > const Duration(minutes: 30)) {
    _collectionContentsAt = DateTime.now();
    _collectionContents = () async {
      final all = await _collections();
      final contents = <String, List<JellyfinItem>>{};
      // Six at a time: quick, without flooding the server.
      for (var i = 0; i < all.length; i += 6) {
        await Future.wait([
          for (final c in all.skip(i).take(6))
            _collectionItems(c.id).then((items) => contents[c.id] = items, onError: (Object _) => const <JellyfinItem>[]),
        ]);
      }
      return contents;
    }();
    _collectionContents!.catchError((Object _) {
      _collectionContents = null; // try again next time
      return const <String, List<JellyfinItem>>{};
    });
  }
  return _collectionContents!;
}

/// The collections [item] is in, each with the rest of what's in it.
Future<List<_CollectionRow>> _collectionsWith(JellyfinItem item) async {
  final all = await _collections();
  final contents = await _contentsOfCollections();
  return [
    for (final c in all)
      if (contents[c.id] case final items? when items.any((i) => i.id == item.id))
        if ([for (final i in items) if (i.id != item.id) i] case final rest when rest.isNotEmpty)
          (collection: c, items: rest),
  ];
}

/// The collections any of [titles] are in (a person's: everything they're in), in name order.
Future<List<JellyfinItem>> _collectionsWithAny(List<JellyfinItem> titles) async {
  final ids = {for (final t in titles) t.id};
  final all = await _collections();
  final contents = await _contentsOfCollections();
  return [
    for (final c in all)
      if (contents[c.id]?.any((i) => ids.contains(i.id)) ?? false) c,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// A person's collections: a row of the collections their movies and shows are in. Nothing
/// until they're found, or if there are none.
class _PersonCollections extends StatefulWidget {
  const _PersonCollections({required this.titles});

  final List<JellyfinItem> titles;

  @override
  State<_PersonCollections> createState() => _PersonCollectionsState();
}

class _PersonCollectionsState extends State<_PersonCollections> {
  late final _found = _collectionsWithAny(widget.titles).catchError((Object _) => <JellyfinItem>[]);

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _found,
    builder: (context, snap) {
      final collections = snap.data ?? const <JellyfinItem>[];
      if (collections.isEmpty) return const SizedBox.shrink();
      return _ItemRow(title: 'Collections', items: collections);
    },
  );
}

/// The server's "more like this" for [item].
Future<List<JellyfinItem>> _similarTo(JellyfinItem item) async {
  final client = jellyfin.client!;
  final page = await client.library.similarItems(itemId: item.id, limit: 20, userId: client.userId);
  return page.items;
}

/// Under a title's details: a row for each collection it's in, then more like it (leaving
/// out what the collections already show).
class _RelatedRows extends StatefulWidget {
  const _RelatedRows({required this.item});

  final JellyfinItem item;

  @override
  State<_RelatedRows> createState() => _RelatedRowsState();
}

class _RelatedRowsState extends State<_RelatedRows> {
  late final Future<(List<_CollectionRow>, List<JellyfinItem>)> _related = () async {
    final collections = _collectionsWith(widget.item).catchError((Object _) => <_CollectionRow>[]);
    final similar = _similarTo(widget.item).catchError((Object _) => <JellyfinItem>[]);
    return together2(collections, similar);
  }();

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _related,
    builder: (context, snap) {
      final (collections, similar) = snap.data ?? (const <_CollectionRow>[], const <JellyfinItem>[]);
      final shown = {for (final c in collections) ...c.items.map((i) => i.id)};
      final more = [for (final i in similar) if (!shown.contains(i.id) && i.id != widget.item.id) i];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in collections) _ItemRow(title: c.collection.name, items: c.items, onTitle: () => openItem(context, c.collection)),
          if (more.isNotEmpty) _ItemRow(title: 'More like this', items: more),
        ],
      );
    },
  );
}

/// A titled row of cards that scrolls sideways, like Home's: it runs to the screen's edges,
/// starting in line with the page, and with the remote the focused card keeps its place
/// while the row moves under it. [onTitle] makes the title a link (a collection's page).
class _ItemRow extends StatefulWidget {
  const _ItemRow({
    required this.title,
    required this.items,
    this.onTitle,
    this.view,
    this.top = 24,
    this.captioned = false,
  });

  final String title;
  final List<JellyfinItem> items;
  final VoidCallback? onTitle;

  /// Always this view (a show's seasons: posters), rather than the poster/thumbnail setting.
  final LibraryView? view;

  final double top; // room above it

  /// Each card's name under it (a show's seasons, whose posters don't always say which).
  final bool captioned;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  final _scroll = ScrollController();

  static const _gap = CardRows.gap;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The row's padding at its ends, as Home's rows have.
  EdgeInsets _sides(BuildContext context) => CardRows.sides(context);

  @override
  Widget build(BuildContext context) {
    final view = widget.view ?? libraryViewFor(context);
    final items = widget.items;
    // The same size as Home's cards.
    final width = CardRows.tileWidth(context, view);
    final height = CardRows.imageHeight(context, view);
    // Bold, as a show's name under Home's cards is.
    final captionStyle = context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    // A line of text and the room above it.
    final captionHeight = widget.captioned ? 6 + lineHeightOf(context, captionStyle) + 1 : 0.0;
    final heading = Text(widget.title, style: context.text.titleLarge);
    Widget row = FocusSlotRow(
      controller: _scroll,
      // Inside the list, so the first card lines up with the page but cards still scroll
      // right to the screen's edge.
      padding: _sides(context),
      itemCount: items.length,
      itemWidth: width,
      frameFor: (_) => SlotFrame(width: width, height: height, borderWidth: PosterCard.borderWidth),
      separatorBuilder: (_, _) => const SizedBox(width: _gap),
      itemBuilder: (context, i) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: height,
              child: PosterCard(
                item: items[i],
                view: view,
                // The first card grows away from the screen's left edge, the last away from its right.
                anchor: i == 0
                    ? Alignment.centerLeft
                    : i == items.length - 1
                    ? Alignment.centerRight
                    : Alignment.center,
                onPress: () => openItem(context, items[i]),
              ),
            ),
            if (widget.captioned)
              Padding(
                // Centered under the card's picture, which rests in from its edges.
                padding: const EdgeInsets.only(top: 6, left: 8, right: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    items[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: captionStyle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: widget.top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Padding(
            padding: pageSides(context, extra: 12), // in line with the rest of the page
            child: widget.onTitle == null
                ? heading
                : Tappable(
                    onPress: widget.onTitle!,
                    builder: (context, states, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: [
                        DefaultTextStyle.merge(
                          style: TextStyle(color: isHighlighted(states) ? context.colors.primary : null),
                          child: heading,
                        ),
                        Icon(appIcons.forward, size: 20, color: isHighlighted(states) ? context.colors.primary : null),
                      ],
                    ),
                  ),
          ),
          ScrollIntoViewOnFocus(child: SizedBox(height: height + captionHeight, child: row)),
        ],
      ),
    );
  }
}

// ─── Media info ──────────────────────────────────────────────────────────────

/// The file behind a title: its video, audio and subtitle tracks, and its size, as the server
/// describes them.
class _MediaInfo extends StatelessWidget {
  const _MediaInfo({required this.item});

  final JellyfinItem item;

  static String _size(num bytes) =>
      bytes >= 1e9 ? '${(bytes / 1e9).toStringAsFixed(1)} GB' : '${(bytes / 1e6).toStringAsFixed(0)} MB';

  @override
  Widget build(BuildContext context) {
    final sources = (item.raw['MediaSources'] as List?) ?? const [];
    final source = sources.firstOrNull;
    if (source is! Map) return const SizedBox.shrink();
    final streams = [for (final s in (source['MediaStreams'] as List?) ?? const []) if (s is Map) s];
    List<String> titles(String type) => [
      for (final s in streams)
        if (s['Type'] == type) ((s['DisplayTitle'] as String?) ?? (s['Codec'] as String? ?? '').toUpperCase()),
    ];
    final video = titles('Video');
    final audio = titles('Audio');
    final subtitles = titles('Subtitle');
    final file = [
      if ((source['Container'] as String?)?.isNotEmpty ?? false) (source['Container'] as String).toUpperCase(),
      if (source['Size'] case final num size) _size(size),
      if (source['Bitrate'] case final num bitrate) '${(bitrate / 1e6).toStringAsFixed(1)} Mbps',
      if (sources.length > 1) '${sources.length} versions',
    ].join('  ·  ');
    if (video.isEmpty && audio.isEmpty && file.isEmpty) return const SizedBox.shrink();

    final muted = context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant);
    final isPhone = ScreenType.of(context).isPhone;
    Widget line(String label, List<String> values) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: isPhone ? 84 : 120, child: Text(label, style: muted)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [for (final v in values) Text(v, style: context.text.bodyMedium)],
          ),
        ),
      ],
    );
    const most = 6;
    List<String> capped(List<String> values) =>
        values.length <= most ? values : [...values.take(most), '+${values.length - most} more'];

    // A box the remote can land on, so it can reach (and scroll to) the end of the page: a
    // border shows while it's there. Selecting it does nothing.
    return Padding(
      // In by the box's own padding less, so its text lines up with the rest of the page.
      padding: pageSides(context, extra: 0).copyWith(top: 24),
      child: ScrollIntoViewOnFocus(
        child: Tappable(
          onPress: () {},
          semanticsLabel: 'Media info',
          builder: (context, states, child) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isHighlighted(states) ? context.colors.primary : context.colors.primary.withValues(alpha: 0),
                width: PosterCard.borderWidth,
              ),
            ),
            child: child,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Text('Media info', style: context.text.titleLarge),
              if (video.isNotEmpty) line('Video', video),
              if (audio.isNotEmpty) line('Audio', capped(audio)),
              if (subtitles.isNotEmpty) line('Subtitles', capped(subtitles)),
              if (file.isNotEmpty) line('File', [file]),
            ],
          ),
        ),
      ),
    );
  }
}

/// The backdrop behind a person's page: their best-rated title that has one.
JellyfinItem? _personBackdrop(List<JellyfinItem> titles) {
  final withBackdrop = [
    for (final t in titles)
      if ((t.raw['BackdropImageTags'] as List?)?.isNotEmpty ?? false) t,
  ];
  if (withBackdrop.isEmpty) return null;
  num score(JellyfinItem t) => (t.raw['CommunityRating'] as num?) ?? 0;
  return withBackdrop.reduce((best, t) => score(t) > score(best) ? t : best);
}
