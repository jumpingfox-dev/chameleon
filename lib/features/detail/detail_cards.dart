part of 'detail_page.dart';

// ─── Collection pieces ───────────────────────────────────────────────────────

/// Count, year span and age rating, then the description, genres and movies.
class _CollectionInfoCard extends StatelessWidget {
  const _CollectionInfoCard({required this.collection, required this.items});

  final JellyfinItem collection;
  final List<JellyfinItem> items;

  /// US film and TV ratings, mildest to strictest, used to find the collection's range.
  static const _ratingOrder = [
    'G',
    'TV-Y',
    'TV-Y7',
    'TV-G',
    'PG',
    'TV-PG',
    'PG-13',
    'TV-14',
    'R',
    'TV-MA',
    'NC-17',
  ];

  /// "2009–2022", or a single year if every movie shares it.
  String? get _years {
    final years = [
      for (final item in items)
        if (item.raw['ProductionYear'] case final int year) year,
    ]..sort();
    if (years.isEmpty) return null;
    return years.first == years.last
        ? '${years.first}'
        : '${years.first}–${years.last}';
  }

  /// "PG-13" if every movie shares it, otherwise the mildest–strictest range, e.g. "PG–R".
  String? get _rating {
    final ratings = {
      for (final item in items)
        if (item.raw['OfficialRating'] case final String r when r.isNotEmpty) r,
    };
    if (ratings.isEmpty) return null;

    final known = ratings.where(_ratingOrder.contains).toList()
      ..sort(
            (a, b) => _ratingOrder.indexOf(a).compareTo(_ratingOrder.indexOf(b)),
      );
    if (known.isEmpty) return ratings.first; // a rating system outside the US list: show it as-is
    return known.first == known.last
        ? known.first
        : '${known.first} – ${known.last}';
  }

  /// The collection's own genres, or else every genre its movies use, most common first.
  List<String> get _genres {
    final own =
        (collection.raw['Genres'] as List?)?.cast<String>() ?? const <String>[];
    if (own.isNotEmpty) return own;

    final counts = <String, int>{};
    for (final item in items) {
      for (final genre
      in (item.raw['Genres'] as List?)?.cast<String>() ??
          const <String>[]) {
        counts[genre] = (counts[genre] ?? 0) + 1;
      }
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isPhone = ScreenType.of(context).isPhone;
    final muted = context.text.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final description = (collection.raw['Overview'] as String?)?.trim();
    final years = _years;
    final rating = _rating;
    final genres = _genres;

    return _DetailCard(
      edgeToEdge: true,
      child: _CardColumn(
        children: [
          // ── Count, years, age rating ──
          _FactsRow(
            children: [
              Text(
                '${items.length} ${items.length == 1 ? 'title' : 'titles'}',
                style: muted,
              ),
              if (years != null) Text(years, style: muted),
              if (rating != null) _RatingBadge(rating),
            ],
          ),

          // ── Play, Shuffle, Favorite ──
          ScrollIntoViewOnFocus(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StartsHere(
                  child: FilledButton(
                    style: actionButtonStyle,
                    onPressed: items.isEmpty
                        ? null
                        : () => playQueue(GoRouter.of(context), collectionQueue(items)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [Icon(appIcons.play, size: 18, fill: 1), const Text('Play')],
                    ),
                  ),
                ),
                FilledButton.tonal(
                  style: actionButtonStyle,
                  onPressed: items.length < 2
                      ? null
                      : () => playQueue(GoRouter.of(context), collectionQueue(items, shuffle: true)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [Icon(appIcons.shuffle, size: 18, fill: 1), const Text('Shuffle')],
                  ),
                ),
                _FavoriteButton(item: collection),
              ],
            ),
          ),

          // ── Description ──
          if (description != null && description.isNotEmpty)
            ExpandableText(
              description,
              limit: isPhone ? 150 : 400,
              style: context.text.bodyLarge,
            ),

          // ── Genres ──
          if (genres.isNotEmpty) _GenreButtons(genres),

          // ── Movies ──
          if (items.isNotEmpty) ...[
            const _CardDivider(),
            Text('Movies', style: context.text.titleLarge),
            _InlineItemGrid(items),
          ],
        ],
      ),
    );
  }
}

