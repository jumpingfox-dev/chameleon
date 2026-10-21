import 'dart:math' as math;

import 'package:dart_jellyfin/dart_jellyfin.dart';

/// Lists items of several types (movies and shows, say) as one request per type, at the same
/// time, merged in the order asked for.
///
/// Jellyfin answers a query for one type quickly, but a query for movies *and* shows together
/// can take seconds (measured on a real server: 0.1 s each alone, 2.7 s together; and
/// another second on top when it also counts the total, which this never asks for).
extension ListEach on JellyfinItemsApi {
  Future<List<JellyfinItem>> listEach({
    required List<String> types,
    String? parentId,
    List<String> genres = const [],
    List<String> filters = const [],
    List<String> personIds = const [],
    List<String> excludeItemIds = const [],
    String? searchTerm,
    List<String> sortBy = const [],
    bool descending = false,
    int? limit,
    List<String> fields = const [],
    bool recursive = true,
  }) async {
    // Fields the merge needs to put the lists in order, beyond what's always sent.
    final needed = {...fields, for (final s in sortBy) ?_sortFields[s]}.toList();
    final pages = await Future.wait([
      for (final type in types)
        list(
          enableTotalRecordCount: false,
          includeItemTypes: [type],
          parentId: parentId,
          genres: genres,
          filters: filters,
          personIds: personIds,
          excludeItemIds: excludeItemIds,
          searchTerm: searchTerm,
          sortBy: sortBy,
          descending: descending,
          limit: limit,
          fields: needed,
          recursive: recursive,
        ),
    ]);
    final all = [for (final page in pages) ...page.items];
    if (types.length > 1) {
      if (sortBy.contains('Random')) {
        all.shuffle(math.Random());
      } else if (sortBy.isNotEmpty) {
        all.sort((a, b) {
          for (final key in sortBy) {
            final order = _compare(_sortValue(a, key), _sortValue(b, key));
            if (order != 0) return descending ? -order : order;
          }
          return 0;
        });
      }
    }
    return limit == null ? all : all.take(limit).toList();
  }
}

/// The field to ask for so an item carries a sort key; null for keys always sent.
const _sortFields = {'SortName': 'SortName', 'DateCreated': 'DateCreated', 'DatePlayed': null};

Object? _sortValue(JellyfinItem item, String key) => switch (key) {
  'SortName' => ((item.raw['SortName'] as String?) ?? item.name).toLowerCase(),
  'DatePlayed' => (item.raw['UserData'] as Map?)?['LastPlayedDate'],
  _ => item.raw[key],
};

int _compare(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1; // missing values last
  if (b == null) return -1;
  if (a is num && b is num) return a.compareTo(b);
  return a.toString().compareTo(b.toString()); // names, and ISO dates sort as text
}
