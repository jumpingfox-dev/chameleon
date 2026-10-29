import 'package:material_ui/material_ui.dart';

import '../../core/focus/focus_rows.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/theme.dart';
import '../../widgets/tappable.dart';
import '../settings/choice_picker.dart';
import 'poster_card.dart';

/// What a library's titles are ordered by.
enum LibrarySort {
  name('Name', 'SortName'),
  dateAdded('Date added', 'DateCreated'),
  releaseDate('Release date', 'PremiereDate'),
  rating('Rating', 'CommunityRating'),
  runtime('Runtime', 'Runtime');

  const LibrarySort(this.label, this.key);
  final String label;
  final String key; // Jellyfin's SortBy

  /// Which way round it goes, in words: A–Z, Newest first, ...
  String direction({required bool descending}) => switch (this) {
    name => descending ? 'Z–A' : 'A–Z',
    dateAdded || releaseDate => descending ? 'Newest first' : 'Oldest first',
    rating => descending ? 'Highest first' : 'Lowest first',
    runtime => descending ? 'Longest first' : 'Shortest first',
  };
}

/// Which titles show by whether you've watched them.
enum WatchedFilter {
  all('Watched or not', null),
  unwatched('Unwatched', 'IsUnplayed'),
  watched('Watched', 'IsPlayed'),
  inProgress('In progress', 'IsResumable');

  const WatchedFilter(this.label, this.filter);
  final String label;
  final String? filter; // Jellyfin's Filters
}

/// A library page's sort and filters. The default is everything, A–Z.
@immutable
class LibraryFilters {
  const LibraryFilters({
    this.sort = LibrarySort.name,
    this.descending = false,
    this.watched = WatchedFilter.all,
    this.favorites = false,
    this.genre,
    this.decade,
  });

  final LibrarySort sort;
  final bool descending;
  final WatchedFilter watched;
  final bool favorites;
  final String? genre;
  final int? decade; // 1990 for the 1990s

  /// Nothing left out: every title, though maybe in another order.
  bool get showsAll => watched == WatchedFilter.all && !favorites && genre == null && decade == null;

  bool get isDefault => showsAll && sort == LibrarySort.name && !descending;

  /// Titles grouped under # and A–Z (sorted by name).
  bool get byLetter => sort == LibrarySort.name;

  /// Tells these filters apart, for keeping each one's titles separately.
  String get signature => '${sort.name}|$descending|${watched.name}|$favorites|${genre ?? ''}|${decade ?? ''}';

  /// What to ask Jellyfin for.
  List<String> get sortBy => [sort.key, if (sort != LibrarySort.name) 'SortName'];
  List<String> get filters => [?watched.filter, if (favorites) 'IsFavorite'];
  List<int> get years => decade == null ? const [] : [for (var y = decade!; y < decade! + 10; y++) y];

  /// The same as raw query parameters, for requests made by hand.
  Map<String, String> get query => {
    if (filters.isNotEmpty) 'Filters': filters.join(','),
    'Genres': ?genre,
    if (years.isNotEmpty) 'Years': years.join(','),
  };

  LibraryFilters copyWith({
    LibrarySort? sort,
    bool? descending,
    WatchedFilter? watched,
    bool? favorites,
    String? Function()? genre,
    int? Function()? decade,
  }) => LibraryFilters(
    sort: sort ?? this.sort,
    descending: descending ?? this.descending,
    watched: watched ?? this.watched,
    favorites: favorites ?? this.favorites,
    genre: genre == null ? this.genre : genre(),
    decade: decade == null ? this.decade : decade(),
  );
}

/// The buttons at the top of a library page: Random, and Filters, which opens the sort and
/// filters together ([showLibraryFilters]). They scroll with the titles, so they're gone as soon
/// as you scroll down.
class LibraryFilterBar extends StatelessWidget {
  const LibraryFilterBar({
    super.key,
    required this.filters,
    required this.onChanged,
    required this.view,
    required this.onToggleView,
    this.onRandom,
    this.showGenre = true,
    this.showInProgress = true,
    this.showRuntime = true,
  });