// ─── Movie pieces ────────────────────────────────────────────────────────────

/// Year, runtime, age rating and score, then Play, the description, genres and the cast.
class _MovieInfoCard extends StatelessWidget {
  const _MovieInfoCard({required this.movie});

  final JellyfinItem movie;


  /// Actors only, in billing order, as Jellyfin lists them.
  /// Started and not finished.
  bool get _partway {
    final userData = movie.raw['UserData'] as Map?;
    final ticks = userData?['PlaybackPositionTicks'];
    return ticks is int && ticks > 0 && userData?['Played'] != true;
  }

  List<Map<String, dynamic>> get _cast => _peopleOf(movie);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isPhone = ScreenType.of(context).isPhone;
    final muted = context.text.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );

    final year = movie.raw['ProductionYear'];
    final runtime = formatRuntime(movie.raw['RunTimeTicks']);
    final rating = movie.raw['OfficialRating'] as String?;
    final score = movie.raw['CommunityRating'] as num?;
    final description = (movie.raw['Overview'] as String?)?.trim();
    final genres =
        (movie.raw['Genres'] as List?)?.cast<String>() ?? const <String>[];
    final cast = _cast;

    return _DetailCard(
      edgeToEdge: true,
      child: _CardColumn(
        children: [
          // ── Year, runtime, age rating, score ──
          _FactsRow(
            children: [
              if (year != null) Text('$year', style: muted),
              if (runtime != null) Text(runtime, style: muted),
              if (rating != null && rating.isNotEmpty) _RatingBadge(rating),
              if (score != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Icon(appIcons.star, size: 14, color: colors.primary, fill: 1),
                    Text(score.toStringAsFixed(1), style: muted),
                  ],
                ),
            ],
          ),

          // ── Play, Favorite ──
          ScrollIntoViewOnFocus(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StartsHere(
                  child: FilledButton(
                    style: actionButtonStyle,
                    onPressed: () => context.push('/play/${movie.id}'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        Icon(appIcons.play, size: 18, fill: 1),
                        // Partway through: it picks up where you left off.
                        Text(_partway ? 'Continue' : 'Play'),
                      ],
                    ),
                  ),
                ),
                _FavoriteButton(item: movie),
                _TrailerButton(item: movie),
                _WatchedButton(item: movie),
                DownloadButton(item: movie, style: actionButtonStyle),
              ],
            ),
          ),

          // ── Description ──
          if (description != null && description.isNotEmpty)
            ExpandableText(
              description,
              limit: isPhone ? 150 : 400,
              style: context.text.bodyLarge,
            ),

          // ── Genres ──
          if (genres.isNotEmpty) _GenreButtons(genres),

          // ── Cast ──
          ..._castSection(context, cast),
        ],
      ),
    );
  }
}

// ─── Series pieces ───────────────────────────────────────────────────────────

/// Years, season count, age rating and score, then Play, Favorite, Trailer and Mark as
/// watched, the description and genres. (The seasons are a row of their own, below.)
class _SeriesInfoCard extends StatelessWidget {
  const _SeriesInfoCard({required this.series, required this.seasons});

  final JellyfinItem series;
  final List<JellyfinItem> seasons;

  /// "2008–2013", "2019–present" for a show still airing, or a single year.
  String? get _years {
    final start = series.raw['ProductionYear'];
    if (start is! int) return null;
    if (series.raw['Status'] == 'Continuing') return '$start–present';
    final end = DateTime.tryParse(
      (series.raw['EndDate'] as String?) ?? '',
    )?.year;
    return end == null || end == start ? '$start' : '$start–$end';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isPhone = ScreenType.of(context).isPhone;
    final muted = context.text.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );

