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

/// [item]'s backdrop across the top of the page, behind everything, fading into the page at the
/// bottom and darkened on the left where the details sit. It scrolls up more slowly than the
/// page ([scroll]).
class _PageBackdrop extends StatelessWidget {
  const _PageBackdrop({required this.item, required this.scroll, this.soft = false});

  final JellyfinItem item;
  final ScrollController scroll;

  /// Blurred and darkened, for a page whose artwork isn't its own (a person's, from one of
  /// their titles): a mood behind the details rather than a picture competing with them.
  final bool soft;

  static const _speed = 0.5; // how fast it moves with the page: 0 stays put, 1 scrolls with it

  /// How tall the artwork is in a page [size]: 16:9 across its width, but no more than most
  /// of its height.
  static double heightIn(Size size) => math.min(size.width * 9 / 16, size.height * 0.9);

  @override
  Widget build(BuildContext context) {
    final tag = (item.raw['BackdropImageTags'] as List?)?.firstOrNull as String?;
    final background = Theme.of(context).scaffoldBackgroundColor;
    if (tag == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = heightIn(constraints.biggest);
        final pixels = View.of(context).physicalSize.width / MediaQuery.sizeOf(context).width;
        final image = Image.network(
          jellyfin.client!.images.url(
            itemId: item.id,
            type: JellyfinImagesApi.typeBackdrop,
            tag: tag,
            fillWidth: ((constraints.maxWidth * pixels / 320).ceil() * 320).clamp(640, 3840),
            quality: 90,
          ),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
        return AnimatedBuilder(
          animation: scroll,
          builder: (context, child) {
            final offset = scroll.hasClients ? scroll.offset : 0.0;
            return Transform.translate(offset: Offset(0, -offset * _speed), child: child);
          },
          // Only moved while scrolling, not rebuilt.
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (soft)
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16, tileMode: TileMode.decal),
                      child: image,
                    )
                  else
                    image,
                  if (soft) ColoredBox(color: background.withValues(alpha: 0.55)),
                  // Darker on the left, where the logo and details are.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        // Solid at the left edge, so the artwork fades into the sidebar.
                        stops: const [0.0, 0.12, 0.4, 0.75],
                        colors: [
                          background,
                          background.withValues(alpha: 0.8),
                          background.withValues(alpha: 0.4),
                          background.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                  // Into the page at the bottom.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.35, 1.0],
                        colors: [background.withValues(alpha: 0), background],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The top of a page over its backdrop: room to see the artwork, with the title's logo (or
/// name) at the bottom left.
class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context) {
    final isPhone = ScreenType.of(context).isPhone;
    final logoTag = item.imageTags['Logo'];
    final size = MediaQuery.sizeOf(context);
    final hasBackdrop = ((item.raw['BackdropImageTags'] as List?)?.isNotEmpty ?? false);
    // Most of the artwork shows above the details.
    final height = hasBackdrop ? _PageBackdrop.heightIn(size) * (isPhone ? 0.7 : 0.55) : 0.0;
    final name = Text(
      item.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: context.text.headlineMedium?.copyWith(
        color: const Color(0xFFFFFFFF),
        shadows: const [Shadow(blurRadius: 8, color: Color(0x99000000))],
      ),
    );
    return Padding(
      padding: pageSides(context, extra: 12).copyWith(bottom: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isPhone ? 220 : 400, maxHeight: isPhone ? 64 : 120),
            child: logoTag == null
                ? name
                : Image.network(
                    jellyfin.client!.images.url(
                      itemId: item.id,
                      type: JellyfinImagesApi.typeLogo,
                      tag: logoTag,
                      fillWidth: 800,
                    ),
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomLeft,
                    errorBuilder: (_, _, _) => name,
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── A person ────────────────────────────────────────────────────────────────

/// The backdrop behind a person's page: from their best-rated title that has one.
JellyfinItem? _personBackdrop(List<JellyfinItem> titles) {
  final withBackdrop = [
    for (final t in titles)
      if ((t.raw['BackdropImageTags'] as List?)?.isNotEmpty ?? false) t,
  ];
  if (withBackdrop.isEmpty) return null;
  num score(JellyfinItem t) => (t.raw['CommunityRating'] as num?) ?? 0;
  return withBackdrop.reduce((best, t) => score(t) > score(best) ? t : best);
}

/// The top of a person's page: their photo, then their name, when and where they were born
/// (and died), how many of their titles you have, and their biography. Side by side on wider
/// screens; on phones the photo sits above.
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
    final size = MediaQuery.sizeOf(context);
    final muted = context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant);
    final bio = (person.raw['Overview'] as String?)?.trim();
    final counts = [
      if (movies > 0) '$movies ${movies == 1 ? 'movie' : 'movies'}',
      if (shows > 0) '$shows ${shows == 1 ? 'show' : 'shows'}',
    ];
    final photoHeight = isPhone ? 180.0 : 300.0;

    final tag = person.imageTags['Primary'];
    final pixels = View.of(context).physicalSize.width / size.width;
    final photo = SizedBox(
      height: photoHeight,
      width: photoHeight * 2 / 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: tag == null
              ? ColoredBox(
                  color: context.colors.surfaceContainerHighest,
                  child: Center(
                    child: Text(
                      initialsOf(person.name),
                      style: context.text.headlineMedium?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ),
                )
              : Image.network(
                  jellyfin.client!.images.url(
                    itemId: person.id,
                    type: JellyfinImagesApi.typePrimary,
                    tag: tag,
                    fillWidth: ((photoHeight * 2 / 3 * pixels / 80).ceil() * 80).clamp(160, 800),
                    quality: 90,
                  ),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
        ),
      ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Text(
          person.name,
          style: (isPhone ? context.text.headlineMedium : context.text.displaySmall)?.copyWith(
            color: const Color(0xFFFFFFFF),
            shadows: const [Shadow(blurRadius: 8, color: Color(0x99000000))],
          ),
        ),
        for (final line in _lifeLines) Text(line, style: muted),
        if (counts.isNotEmpty) Text('${counts.join(' · ')} in your library', style: muted),
        if (bio != null && bio.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ExpandableText(bio, limit: isPhone ? 200 : 500, style: context.text.bodyLarge),
          ),
      ],
    );

    // Some of the backdrop shows above it, as on a title's page.
    final room = _PageBackdrop.heightIn(size) * (isPhone ? 0.25 : 0.3);
    return Padding(
      padding: pageSides(context, extra: 12).copyWith(top: room, bottom: 8),
      child: isPhone
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [photo, details])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 32,
              children: [
                photo,
                Expanded(
                  // Not too wide to read.
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: details),
                  ),
                ),
              ],
            ),
    );
  }
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

