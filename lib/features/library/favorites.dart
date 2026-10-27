import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/app_icons.dart';
import '../../core/storage/app_cache.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import '../../core/focus/scroll_into_view.dart';
import '../../core/format/item_format.dart';
import '../../core/jellyfin/list_each.dart';
import '../detail/detail_page.dart';
import 'poster_card.dart';
import '../../theme/theme.dart';
import '../../core/platform/page_insets.dart';

/// Everything you've favorited, in sections: Movies, Shows, Collections, Seasons and Episodes.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<JellyfinItem> _movies = const [];
  List<JellyfinItem> _series = const [];
  List<JellyfinItem> _collections = const [];
  List<JellyfinItem> _seasons = const [];
  List<JellyfinItem> _episodes = const [];
  bool _loading = true;
  String? _error;

  static const _cacheKey = 'favorites';

  @override
  void initState() {
    super.initState();
    favoritesChanged.addListener(
      _load,
    ); // refresh when a favorite changes anywhere

    final cached = appCache.peek(_cacheKey, fromJson: itemsFromJson); // saved, from last time
    if (cached != null) {
      _show(cached);
      _loading = false;
    }
    if (!appCache.isFresh(_cacheKey)) _load();
  }

  /// Sorts [items] into the sections.
  void _show(List<JellyfinItem> items) {
    _movies = items.where((i) => i.type == JellyfinItemKind.movie).toList();
    _series = items.where((i) => i.type == JellyfinItemKind.series).toList();
    _collections = items.where((i) => i.type == 'BoxSet').toList();
    _seasons = items.where((i) => i.type == JellyfinItemKind.season).toList();
    _episodes = items.where((i) => i.type == JellyfinItemKind.episode).toList();
  }

  bool get _empty =>
      _movies.isEmpty && _series.isEmpty && _collections.isEmpty && _seasons.isEmpty && _episodes.isEmpty;

  @override
  void dispose() {
    favoritesChanged.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final client = jellyfin.client;
    if (client == null) return;
    try {
      final items = await client.items.listEach(
        filters: const ['IsFavorite'],
        types: const [
          JellyfinItemKind.movie,
          JellyfinItemKind.series,
          'BoxSet',
          JellyfinItemKind.season,
          JellyfinItemKind.episode,
        ],
        // A show's seasons and episodes together, in order.
        sortBy: const ['SeriesSortName', 'ParentIndexNumber', 'IndexNumber', 'SortName'],
        limit: 500,
        fields: const ['RecursiveItemCount'],
      );
      appCache.put(_cacheKey, items, toJson: itemsToJson);
      if (!mounted) return;
      setState(() {
        _show(items);
        _error = null;
      });
    } on JellyfinException catch (e) {
      if (mounted && _empty) {
        setState(() => _error = describeJellyfinError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: pageSides(context, extra: 12),
      child: ListenableBuilder(
        listenable: libraryViewOverride, // follow the poster/thumbnail choice
        builder: (context, _) => _buildBody(context),
      ),
    ),
  );

  Widget _buildBody(BuildContext context) {
    final colors = context.colors;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Text(_error!),
            FilledButton(
              onPressed: _load,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (_empty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(appIcons.favorite, size: 40, color: colors.onSurfaceVariant, fill: 1),
            Text(
              'No favorites yet',
              style: context.text.titleLarge,
            ),
            Text(
              'Select Favorite on any movie, show or season to add it here.',
              style: context.text.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: pageTop(context))),
        if (_movies.isNotEmpty) ...[
          const SliverSectionTitle('Movies'),
          SliverItemGrid(items: _movies),
        ],
        if (_series.isNotEmpty) ...[
          const SliverSectionTitle('Shows'),
          SliverItemGrid(items: _series),
        ],
        if (_collections.isNotEmpty) ...[
          const SliverSectionTitle('Collections'),
          SliverItemGrid(items: _collections),
        ],
        // Named underneath, as their pictures alone don't say which show they're from.
        if (_seasons.isNotEmpty) ...[
          const SliverSectionTitle('Seasons'),
          _CaptionedGrid(
            items: _seasons,
            view: LibraryView.poster, // seasons have posters
            caption: (season) => ((season.raw['SeriesName'] as String?) ?? '', season.name),
          ),
        ],
        if (_episodes.isNotEmpty) ...[
          const SliverSectionTitle('Episodes'),
          _CaptionedGrid(
            items: _episodes,
            view: LibraryView.thumbnail, // an episode's picture is a still from it
            caption: (episode) => (
              (episode.raw['SeriesName'] as String?) ?? '',
              episodeLabel(episode.raw['ParentIndexNumber'], episode.raw['IndexNumber'], episode.name),
            ),
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: pageBottom(context))),
      ],
    );
  }
}

/// A grid of cards in a fixed [view], each with two lines under it ([caption]: a show's name,
/// then the season or episode).
class _CaptionedGrid extends StatelessWidget {
  const _CaptionedGrid({required this.items, required this.view, required this.caption});

  final List<JellyfinItem> items;
  final LibraryView view;
  final (String, String) Function(JellyfinItem item) caption;

  static const _captionHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    final grid = libraryGridDelegate(view) as SliverGridDelegateWithMaxCrossAxisExtent;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        // The library grid's columns, each card as tall as its picture plus the caption.
        final width = constraints.crossAxisExtent;
        final columns = (width / (grid.maxCrossAxisExtent + grid.crossAxisSpacing)).ceil().clamp(1, 1000);
        final tile = (width - (columns - 1) * grid.crossAxisSpacing) / columns;
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: grid.maxCrossAxisExtent,
            mainAxisSpacing: grid.mainAxisSpacing,
            crossAxisSpacing: grid.crossAxisSpacing,
            mainAxisExtent: tile / grid.childAspectRatio + _captionHeight,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            final (first, second) = caption(item);
            final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
            // The whole tile, caption too, comes into view with the remote.
            return ScrollIntoViewOnFocus(
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: PosterCard(item: item, view: view, onPress: () => openItem(context, item))),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(first, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
                      Text(second, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                    ],
                  ),
                ),
              ],
              ),
            );
          },
        );
      },
    );
  }
}