    final years = _years;
    final seasonCount = seasons.length;
    final rating = series.raw['OfficialRating'] as String?;
    final score = series.raw['CommunityRating'] as num?;
    final description = (series.raw['Overview'] as String?)?.trim();
    final genres =
        (series.raw['Genres'] as List?)?.cast<String>() ?? const <String>[];

    return _DetailCard(
      edgeToEdge: true,
      child: _CardColumn(
        children: [
          // ── Years, seasons, age rating, score ──
          _FactsRow(
            children: [
              if (years != null) Text(years, style: muted),
              if (seasonCount > 0)
                Text(
                  '$seasonCount ${seasonCount == 1 ? 'season' : 'seasons'}',
                  style: muted,
                ),
              if (rating != null && rating.isNotEmpty) _RatingBadge(rating),
              if (score != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Icon(appIcons.star, size: 14, color: colors.primary, fill: 1),
                    Text(score.toStringAsFixed(1), style: muted),
                  ],
                ),
            ],
          ),

          // ── Play, Favorite, Trailer, Mark as watched ──
          ScrollIntoViewOnFocus(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StartsHere(child: _SeriesPlayButton(series: series, seasons: seasons)),
                _FavoriteButton(item: series),
                _TrailerButton(item: series),
                _WatchedButton(item: series),
              ],
            ),
          ),

          // ── Description ──
          if (description != null && description.isNotEmpty)
            ExpandableText(
              description,
              limit: isPhone ? 150 : 400,
              style: context.text.bodyLarge,
            ),

          // ── Genres ──
          if (genres.isNotEmpty) _GenreButtons(genres),
        ],
      ),
    );
  }
}

// ─── Season pieces ───────────────────────────────────────────────────────────

/// A season's Play, Favorite and Mark as watched, its description, the
/// cast, then its episodes.
class _SeasonInfoCard extends StatefulWidget {
  const _SeasonInfoCard({required this.season, required this.series, required this.episodes});

  final JellyfinItem season;
  final JellyfinItem series;
  final List<JellyfinItem> episodes;

  @override
  State<_SeasonInfoCard> createState() => _SeasonInfoCardState();
}

class _SeasonInfoCardState extends State<_SeasonInfoCard> {
  // Kept here, so marking the season shows on every episode straight away.
  late var _episodes = widget.episodes;
  bool _saving = false;