/// The collections [item] is in, each with the rest of what's in it. A movie's franchise comes
/// from the collection id the server matched it to (TMDb's); collections made by hand (without
/// such an id) are looked through, a few at most.
Future<List<_CollectionRow>> _collectionsWith(JellyfinItem item) async {
  final franchise = (item.raw['ProviderIds'] as Map?)?['TmdbCollection'] as String?;
  final all = await _collections();
  final candidates = [
    for (final c in all)
      if (franchise != null && (c.raw['ProviderIds'] as Map?)?['Tmdb'] == franchise) c,
  ];
  final handmade = [for (final c in all) if ((c.raw['ProviderIds'] as Map?)?['Tmdb'] == null) c];
  if (handmade.length <= 10) candidates.addAll(handmade);

  final rows = await Future.wait([
    for (final c in candidates)
      _collectionItems(c.id).then<_CollectionRow?>(
        (items) => items.any((i) => i.id == item.id)
            ? (collection: c, items: [for (final i in items) if (i.id != item.id) i])
            : null,
        onError: (Object _) => null,
      ),
  ]);
  return [for (final r in rows) if (r != null && r.items.isNotEmpty) r];
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
  const _ItemRow({required this.title, required this.items, this.onTitle});

  final String title;
  final List<JellyfinItem> items;
  final VoidCallback? onTitle;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  final _scroll = ScrollController();

  static const _gap = 4.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The row's padding at its ends: the first card in line with the page, and the same room
  /// after the last one.
  EdgeInsets _sides(BuildContext context) {
    final sides = pageSides(context, extra: 12);
    return sides.copyWith(right: sides.left);
  }

  /// With a remote, scrolls the row so card [index] sits in the last slot that fits whole (or
  /// as far as the row goes), as Home's rows do.
  void _keepInSlot(BuildContext context, int index, double width) {
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final step = width + _gap;
    final slot = math.max(0, ((position.viewportDimension - _sides(context).left - width) / step).floor());
    final offset = ((index - slot) * step).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((offset - position.pixels).abs() < 0.5) return;
    position.animateTo(offset, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = ScreenType.of(context).isPhone;
    final view = libraryViewFor(context);
    final items = widget.items;
    final height = isPhone ? (view == LibraryView.poster ? 180.0 : 135.0) : PosterCard.height;
    final width = view == LibraryView.poster ? height * 2 / 3 : height * 16 / 9;
    final heading = Text(widget.title, style: context.text.titleLarge);
    Widget row = FocusRow(
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        // Inside the list, so the first card lines up with the page but cards still scroll
        // right to the screen's edge.
        padding: _sides(context),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: _gap),
        itemBuilder: (context, i) => SizedBox(
          width: width,
          child: Focus(
            // Doesn't take focus itself: notices the card getting it, and scrolls the row.
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (focused) {
              if (focused) _keepInSlot(context, i, width);
            },
            child: PosterCard(
              item: items[i],
              view: view,
              // The first card grows away from the sidebar, the last away from the screen's edge.
              anchor: i == 0
                  ? Alignment.centerLeft
                  : i == items.length - 1
                  ? Alignment.centerRight
                  : Alignment.center,
              onPress: () => openItem(context, items[i]),
            ),
          ),
        ),
      ),
    );
    // Scrolled along with a remote, the card before the first one in view would peek out of
    // the margin as a sliver. Phones keep rows running to the edge, for swiping.
    if (!isPhone) row = ClipRect(clipper: _LeftMarginClipper(_sides(context).left / 2), child: row);

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Padding(
            padding: pageSides(context, extra: 12),
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
          ScrollIntoViewOnFocus(child: SizedBox(height: height, child: row)),
        ],
      ),
    );
  }
}

/// Clips off the left [left] of a row, where a card scrolled past would peek out, and nothing
/// above, below or to the right (so a focused card can still grow there).
class _LeftMarginClipper extends CustomClipper<Rect> {
  const _LeftMarginClipper(this.left);

  final double left;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(left, -size.height, size.width * 2, size.height * 2);

  @override
  bool shouldReclip(_LeftMarginClipper old) => old.left != left;
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

    return Padding(
      padding: pageSides(context, extra: 12).copyWith(top: 24),
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
    );
  }
}