  final LibraryFilters filters;
  final ValueChanged<LibraryFilters> onChanged;

  /// Posters or thumbnails, and switching between them.
  final LibraryView view;
  final VoidCallback onToggleView;

  /// Opens a title picked at random; null for no Random button (a collections library).
  final VoidCallback? onRandom;

  final bool showGenre; // not on a genre's own page
  final bool showInProgress; // movies only: a show isn't "in progress" itself
  final bool showRuntime; // not for shows


  @override
  Widget build(BuildContext context) {
    final f = filters;
    // How many things are set, sort included, for the button's label.
    final count = [
      !(f.sort == LibrarySort.name && !f.descending),
      f.watched != WatchedFilter.all,
      f.genre != null,
      f.decade != null,
      f.favorites,
    ].where((set) => set).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FocusRow(
        startsPage: false, // a page opens on its first title, not on these
        // On a narrow screen, what doesn't fit goes onto a line underneath.
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
              if (onRandom != null) _FilterButton(icon: appIcons.random, label: 'Random', onPressed: onRandom!),
              _FilterButton(
                icon: appIcons.filter,
                label: count == 0 ? 'Filters' : 'Filters · $count',
                active: count > 0,
                onPressed: () => showLibraryFilters(
                  context,
                  filters: f,
                  onChanged: onChanged,
                  showGenre: showGenre,
                  showInProgress: showInProgress,
                  showRuntime: showRuntime,
                ),
              ),
              // Shows the view you'll switch *to*: a wide shape for thumbnails, a tall one for posters.
              _FilterButton(
                iconWidget: view == LibraryView.poster
                    ? const AspectIcon(width: 18, height: 10)
                    : const AspectIcon(width: 11, height: 16),
                label: view == LibraryView.poster ? 'Thumbnails' : 'Posters',
                onPressed: onToggleView,
              ),
          ],
        ),
      ),
    );
  }
}