  @override
  void didUpdateWidget(_SeasonInfoCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.episodes, widget.episodes)) _episodes = widget.episodes; // refreshed
  }

  bool get _allWatched => _episodes.isNotEmpty && _episodes.every(isWatched);

  /// [episode] with its watched state set to [played] (and its place forgotten either way).
  static JellyfinItem _withPlayed(JellyfinItem episode, bool played) => JellyfinItem.fromJson({
    ...episode.raw,
    'UserData': {
      ...?(episode.raw['UserData'] as Map?)?.cast<String, dynamic>(),
      'Played': played,
      'PlaybackPositionTicks': 0,
      'PlayedPercentage': played ? 100 : 0,
    },
  });

  /// Marks every episode in the season watched (or, all watched already, unwatched): shown at
  /// once, put back if the server refuses.
  Future<void> _toggleWatched() async {
    if (_saving) return;
    final before = _episodes;
    final played = !_allWatched;
    setState(() {
      _saving = true;
      _episodes = [for (final e in before) _withPlayed(e, played)];
    });
    try {
      final userData = jellyfin.client!.userData;
      // Marking the season marks all of its episodes.
      await (played ? userData.markPlayed(widget.season.id) : userData.markUnplayed(widget.season.id));
      // Saved pages for the season and the show now show the old state.
      appCache.invalidateWhere(
        (key) => key == 'episodes:${widget.season.id}' || key.endsWith(':${widget.season.id}') || key.endsWith(':${widget.series.id}'),
      );
    } on JellyfinException {
      if (mounted) setState(() => _episodes = before);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Where Play picks up: an episode partway through, else the first not watched, else the first.
  JellyfinItem? get _next =>
      _episodes.where((e) => watchProgress(e) != null && !isWatched(e)).firstOrNull ??
      _episodes.where((e) => !isWatched(e)).firstOrNull ??
      _episodes.firstOrNull;

  @override
  Widget build(BuildContext context) {
    final season = widget.season;
    final isPhone = ScreenType.of(context).isPhone;
    final muted = context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant);
    final description = ((season.raw['Overview'] as String?)?.trim().isNotEmpty ?? false)
        ? (season.raw['Overview'] as String).trim()
        : (widget.series.raw['Overview'] as String?)?.trim();
    // The season's own cast and crew, or the show's.
    final cast = _peopleOf(season).isNotEmpty ? _peopleOf(season) : _peopleOf(widget.series);
    final next = _next;
    final allWatched = _allWatched;
    final started = !allWatched && _episodes.any((e) => isWatched(e) || watchProgress(e) != null);

    return _DetailCard(
      edgeToEdge: true,
      child: _CardColumn(
        children: [
          // ── Play, Favorite, Mark as watched (the trailer is on the show's page) ──
          ScrollIntoViewOnFocus(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StartsHere(
                  child: FilledButton(
                    style: actionButtonStyle,
                    onPressed: next == null ? null : () => context.push('/play/${next.id}'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [Icon(appIcons.play, size: 18, fill: 1), Text(started ? 'Continue' : 'Play')],
                    ),
                  ),
                ),
                _FavoriteButton(item: season),
                _watchedButton(context, watched: allWatched, onPressed: _episodes.isEmpty ? null : _toggleWatched),
              ],
            ),
          ),

          // ── Description ──
          if (description != null && description.isNotEmpty)
            ExpandableText(
              description,
              limit: isPhone ? 150 : 400,
              style: context.text.bodyLarge,
            ),

          // ── Cast ──
          ..._castSection(context, cast),

          // ── Episodes ──
          const _CardDivider(),
          Text('Episodes', style: context.text.titleLarge),
          if (_episodes.isEmpty)
            Text('No episodes in this season yet.', style: muted)
          else
            Column(
              spacing: 8,
              children: [for (final episode in _episodes) _EpisodeTile(episode: episode)],
            ),
        ],
      ),
    );
  }
}

/// Everyone Jellyfin lists for a title: the cast in billing order, then the crew (directors,
/// writers, producers, ...), as it lists them. Anyone listed twice (an actor who also directed)
/// appears once per job.
List<Map<String, dynamic>> _peopleOf(JellyfinItem item) {
  final people = [for (final p in (item.raw['People'] as List?) ?? const []) if (p is Map<String, dynamic>) p];
  return [...people.where(_isActing), ...people.where((p) => !_isActing(p))];
}

/// In the cast (an actor or guest star), rather than the crew.
bool _isActing(Map<String, dynamic> person) => person['Type'] == 'Actor' || person['Type'] == 'GuestStar';

/// What someone did on a title, for under their name: an actor's character, or a crew member's
/// job ("Director", "Writer", ...).
String? _jobOf(Map<String, dynamic> person) {
  final role = (person['Role'] as String?)?.trim();
  if (role != null && role.isNotEmpty) return role;
  return switch (person['Type']) {
    'Actor' || null => null,
    'GuestStar' => 'Guest star',
    final String type => type.replaceAllMapped(RegExp(r'(?<=[a-z])([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}'),
    _ => null,
  };
}

/// The cast and crew, under a divider: a heading, and a row of people that scrolls sideways to
/// the card's edges. Nothing when there's no one.
List<Widget> _castSection(BuildContext context, List<Map<String, dynamic>> cast) => [
  if (cast.isNotEmpty) ...[
    const _CardDivider(),
    Text('Cast & Crew', style: context.text.titleLarge),
    _EdgeToEdge(
      // Runs to the card's edges, so the cast scrolls all the way across.
      builder: (padding) => ScrollIntoViewOnFocus(
        child: SizedBox(
          height: _CastTile.heightOf(context),
          child: FocusRow(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: padding,
              itemCount: cast.length,
              // Between the last of the cast and the first of the crew, a line down the middle.
              separatorBuilder: (context, i) => _isActing(cast[i]) && !_isActing(cast[i + 1])
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 40),
                      child: VerticalDivider(width: 1, thickness: 1, color: context.colors.outlineVariant),
                    )
                  : const SizedBox(width: 8),
              itemBuilder: (context, i) => _CastTile(person: cast[i]),
            ),
          ),
        ),
      ),
    ),
  ],
];

