import 'package:material_ui/material_ui.dart';

import '../core/downloads/downloads.dart';
import '../core/jellyfin/jellyfin_controller.dart';
import '../core/storage/storage.dart';
import '../theme/app_icons.dart';
import '../widgets/nav_button.dart';
import '../core/storage/app_defaults.dart';

/// The buttons along the bottom on phones (and tablets held upright): up to [max] of them, in
/// order. Home, Search, Downloads and your Movies library unless you've chosen others in
/// Settings › Appearance. Saved per person.
///
/// Each button is an id: 'home', 'search', 'downloads', 'favorites', 'genres', 'settings', or
/// 'library:' and a library's id.
final bottomBarTabs = BottomBarTabs._();

/// What a bottom bar button shows and opens.
typedef BottomBarTab = ({String id, String label, IconData icon, String path});

class BottomBarTabs extends ChangeNotifier {
  BottomBarTabs._();

  static const max = 4;
  static const _key = 'bottom_bar_tabs';

  /// Every button you can choose, in the order they're offered.
  List<String> get options => [
    'home',
    'search',
    if (DownloadsController.supported) 'downloads',
    'favorites',
    if (jellyfin.genres.isNotEmpty) 'genres',
    for (final library in jellyfin.libraries) 'library:${library.id}',
    'settings',
  ];

  /// From assets/defaults.json's appearance.bottomBar, where a library is named by its kind
  /// ("movies", "tvshows", "music", ... : the first library of that kind) and Downloads becomes
  /// Favorites where there are no downloads. Home, Search, Downloads and Movies without it.
  List<String> get _defaults {
    final names = appDefaults.strings('bottomBar', sectionName: 'appearance') ?? const ['home', 'search', 'downloads', 'movies'];
    String? resolve(String name) {
      if (name == 'downloads' && !DownloadsController.supported) return 'favorites';
      if (describe(name) != null) return name;
      final library = jellyfin.libraries.where((l) => l.collectionType == name).firstOrNull;
      return library == null ? null : 'library:${library.id}';
    }

    final ids = <String>[];
    for (final name in names) {
      final id = resolve(name);
      if (id != null && !ids.contains(id)) ids.add(id);
    }
    return ids.take(max).toList();
  }

  /// The buttons, as chosen (or the defaults). Ones that no longer exist (a library that's
  /// gone) are left out.
  List<String> get ids {
    final saved = storage.getStringList(_key);
    final available = options.toSet();
    final ids = [for (final id in saved ?? _defaults) if (available.contains(id)) id];
    return ids.isEmpty ? _defaults : ids.take(max).toList();
  }

  List<BottomBarTab> get tabs => [for (final id in ids) ?describe(id)];

  /// Puts [id] in button [slot] (0 to 3), or empties it with null. A button already shown
  /// elsewhere swaps places with what was there. At least one button always stays.
  Future<void> setSlot(int slot, String? id) async {
    final slots = [...ids, for (var i = ids.length; i < max; i++) null];
    final from = id == null ? -1 : slots.indexOf(id);
    if (from != -1 && from != slot) slots[from] = slots[slot];
    slots[slot] = id;
    final chosen = slots.whereType<String>().toList();
    if (chosen.isEmpty) return;
    await storage.setStringList(_key, chosen);
    notifyListeners();
  }

  /// The defaults changed (a server's own, see AppDefaults.server).
  void defaultsChanged() => notifyListeners();

  /// Back to Home, Search, Downloads and Movies.
  Future<void> reset() async {
    await storage.remove(_key);
    notifyListeners();
  }

  /// What button [id] shows and where it goes, or null if it doesn't exist (any more).
  static BottomBarTab? describe(String id) {
    if (id.startsWith('library:')) {
      final libraryId = id.substring('library:'.length);
      final library = jellyfin.libraries.where((l) => l.id == libraryId).firstOrNull;
      if (library == null) return null;
      return (id: id, label: library.name, icon: libraryIcon(library.collectionType), path: '/home/library/$libraryId');
    }
    return switch (id) {
      'home' => (id: id, label: 'Home', icon: appIcons.home, path: '/home'),
      'search' => (id: id, label: 'Search', icon: appIcons.search, path: '/search'),
      'downloads' => (id: id, label: 'Downloads', icon: appIcons.download, path: '/downloads'),
      'favorites' => (id: id, label: 'Favorites', icon: appIcons.favorite, path: '/home/favorites'),
      'genres' => (id: id, label: 'Genres', icon: appIcons.genres, path: '/home/genres'),
      'settings' => (id: id, label: 'Settings', icon: appIcons.settings, path: '/settings'),
      _ => null,
    };
  }
}