/// The sort and filters for a library, in a panel: each line shows what it's set to and opens a
/// list to pick from (it works the same with a remote). Changes apply straight away.
Future<void> showLibraryFilters(
  BuildContext context, {
  required LibraryFilters filters,
  required ValueChanged<LibraryFilters> onChanged,
  bool showGenre = true,
  bool showInProgress = true,
  bool showRuntime = true,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: context.colors.scrim,
  transitionDuration: const Duration(milliseconds: 150),
  transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
  pageBuilder: (context, _, _) => Center(
    child: _FiltersPanel(
      filters: filters,
      onChanged: onChanged,
      showGenre: showGenre,
      showInProgress: showInProgress,
      showRuntime: showRuntime,
    ),
  ),
);

class _FiltersPanel extends StatefulWidget {
  const _FiltersPanel({
    required this.filters,
    required this.onChanged,
    required this.showGenre,
    required this.showInProgress,
    required this.showRuntime,
  });

  final LibraryFilters filters;
  final ValueChanged<LibraryFilters> onChanged;
  final bool showGenre;
  final bool showInProgress;
  final bool showRuntime;

  @override
  State<_FiltersPanel> createState() => _FiltersPanelState();
}

class _FiltersPanelState extends State<_FiltersPanel> {
  late var _f = widget.filters;

  static const _firstDecade = 1920;

  void _set(LibraryFilters f) {
    setState(() => _f = f);
    widget.onChanged(f);
  }

  Future<T?> _pick<T>(String title, List<T> options, T selected, String Function(T) label) => showChoicePicker<T>(
    context: context,
    title: title,
    selected: selected,
    searchable: options.length > 12,
    search: (query) async => [
      for (final o in options)
        if (label(o).toLowerCase().contains(query.toLowerCase())) o,
    ],
    itemBuilder: (context, o) => Text(label(o)),
  );

  @override
  Widget build(BuildContext context) {
    final f = _f;
    final sorts = [
      for (final sort in LibrarySort.values)
        if (sort != LibrarySort.runtime || widget.showRuntime)
          for (final descending in [false, true]) (sort, descending),
    ];
    String sortLabel((LibrarySort, bool) s) => '${s.$1.label} (${s.$1.direction(descending: s.$2)})';
    final watchedOptions = [
      for (final w in WatchedFilter.values)
        if (w != WatchedFilter.inProgress || widget.showInProgress) w,
    ];
    // (0 and '' stand for "any": the picker gives null back only when it's closed.)
    final thisDecade = DateTime.now().year ~/ 10 * 10;
    final decades = [0, for (var d = thisDecade; d >= _firstDecade; d -= 10) d];
    final genres = ['', ...jellyfin.genres];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          color: context.colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: FocusScope(
              autofocus: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                    child: Text('Filters', style: context.text.titleLarge),
                  ),
                  _FilterLine(
                    autofocus: true,
                    icon: appIcons.sort,
                    title: 'Sort by',
                    value: sortLabel((f.sort, f.descending)),
                    onPressed: () async {
                      final picked = await _pick('Sort by', sorts, (f.sort, f.descending), sortLabel);
                      if (picked != null) _set(f.copyWith(sort: picked.$1, descending: picked.$2));
                    },
                  ),
                  _FilterLine(
                    icon: appIcons.check,
                    title: 'Show',
                    value: f.watched.label,
                    onPressed: () async {
                      final picked = await _pick('Show', watchedOptions, f.watched, (w) => w.label);
                      if (picked != null) _set(f.copyWith(watched: picked));
                    },
                  ),
                  if (widget.showGenre && jellyfin.genres.isNotEmpty)
                    _FilterLine(
                      icon: appIcons.genres,
                      title: 'Genre',
                      value: f.genre ?? 'All genres',
                      onPressed: () async {
                        final picked = await _pick('Genre', genres, f.genre ?? '', (g) => g.isEmpty ? 'All genres' : g);
                        if (picked != null) _set(f.copyWith(genre: () => picked.isEmpty ? null : picked));
                      },
                    ),
                  _FilterLine(
                    icon: appIcons.recentlyAdded,
                    title: 'Released in',
                    value: f.decade == null ? 'Any year' : '${f.decade}s',
                    onPressed: () async {
                      final picked = await _pick('Released in', decades, f.decade ?? 0, (d) => d == 0 ? 'Any year' : '${d}s');
                      if (picked != null) _set(f.copyWith(decade: () => picked == 0 ? null : picked));
                    },
                  ),
                  _FilterLine(
                    icon: f.favorites ? appIcons.favorite : appIcons.favoriteOutline,
                    title: 'Favorites only',
                    value: f.favorites ? 'On' : 'Off',
                    onPressed: () => _set(f.copyWith(favorites: !f.favorites)),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      spacing: 8,
                      children: [
                        if (!f.isDefault) TextButton(onPressed: () => _set(const LibraryFilters()), child: const Text('Clear all')),
                        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One line in the filters panel: what it is, and what it's set to.
class _FilterLine extends StatelessWidget {
  const _FilterLine({
    required this.icon,
    required this.title,
    required this.value,
    required this.onPressed,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tappable(
        autofocus: autofocus,
        onPress: onPressed,
        builder: (context, states, child) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isHighlighted(states) ? colors.onSurface.withValues(alpha: 0.10) : colors.onSurface.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        ),
        child: Row(
          spacing: 16,
          children: [
            Icon(icon, size: 22, color: colors.primary, fill: 1),
            Text(title, style: context.text.titleMedium),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: context.text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the filter bar's buttons: like a genre button, in the accent color while it's set.
class _FilterButton extends StatelessWidget {
  const _FilterButton({this.icon, this.iconWidget, required this.label, required this.onPressed, this.active = false});

  final IconData? icon;
  final Widget? iconWidget; // in place of [icon]
  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = active ? colors.primary : null;
    return OutlinedButton.icon(
      style: genreButtonStyle(colors, compact: true).copyWith(
        foregroundColor: active ? WidgetStatePropertyAll(colors.primary) : null,
      ),
      onPressed: onPressed,
      icon: iconWidget ?? Icon(icon, size: 18, color: color, fill: 1),
      label: Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(label)),
    );
  }
}
