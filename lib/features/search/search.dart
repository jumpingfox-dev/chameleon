import 'dart:async';

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/storage/app_cache.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import '../../core/jellyfin/list_each.dart';
import '../detail/detail_page.dart';
import '../detail/person_tile.dart';
import '../library/poster_card.dart';
import '../../theme/app_icons.dart';
import '../../theme/theme.dart';
import '../../core/platform/page_insets.dart';
import '../../core/jellyfin/together.dart';
import '../../widgets/focus_slot_row.dart';
import '../../widgets/remote_text_field.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.query});

  /// A search to run straight away, from /search?q=... (a link elsewhere).
  final String? query;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _lastSearched = '';
  String? _routeQuery;
  int _requestId = 0;

  List<JellyfinItem> _results = const [];
  List<JellyfinItem> _people = const [];
  List<JellyfinItem> _suggestions = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query.addListener(_onTextChanged);
    _takeRouteQuery();
    _loadSuggestions();
  }

  /// A search submitted from elsewhere arrives as /search?q=..., passed in as [SearchScreen.query].
  void _takeRouteQuery() {
    final q = widget.query;
    if (q != null && q != _routeQuery) {
      _routeQuery = q;
      _query.text = q; // triggers _onTextChanged, which runs the search
    }
  }

  @override
  void didUpdateWidget(covariant SearchScreen old) {
    super.didUpdateWidget(old);
    _takeRouteQuery(); // a new search while this page is already open
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_query.text == _lastSearched) {
      return; // cursor moves also notify; ignore them
    }
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
          () => _search(_query.text),
    );
  }

  Future<void> _search(String text) async {
    final query = text.trim();
    _lastSearched = text;
    final client = jellyfin.client;
    if (query.isEmpty || client == null) {
      setState(() {
        _results = const [];
        _people = const [];
        _error = null;
      });
      return;
    }

    final id = ++_requestId;
    setState(() => _loading = true);
    try {
      final (page, people) = await together2(
      client.items.listEach(
        searchTerm: query,
        types: const [
          JellyfinItemKind.movie,
          JellyfinItemKind.series,
        ],
        sortBy: const ['SortName'],
        limit: 60,
      ),
      client.persons.list(
        searchTerm: query,
        personTypes: const ['Actor'],
        limit: 20,
      ),
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = page;
        _people = people.items;
        _error = null;
      });
    } on JellyfinException catch (e) {
      if (mounted && id == _requestId) {
        setState(() => _error = describeJellyfinError(e));
      }
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  /// Shown while the search box is empty: suggestions from your history, or random titles as a fallback.
  Future<void> _loadSuggestions() async {
    const cacheKey = 'search:suggestions';
    if (appCache.peek<List<JellyfinItem>>(cacheKey) case final cached?) {
      setState(() => _suggestions = cached);
      if (appCache.isFresh(cacheKey)) return;
    }
    final client = jellyfin.client;
    if (client == null) return;
    try {
      var items = (await client.suggestions.list(
        enableTotalRecordCount: false,
        mediaType: const ['Video'],
        type: const [JellyfinItemKind.movie, JellyfinItemKind.series],
        limit: 24,
      )).items;

      // Little or no watch history: show a random mix instead.
      if (items.isEmpty) {
        items = await client.items.listEach(
          types: const [
            JellyfinItemKind.movie,
            JellyfinItemKind.series,
          ],
          sortBy: const ['Random'],
          limit: 24,
        );
      }
      appCache.put(cacheKey, items);
      if (mounted) setState(() => _suggestions = items);
    } on JellyfinException {
      // Suggestions are a nice extra; if they fail, the plain empty message shows instead.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // No side padding around the page: the results put it inside their scrolling, so a card at
    // the edge has room to grow when it's focused.
    // The box at the top of the page, under its title, scrolling away with the results as other
    // pages' tops do.
    body: CustomScrollView(
      slivers: [
        // Arriving from the menu, top bar or bottom bar: ready to type (on a TV, the remote is on
        // the box, and Select opens the keyboard).
        SliverPadding(
          padding: pageSides(context, extra: 12).copyWith(top: pageTop(context), bottom: 16),
          sliver: SliverToBoxAdapter(
          child: RemoteTextField(
            autofocus: _routeQuery == null,
            builder: (context, focusNode, highlighted) => TextField(
              controller: _query,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (text) {
                _debounce?.cancel();
                _search(text);
              },
              decoration: InputDecoration(
                hintText: 'Search movies, shows, and actors',
                border: searchFieldBorder,
                enabledBorder: highlighted ? remoteFieldBorder(context, searchFieldBorder) : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                // A clear button while there's something to clear, in from the box's rounded end.
                suffixIcon: ListenableBuilder(
                  listenable: _query,
                  builder: (context, _) => _query.text.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: IconButton(
                            onPressed: _query.clear,
                            visualDensity: VisualDensity.standard,
                            iconSize: 20,
                            icon: Icon(appIcons.close),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        ),
        ..._resultSlivers(context),
      ],
    ),
  );

  /// What's under the box: suggestions, the results, or a message in the room that's left.
  List<Widget> _resultSlivers(BuildContext context) {
    final results = _buildResults(context);
    return switch (results) {
      CustomScrollView(:final slivers) => slivers,
      final message => [SliverFillRemaining(hasScrollBody: false, child: message)],
    };
  }

  Widget _buildResults(BuildContext context) {
    final muted = context.text.bodyLarge?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return Center(child: Text(_error!));
    if (_query.text.trim().isEmpty) {
      if (_suggestions.isEmpty) {
        return Center(child: Text('Search your library', style: muted));
      }
      final view = libraryViewFor(context);
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: pageSides(context, extra: 12),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('Suggested For You', style: context.text.titleLarge),
                  ),
                ),
                SliverGrid.builder(
                  gridDelegate: libraryGridDelegate(view),
                  itemCount: _suggestions.length,
                  itemBuilder: (context, i) => PosterCard(
                    item: _suggestions[i],
                    view: view,
                    onPress: () => openItem(context, _suggestions[i]),
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: pageBottom(context))),
        ],
      );
    }

    if (_results.isEmpty && _people.isEmpty) {
      return Center(
        child: Text('No results for "${_query.text.trim()}"', style: muted),
      );
    }

    final view = libraryViewFor(context);
    final sides = pageSides(context, extra: 12);
    return CustomScrollView(
      slivers: [
        if (_people.isNotEmpty) ...[
          SliverPadding(padding: sides, sliver: SliverToBoxAdapter(child: _sectionTitle(context, 'People'))),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 130,
              child: FocusSlotRow(
                padding: sides, // runs to the screen's edges, starting in line with the page
                itemCount: _people.length,
                itemWidth: PersonTile.width,
                // The photo, centred at the top of the tile.
                frameFor: (_) => const SlotFrame(
                  width: PersonTile.photo,
                  height: PersonTile.photo,
                  left: (PersonTile.width - PersonTile.photo) / 2,
                  circle: true,
                ),
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => PersonTile(
                  person: _people[i],
                  onPress: () => openPerson(context, _people[i].id),
                ),
              ),
            ),
          ),
        ],
        if (_results.isNotEmpty)
          SliverPadding(
            padding: sides,
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(child: _sectionTitle(context, 'Movies & Shows')),
                SliverGrid.builder(
                  gridDelegate: libraryGridDelegate(view),
                  itemCount: _results.length,
                  itemBuilder: (context, i) => PosterCard(
                    item: _results[i],
                    view: view,
                    onPress: () => openItem(context, _results[i]),
                  ),
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: pageBottom(context))),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Text(text, style: context.text.titleLarge),
  );
}