/// One episode: thumbnail on the left; number, title, runtime, air date and description beside it.
/// Lifts on hover or remote focus, and plays when selected.
class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode});

  final JellyfinItem episode;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// "Jan 20, 2008" from the episode's premiere date.
  String? get _airDate {
    final date = DateTime.tryParse(
      (episode.raw['PremiereDate'] as String?) ?? '',
    );
    return date == null
        ? null
        : '${_months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isPhone = ScreenType.of(context).isPhone;
    final number = episode.raw['IndexNumber'];
    final tag = episode.imageTags['Primary']; // an episode's Primary image is its 16:9 thumbnail
    final overview = (episode.raw['Overview'] as String?)?.trim();
    final details = [formatRuntime(episode.raw['RunTimeTicks']), _airDate].whereType<String>().join(' · ');
    final thumbWidth = isPhone ? 140.0 : 240.0;

    return ScrollIntoViewOnFocus(
      alignment: 0.4, // episodes are tall rows: settle a little lower so the previous one stays visible
      child: HoverLift(
        builder: (context, active) => Tappable(
          onPress: () => context.push('/play/${episode.id}'),
          onLongPress: () => showItemMenu(context, episode),
          child: AnimatedScale(
            scale: active ? 1.0 : 0.98, // a gentle lift: rows are wide, so a small scale is plenty
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                // ── Thumbnail ──
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: active ? cardHoverShadow : const [], // lifted off the page
                  ),
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(
                      color: active ? colors.primary : const Color(0x00000000),
                      width: 2.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: thumbWidth,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            tag == null
                                ? ColoredBox(
                              color: colors.surfaceContainerHighest,
                              child: Icon(
                                appIcons.play,
                                color: colors.onSurfaceVariant,
                                fill: 1,
                              ),
                            )
                                : Image.network(
                              jellyfin.client!.images.url(
                                itemId: episode.id,
                                type: JellyfinImagesApi.typePrimary,
                                tag: tag,
                                fillWidth: (thumbWidth * 2).round(),
                                quality: 90,
                              ),
                              fit: BoxFit.cover,
                            ),
                            if (watchProgress(episode) case final progress?)
                              Positioned(
                                left: 6,
                                right: 6,
                                bottom: 6,
                                child: WatchProgressBar(progress),
                              ),
                            if (isWatched(episode))
                              const Positioned(
                                top: 6,
                                right: 6,
                                child: WatchedBadge(size: 20),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Text ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(
                        number != null
                            ? '$number. ${episode.name}'
                            : episode.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details,
                          style: context.text.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      if (overview != null && overview.isNotEmpty)
                        Text(
                          overview,
                          maxLines: isPhone ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium,
                        ),
                    ],
                  ),
                ),
                DownloadButton(item: episode, compact: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An actor in the cast row: photo, name and character. Lifts on hover or remote focus.
class _CastTile extends StatelessWidget {
  const _CastTile({required this.person});

  final Map<String, dynamic> person;

  /// Its height: the photo, then up to two lines of name and one of character or job, measured
  /// in the font and text size in use (so nothing's cut off with larger text).
  static double heightOf(BuildContext context) {
    final small = context.text.bodySmall;
    return 96 + 4 + 2 * lineHeightOf(context, small) + 4 + lineHeightOf(context, small) + 2;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final id = person['Id'] as String;
    final name = (person['Name'] as String?) ?? '';
    final role = _jobOf(person); // their character, or their job on it
    final tag = person['PrimaryImageTag'] as String?;
    final initials = initialsOf(name);

    return HoverLift(
      builder: (context, active) => Tappable(
        onPress: () => openPerson(context, id),
        child: SizedBox(
          width: 110,
          child: Column(
            spacing: 4,
            children: [
              AnimatedScale(
                scale: active ? 1.0 : 0.94,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  // Hovered or focused: a ring drawn over the photo's edge (it takes up no space).
                  foregroundDecoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active ? colors.primary : const Color(0x00000000),
                      width: 2.5,
                    ),
                  ),
                  child: ClipOval(
                    child: SizedBox.square(
                      dimension: 96,
                      child: tag == null
                          ? ColoredBox(
                        color: colors.surfaceContainerHighest,
                        child: Center(
                          child: Text(
                            initials,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ),
                      )
                          : Image.network(
                        jellyfin.client!.images.url(
                          itemId: id,
                          type: JellyfinImagesApi.typePrimary,
                          tag: tag,
                          fillWidth: 192,
                          quality: 90,
                        ),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall,
              ),
              if (role != null && role.isNotEmpty)
                Text(
                  role,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Action buttons ──────────────────────────────────────────────────────────

/// Toggles an item as a favorite in Jellyfin. Updates instantly, and reverts if the server fails.
class _FavoriteButton extends StatefulWidget {
  const _FavoriteButton({required this.item});

  final JellyfinItem item;

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  // Jellyfin includes the user's own data (favorite, watched, ...) with each item.
  late bool _favorite =
      ((widget.item.raw['UserData'] as Map?)?['IsFavorite'] as bool?) ?? false;
  bool _saving = false;

  Future<void> _toggle() async {
    if (_saving) return;
    final next = !_favorite;
    setState(() {
      _favorite = next; // show the change right away
      _saving = true;
    });
    try {
      await jellyfin.client!.userData.setFavorite(widget.item.id, next);
      favoritesChanged.value++; // tell the Favorites page to refresh
      // Cached pages for this item, and the Favorites list, now show the wrong heart.
      appCache.invalidateWhere(
            (key) => key.endsWith(':${widget.item.id}') || key == 'favorites',
      );
    } on JellyfinException {
      if (mounted) setState(() => _favorite = !next); // the server refused: undo
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      _favorite ? appIcons.favorite : appIcons.favoriteOutline,
      size: 18,
      color: _favorite ? context.colors.primary : null,
      fill: _favorite ? 1 : 0,
    );
    final label = Text(_favorite ? 'Favorited' : 'Favorite');
    // Filled, like the banner's More info: an outline alone gets lost on a busy backdrop.
    return FilledButton.tonalIcon(style: actionButtonStyle, onPressed: _toggle, icon: icon, label: label);
  }
}

/// Marks a movie watched (or a show: all of its episodes), or, watched already, unwatched.
/// Updates instantly, and reverts if the server fails.
class _WatchedButton extends StatefulWidget {
  const _WatchedButton({required this.item});

  final JellyfinItem item;

  @override
  State<_WatchedButton> createState() => _WatchedButtonState();
}

class _WatchedButtonState extends State<_WatchedButton> {
  late bool _watched = isWatched(widget.item);
  bool _saving = false;

  Future<void> _toggle() async {
    if (_saving) return;
    final next = !_watched;
    setState(() {
      _watched = next; // show the change right away
      _saving = true;
    });
    try {
      final userData = jellyfin.client!.userData;
      await (next ? userData.markPlayed(widget.item.id) : userData.markUnplayed(widget.item.id));
      // Saved pages for it (and a show's seasons' episodes) now show the old state.
      appCache.invalidateWhere((key) => key.endsWith(':${widget.item.id}') || key.startsWith('episodes:'));
    } on JellyfinException {
      if (mounted) setState(() => _watched = !next); // the server refused: undo
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _watchedButton(context, watched: _watched, onPressed: _toggle);
}

/// Mark as watched (or unwatched, when [watched]): filled, like Favorite, as an outline alone
/// gets lost on a busy backdrop.
Widget _watchedButton(BuildContext context, {required bool watched, required VoidCallback? onPressed}) =>
    FilledButton.tonalIcon(
      style: actionButtonStyle,
      onPressed: onPressed,
      icon: Icon(appIcons.check, size: 18, color: watched ? context.colors.primary : null, fill: 1),
      label: Text(watched ? 'Mark as unwatched' : 'Mark as watched'),
    );

/// Plays the title's trailer in the app: one on the server in the app's player, a YouTube one
/// full screen in YouTube's player (in the browser on desktops). Only there once a trailer
/// has been found.
class _TrailerButton extends StatelessWidget {
  const _TrailerButton({required this.item});

  final JellyfinItem item;

  Future<void> _play(BuildContext context, Trailer trailer) async {
    switch (trailer) {
      case ServerTrailer(:final itemId):
        await context.push('/play/$itemId');
      // In the app where there's a web view to play it in; elsewhere (Linux) in the browser.
      case YouTubeTrailer(:final videoId) when Platform.isAndroid || Platform.isIOS:
        await YouTubeTrailerScreen.open(context, videoId);
      case YouTubeTrailer(:final watchUrl):
        if (!await MediaSupport.openUrl(watchUrl) && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't open YouTube on this device.")),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Trailer?>(
    future: trailerFor(item),
    builder: (context, snap) {
      final trailer = snap.data;
      if (trailer == null) return const SizedBox.shrink();
      // Filled, like the banner's More info: an outline alone gets lost on a busy backdrop.
      return FilledButton.tonalIcon(
        style: actionButtonStyle,
        onPressed: () => _play(context, trailer),
        icon: Icon(appIcons.trailer, size: 18, fill: 1),
        label: const Text('Trailer'),
      );
    },
  );
}

/// The episode a show's Play button plays (see continueEpisodeOf).
typedef _NextEpisode = ContinueEpisode;

/// Each show page's next episode, looked up once and shared by its Play button. Kept with the
/// page's own copy of the show, so opening the page again asks again.
final _nextEpisodes = Expando<Future<_NextEpisode>>('next episode');

Future<_NextEpisode> _nextEpisodeOf(JellyfinItem series, List<JellyfinItem> seasons) =>
    _nextEpisodes[series] ??= continueEpisodeOf(series.id).catchError(
      (Object _) => (episode: null, started: false), // the button stays disabled
      test: (e) => e is JellyfinException,
    );

class _SeriesPlayButton extends StatefulWidget {
  const _SeriesPlayButton({required this.series, required this.seasons});

  final JellyfinItem series;
  final List<JellyfinItem> seasons;

  @override
  State<_SeriesPlayButton> createState() => _SeriesPlayButtonState();
}

class _SeriesPlayButtonState extends State<_SeriesPlayButton> {
  _NextEpisode? _next;

  @override
  void initState() {
    super.initState();
    _nextEpisodeOf(widget.series, widget.seasons).then((next) {
      if (mounted) setState(() => _next = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final next = _next?.episode;
    final label = _next?.started ?? false ? 'Continue' : 'Play';

    return FilledButton(
      style: actionButtonStyle,
      // Usable straight away (so the page can open with focus on it): pressed before the next
      // episode is found, it waits for it.
      onPressed: _next != null && next == null
          ? null // nothing to play
          : () async {
              final router = GoRouter.of(context);
              final episode = next ?? (await _nextEpisodeOf(widget.series, widget.seasons)).episode;
              if (episode != null) router.push('/play/${episode.id}');
            },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [Icon(appIcons.play, size: 18, fill: 1), Text(label)],
      ),
    );
  }
}
