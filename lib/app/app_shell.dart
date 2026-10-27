import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/detail/detail_page.dart' show detailTitleOf;
import '../features/detail/detail_screens.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/library/genres.dart';
import '../features/home/home.dart';
import '../features/library/favorites.dart';
import '../features/library/library.dart';
import '../features/player/cast_widgets.dart';
import '../features/search/search.dart';
import '../features/settings/settings.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import '../core/cast/cast_controller.dart';
import '../core/downloads/downloads.dart';
import '../core/focus/focus_rows.dart';
import '../features/home/home_layout.dart';
import '../core/jellyfin/jellyfin_controller.dart';
import '../core/platform/page_insets.dart';
import '../core/platform/screen_type.dart';
import '../core/storage/storage.dart';
import '../widgets/app_logo.dart';
import '../widgets/nav_button.dart';
import 'bottom_bar_tabs.dart';
import '../widgets/tappable.dart';
import '../features/auth/profile_actions.dart';
import '../features/auth/profile_picker.dart';
import '../core/storage/app_defaults.dart';

part 'app_menu.dart';

/// The app's top-level pages, one navigator each (so each keeps its place when you switch).
/// Order = router branch order.
typedef AppDestination = ({
  String path,
  Widget Function(GoRouterState state) screen, // state: e.g. the ?tab= on Settings
  List<RouteBase> routes, // sub-pages that belong to this page
});

final destinations = <AppDestination>[
  (
    path: '/home',
    screen: (_) => const HomeScreen(),
    routes: [
      GoRoute(path: 'favorites', builder: (context, state) => const FavoritesScreen()),
      GoRoute(path: 'genres', builder: (context, state) => const GenresScreen()),
      GoRoute(
        path: 'library/:id',
        builder: (context, state) => LibraryScreen(libraryId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'genre/:name',
        builder: (context, state) => LibraryScreen(genre: state.pathParameters['name']!),
      ),
      GoRoute(
        path: 'collection/:id',
        builder: (context, state) => CollectionScreen(collectionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'movie/:id',
        builder: (context, state) => MovieScreen(movieId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'series/:id',
        builder: (context, state) => SeriesScreen(seriesId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: 'person/:id',
        builder: (context, state) => PersonScreen(personId: state.pathParameters['id']!),
      ),
    ],
  ),
  (
    path: '/search',
    screen: (state) => SearchScreen(query: state.uri.queryParameters['q']),
    routes: [
      GoRoute(
        path: 'person/:id',
        builder: (context, state) => PersonScreen(personId: state.pathParameters['id']!),
      ),
    ],
  ),
  (path: '/downloads', screen: (_) => const DownloadsScreen(), routes: const []),
  (
    path: '/settings',
    screen: (state) => SettingsScreen(
      initialTab: state.uri.queryParameters['tab'],
      group: state.uri.queryParameters['group'],
    ),
    routes: const [],
  ),
  (
    path: '/profile',
    screen: (state) => SettingsScreen(initialTab: state.uri.queryParameters['tab'] ?? 'Account'),
    routes: const [],
  ),
];

/// Each top-level page's navigator, in [destinations] order, so the shell can take one back to
/// its start (pressing Home while on a title's page opened from Home, say).
final branchNavigatorKeys = [for (final _ in destinations) GlobalKey<NavigatorState>()];

/// Bumped when a page is pushed onto or popped off one of the pages' navigators (a title's page,
/// say), which the router's location doesn't show, so the top bar can update its Back button.
final pageStackChanged = ValueNotifier(0);

/// Tells [pageStackChanged] about one page navigator. One per navigator: an observer can only
/// watch one.
class PageStackObserver extends NavigatorObserver {
  /// The page on top of this navigator.
  Route<dynamic>? top;

  void _changed() => WidgetsBinding.instance.addPostFrameCallback((_) => pageStackChanged.value++);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    top = route;
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route == top) top = previousRoute;
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route == top) top = previousRoute;
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == top) top = newRoute;
    _changed();
  }
}

/// One [PageStackObserver] per top-level page, in [destinations] order.
final pageStackObservers = [for (final _ in destinations) PageStackObserver()];

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell, required this.location, this.tab, this.group});

  final StatefulNavigationShell navigationShell;
  final String location; // current path, e.g. /home/library/movies
  final String? tab; // the ?tab= on Settings, e.g. Playback
  final String? group; // the ?group= on Settings: one group's page, e.g. Fonts

  @override
  State<AppShell> createState() => _AppShellState();
}

/// The menu's width.
const _menuWidth = 280.0;

/// Saved: the menu stays open beside the page on wide screens.
const _kMenuPinned = 'menu_pinned';

class _AppShellState extends State<AppShell> {
  // Each page lives in its own navigator, and arrow keys can't cross from a page into the top
  // bar or the menu (or back) on their own. These scopes let the shell move focus between them.
  final _menuScope = FocusScopeNode(debugLabel: 'Menu');
  final _pageScope = FocusScopeNode(debugLabel: 'Page');
  final _barScope = FocusScopeNode(debugLabel: 'Top bar');

  /// The menu slid out over the page (rather than pinned beside it).
  final _menuOpen = ValueNotifier(false);

  /// The top bar shows. It slides away as a page scrolls down, and comes back only once the
  /// page is back at the top (or another page opens).
  final _barShown = ValueNotifier(true);

  /// The page is scrolled to its top: only then does the top bar show its logo or title.
  final _atTop = ValueNotifier(true);

  /// The room the top bar takes when it shows (see TopBarSpace), and the status bar's share
  /// of it, set as the page builds.
  double _barRoom = 0;
  double _barRoomStatus = 0;

  /// Tells pages how far to keep their fixed parts down now (see topBarRoom).
  void _onBarShown() => topBarRoom.value = _barShown.value ? _barRoom : _barRoomStatus;

  /// A page scrolled: down hides the top bar, reaching the top shows it again. Only the page's
  /// own up-and-down scrolling, not rows scrolling sideways.
  bool _onPageScroll(ScrollUpdateNotification n) {
    // The page's own scrolling only: not a list inside it (depth > 0), and not something that
    // can't scroll at all (a short side column, which always reads as "at the top").
    if (n.depth != 0 || n.metrics.axis != Axis.vertical || n.metrics.maxScrollExtent <= 0) return false;
    _atTop.value = n.metrics.pixels <= n.metrics.minScrollExtent + 8;
    if (n.metrics.pixels <= n.metrics.minScrollExtent + 8) {
      _barShown.value = true;
    } else if ((n.scrollDelta ?? 0) > 4 && !_barScope.hasFocus) {
      _barShown.value = false;
      _hiddenBy = n.context;
    }
    return false;
  }

  /// What scrolled the top bar away, so a change to it (below) can bring the bar back.
  BuildContext? _hiddenBy;

  /// The page that hid the bar changed size: with the bar gone it's taller, and a page only
  /// just long enough to scroll may now fit, or sit at its top, with no scrolling left to bring
  /// the bar back. Then it comes back now.
  bool _onPageMetrics(ScrollMetricsNotification n) {
    if (_barShown.value || n.context != _hiddenBy || n.metrics.axis != Axis.vertical) return false;
    if (n.metrics.maxScrollExtent <= 0 || n.metrics.pixels <= n.metrics.minScrollExtent + 8) {
      _barShown.value = true;
    }
    return false;
  }

  /// A page opened or closed (a title's page, say, which doesn't change the address).
  void _onPageStack() => _syncBarToPage();

  /// Each page's top bar as it was left (shown, and at its top), so going back to a page finds
  /// it as it was: hidden, if you'd scrolled down.
  final _barStates = Expando<(bool, bool)>('top bar');

  /// The page [_barShown] and [_atTop] are about.
  Route<dynamic>? _barPage;

  /// The page on top changed: keeps the last one's top bar, and gives the new one its own. A page
  /// opened for the first time starts at its top, with the bar showing.
  void _syncBarToPage() {
    if (!mounted) return;
    final page = pageStackObservers[widget.navigationShell.currentIndex].top;
    if (page == _barPage) return;
    if (_barPage case final last?) _barStates[last] = (_barShown.value, _atTop.value);
    _barPage = page;
    final (shown, atTop) = (page == null ? null : _barStates[page]) ?? (true, true);
    _barShown.value = shown;
    _atTop.value = atTop;
  }

  late bool _pinned = storage.getBool(_kMenuPinned) ?? appDefaults.settings('appearance')['menuPinned'] == true;

  /// Whether My Media's libraries show in the menu. Stays as you left it.
  bool _myMediaOpen = true;

  /// A focus node for each menu entry, by name ('Home', `Library/<id>`, ...), so the remote can
  /// land on the entry for where you are.
  final _menuNodes = <String, FocusNode>{};
  FocusNode _menuNode(String id) => _menuNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'Menu: $id'));

  /// The menu entry for where you are.
  String get _here {
    final loc = widget.location;
    if (loc.startsWith('/search')) return 'Search';
    if (loc == '/downloads') return 'Downloads';
    if (loc == '/home/favorites') return 'Favorites';
    if (loc.startsWith('/home/genre')) return 'Genres';
    if (loc.startsWith('/home/library/')) return 'Library/${loc.split('/').last}';
    if (loc == '/settings' || loc == '/profile') return widget.group ?? 'Settings';
    return 'Home'; // home, and the pages opened from it (a movie, a show, ...)
  }

  /// The bottom bar, measured after each frame so pages know where it starts.
  final _footerKey = GlobalKey();
  double _footerHeight = 0;

  void _measureFooter() {
    final box = _footerKey.currentContext?.findRenderObject();
    final height = box is RenderBox && box.hasSize ? box.size.height : 0.0;
    if (mounted && height != _footerHeight) setState(() => _footerHeight = height);
  }

  @override
  void dispose() {
    _menuScope.dispose();
    _pageScope.dispose();
    _barScope.dispose();
    _menuOpen.dispose();
    pageStackChanged.removeListener(_onPageStack);
    _barShown.dispose();
    for (final node in _menuNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// The menu can stay open beside the page on wide screens: TVs, computers, and tablets held
  /// sideways. Phones slide it out over the page.
  bool _canPin(BuildContext context) {
    final type = ScreenType.of(context);
    if (type.isPhone) return false;
    final size = MediaQuery.sizeOf(context);
    return size.width >= size.height;
  }

  /// A remote or keyboard is in use: focus follows the menu as it opens and closes.
  bool get _remote => FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  void _openMenu() {
    if (_pinned && _canPin(context)) {
      _focusMenuEntry();
      return;
    }
    _menuOpen.value = true;
    if (_remote) WidgetsBinding.instance.addPostFrameCallback((_) => _focusMenuEntry());
  }

  void _closeMenu() {
    final hadFocus = _menuScope.hasFocus;
    _menuOpen.value = false;
    if (hadFocus) _focusFirstOrRemembered(_pageScope);
  }

  void _togglePinned() {
    final hadFocus = _menuScope.hasFocus;
    setState(() => _pinned = !_pinned);
    _menuOpen.value = false;
    storage.setBool(_kMenuPinned, _pinned);
    // The menu moves (beside the page, or back over it), which loses focus: back onto the pin
    // button if pinning, or into the page if closing it.
    if (hadFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pinned) {
          // Focus has to change for the button (rebuilt beside the page) to show it's on it.
          final pin = _menuNode('Pin')..unfocus();
          WidgetsBinding.instance.addPostFrameCallback((_) => pin.requestFocus());
        } else {
          _focusFirstOrRemembered(_pageScope);
        }
      });
    }
  }

  /// Into the menu, on the entry for where you are.
  void _focusMenuEntry() {
    final node = _menuNodes[_here];
    if (node != null && node.context != null && node.canRequestFocus) {
      node.requestFocus();
    } else {
      firstFocusable(_menuScope)?.requestFocus();
    }
  }

  /// Opens a page from the menu or the bottom bar: closes the menu (unless it's pinned) and,
  /// with a remote, moves onto the new page's first item once it's built.
  @override
  void initState() {
    super.initState();
    // The remote moving up into the top bar brings it back.
    _barScope.addListener(() {
      if (_barScope.hasFocus) _barShown.value = true;
    });
    pageStackChanged.addListener(_onPageStack);
    _barShown.addListener(_onBarShown);
  }

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    // Another page (or tab): its own top bar, once the navigator has it on top.
    if (old.location != widget.location) WidgetsBinding.instance.addPostFrameCallback((_) => _syncBarToPage());
  }

  void _goTo(String path) {
    // Going to a page you're already in (Home, from a title opened on Home) takes it back to its
    // start, rather than doing nothing.
    // Only the pages pushed by hand (a title's page) are closed here; the router's own pages
    // (Genres, a library) are its to change, which context.go does.
    final branch = destinations.indexWhere((d) => path == d.path || path.startsWith('${d.path}/'));
    if (branch != -1 && branch == widget.navigationShell.currentIndex) {
      branchNavigatorKeys[branch].currentState?.popUntil((route) => route.settings is Page);
    }
    context.go(path);
    final hadFocus = _menuScope.hasFocus || _barScope.hasFocus;
    _menuOpen.value = false;
    if (hadFocus || ScreenType.of(context).isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusNewPage());
    }
  }

  /// Back (the remote's, Android's, or Esc): closes the menu if it's open; otherwise, with
  /// nothing left to go back to on a page other than Home, goes Home, so leaving the app takes
  /// one more press from there. False leaves it to the router (going back, or leaving the app).
  bool _back() {
    if (_menuOpen.value) {
      _closeMenu();
      return true;
    }
    if (!GoRouter.of(context).canPop() && widget.location != '/home') {
      _goTo('/home');
      return true;
    }
    return false;
  }

  bool _isArrow(KeyEvent event, LogicalKeyboardKey key) =>
      (event is KeyDownEvent || event is KeyRepeatEvent) && event.logicalKey == key;

  /// ← or ↑ on a page: move within the page if anything's there, otherwise into the menu (←)
  /// or the top bar (↑).
  KeyEventResult _onPageKey(FocusNode node, KeyEvent event) {
    final left = _isArrow(event, LogicalKeyboardKey.arrowLeft);
    final up = _isArrow(event, LogicalKeyboardKey.arrowUp);
    if (!left && !up) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus;
    final focusedContext = focused?.context;
    if (focused == null || focusedContext == null) return KeyEventResult.ignored;

    // Dialogs and pickers keep their keys to themselves.
    if (ModalRoute.of(focusedContext) is PopupRoute) return KeyEventResult.ignored;

    // In a text field, ← moves the cursor until it reaches the start.
    final editable = focusedContext.findAncestorStateOfType<EditableTextState>();
    if (left && editable != null) {
      final selection = editable.textEditingValue.selection;
      if (!selection.isCollapsed || selection.baseOffset > 0) return KeyEventResult.ignored;
    }

    if (left) {
      if (!moveFocus(TraversalDirection.left)) _openMenu();
    } else if (!moveFocus(TraversalDirection.up)) {
      // Nothing above on the page. If the page isn't at its top, what's above just isn't built
      // yet (pressing ↑ faster than the page scrolls): scroll up a little and try again, rather
      // than jumping to the top bar in the middle of the page.
      if (!_scrollPageUp(focusedContext)) _focusFirstOrRemembered(_barScope);
    }
    return KeyEventResult.handled;
  }

  /// Scrolls the page [context] is on up by a third of the screen, then tries ↑ again. False if
  /// the page is already at its top.
  bool _scrollPageUp(BuildContext context) {
    ScrollableState? page;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final scrollable = element.state as ScrollableState;
        if (scrollable.position.axis == Axis.vertical) page = scrollable;
      }
      return true; // the outermost vertical one: the page's own
    });
    final position = page?.position;
    if (position == null || position.pixels <= position.minScrollExtent + 1) return false;
    position.jumpTo(math.max(position.minScrollExtent, position.pixels - position.viewportDimension / 3));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageScope.hasFocus) return;
      if (!moveFocus(TraversalDirection.up) && position.pixels <= position.minScrollExtent + 1) {
        _focusFirstOrRemembered(_barScope); // at the top after all, and nothing above
      }
    });
    return true;
  }

  /// ↓ from the top bar: back into the page, where you were.
  KeyEventResult _onBarKey(FocusNode node, KeyEvent event) {
    if (!_isArrow(event, LogicalKeyboardKey.arrowDown)) return KeyEventResult.ignored;
    _focusFirstOrRemembered(_pageScope);
    return KeyEventResult.handled;
  }

  /// → from the menu, or Esc: back into the page.
  KeyEventResult _onMenuKey(FocusNode node, KeyEvent event) {
    final escape = event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape;
    if (!escape && !_isArrow(event, LogicalKeyboardKey.arrowRight)) return KeyEventResult.ignored;
    if (_menuOpen.value) {
      _closeMenu();
    } else {
      _focusFirstOrRemembered(_pageScope);
    }
    return KeyEventResult.handled;
  }

  /// After opening a page from the menu: focus that page's first item, not wherever you were on
  /// the last page. Pages that load their content first (a library) have nothing to focus at
  /// the start, so it checks again for a moment.
  void _focusNewPage([int attempt = 0]) {
    if (!mounted) return;
    // You've already moved on: leave focus be.
    if (attempt > 0 && (_pageScope.hasFocus || _menuScope.hasFocus || _barScope.hasFocus)) return;

    final first = firstFocusable(_pageScope, mainOnly: true) ?? (attempt >= 20 ? firstFocusable(_pageScope) : null);
    if (first != null) {
      first.requestFocus();
      if (first.context case final context?) {
        Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      }
      scrollToStartIfFirst(first);
      return;
    }
    if (attempt == 0) _pageScope.requestFocus();
    if (attempt >= 40) return; // nothing to focus on this page at all
    Future.delayed(const Duration(milliseconds: 100), () => _focusNewPage(attempt + 1));
  }

  /// Focuses whatever last had focus inside [scope] if it's still on the page you're looking
  /// at, or else that page's first item.
  void _focusFirstOrRemembered(FocusScopeNode scope) {
    final remembered = _rememberedIn(scope);
    if (remembered != null) {
      remembered.requestFocus();
    } else {
      firstFocusable(scope)?.requestFocus();
    }
  }

  /// The item last focused inside [scope], following its scopes down (each page keeps its
  /// own), or null if there isn't one or it's on a page that's now hidden.
  FocusNode? _rememberedIn(FocusScopeNode scope) {
    FocusNode? node = scope.focusedChild;
    while (node is FocusScopeNode && node.focusedChild != null) {
      node = node.focusedChild;
    }
    if (node == null || node is FocusScopeNode || !node.canRequestFocus) return null;
    return isOnTopPage(node) ? node : null;
  }

  /// The top bar's title on a page with one (a library, Settings, ...); null shows the logo.
  String? get _title {
    final loc = widget.location;
    if (loc.startsWith('/search')) return 'Search';
    if (loc == '/downloads') return 'Downloads';
    if (loc == '/home/favorites') return 'Favorites';
    if (loc == '/home/genres') return 'Genres';
    if (loc.startsWith('/home/genre/')) return Uri.decodeComponent(loc.split('/').last);
    if (loc.startsWith('/home/library/')) {
      final id = loc.split('/').last;
      return jellyfin.libraries.where((l) => l.id == id).firstOrNull?.name;
    }
    if (loc == '/settings' || loc == '/profile') return widget.group ?? 'Settings';
    return null;
  }

  /// The top bar, floating over the page and sliding up out of sight as the page scrolls
  /// down: see-through, its buttons on glass islands, covering the status bar too (the page runs
  /// up under both).
  Widget _collapsing(BuildContext context, Widget bar) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [SizedBox(height: MediaQuery.paddingOf(context).top), bar],
    );
    return ValueListenableBuilder(
      valueListenable: _barShown,
      // Slid up and faded out together, so nothing of it (its islands' shadows) is left at the
      // edge however short it is.
      builder: (context, shown, content) => IgnorePointer(
        ignoring: !shown,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          opacity: shown ? 1 : 0,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            offset: shown ? Offset.zero : const Offset(0, -1.2),
            child: content,
          ),
        ),
      ),
      child: content,
    );
  }

  /// The top bar's height when it shows (not counting the status bar): its padding and a row of
  /// buttons on islands (see _TopBar). Nothing when it's empty.
  static double _barHeight(ScreenType type, {required bool empty}) =>
      empty ? 0 : (type.isTv ? 24 + 8 : 4 + 4) + 48 + 6;

  /// The top bar's contents for where you are ([detail]: the detail page on top, if any).
  /// Nothing at all when it would be empty: Home beside a pinned menu (which has the logo, cast,
  /// Settings and your profile).
  Widget _topBar(
    BuildContext context, {
    required ScreenType type,
    required bool pinned,
    required ValueNotifier<String?>? detail,
  }) {
    final home = detail == null && widget.location == '/home';
    if (pinned && home) return const SizedBox(width: double.infinity);
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: FocusScope(
        node: _barScope,
        onKeyEvent: _onBarKey,
        child: ValueListenableBuilder<String?>(
          valueListenable: detail ?? ValueNotifier<String?>(null),
          // Home has the menu button and the logo. Every other page has Back (to the page
          // before, or Home) and its name, centered.
          builder: (context, detailTitle, _) => ValueListenableBuilder(
            valueListenable: _atTop,
            builder: (context, atTop, _) => _TopBar(
              textShown: atTop,
              // Every page but Home, TVs too (alongside the remote's Back).
              canGoBack: !home,
              onBack: () {
                final router = GoRouter.of(context);
                if (router.canPop()) {
                  router.pop();
                } else {
                  _goTo('/home');
                }
              },
              showMenuButton: !pinned && home,
              onMenu: _openMenu,
              // (A detail page's own name is big on the page itself.)
              centeredTitle: home || detail != null ? null : (_title ?? ''),
              showLogo: !pinned && home,
              // Pinned, the menu has cast, Settings and your profile.
              showAccount: !pinned,
              onSettings: () => _goTo('/settings'),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Rebuild when signing in or out.
    listenable: jellyfin,
    builder: (context, _) {
      // Signed out: the router is about to show the login page. Draw nothing in the meantime,
      // since every page here needs a connected client.
      if (!jellyfin.isConnected) return const SizedBox.shrink();

      final type = ScreenType.of(context);
      final size = MediaQuery.sizeOf(context);
      final pinned = _pinned && _canPin(context);
      // Tabs along the bottom on phones, and tablets held upright.
      final bottomBar = type.isPhone || (type == ScreenType.tablet && size.height > size.width);

      // The page's view of the screen: below the top bar (which takes the top inset), right of a
      // pinned menu (which takes the left one), and with the floating bottom bar's height as the
      // room to leave at the bottom (pageBottom). The keyboard is handled by the shell already.
      final media = MediaQuery.of(context);
      EdgeInsets inset(EdgeInsets e) => e.copyWith(
        top: 0,
        left: pinned ? 0 : e.left,
        bottom: bottomBar ? _footerHeight : e.bottom,
      );
      if (bottomBar) WidgetsBinding.instance.addPostFrameCallback((_) => _measureFooter());
      final Widget page = MediaQuery(
        data: media.copyWith(
          padding: inset(media.padding),
          viewPadding: inset(media.viewPadding),
          viewInsets: media.viewInsets.copyWith(bottom: 0),
          // Dropdowns and menus decide whether to open up or down by measuring the screen: it
          // ends where the bottom bar starts, so nothing opens behind the bar.
          // The page's own width too: narrower beside a pinned menu.
          size: Size(
            media.size.width - (pinned ? media.padding.left + _menuWidth : 0),
            media.size.height - (bottomBar ? _footerHeight : 0),
          ),
        ),
        // Pages run to the bottom of the screen, under the home indicator (and the bottom bar,
        // where there is one): they leave room for those inside their scrolling (pageBottom).
        child: FocusScope(
          node: _pageScope,
          onKeyEvent: type.isPhone ? null : _onPageKey,
          child: widget.navigationShell,
        ),
      );

      final menu = _Menu(
        pinned: pinned,
        canPin: _canPin(context),
        onPin: _togglePinned,
        onClose: _closeMenu,
        here: _here,
        location: widget.location,
        myMediaOpen: _myMediaOpen,
        onMyMedia: (open) => setState(() => _myMediaOpen = open),
        nodeFor: _menuNode,
        goTo: _goTo,
      );

      return BackButtonListener(
        // The remote's Back closes the menu first.
        onBackButtonPressed: () async => _back(),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (!_back() && GoRouter.of(context).canPop()) GoRouter.of(context).pop();
            },
          },
          child: Scaffold(
          body: Stack(
            children: [
              // Pinned, the menu runs the full height of the screen, with the top bar and the
              // page beside it.
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (pinned)
                    FocusScope(
                      node: _menuScope,
                      onKeyEvent: _onMenuKey,
                      child: SizedBox(width: MediaQuery.paddingOf(context).left + _menuWidth, child: menu),
                    ),
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeLeft: pinned, // the menu clears any camera cutout
                      // A detail page (a movie's, a person's, ...) runs up under a glass top bar;
                      // other pages sit below a solid one.
                      child: ListenableBuilder(
                        listenable: pageStackChanged,
                        builder: (context, _) {
                          final detail = detailTitleOf(pageStackObservers[widget.navigationShell.currentIndex].top);
                          final body = Stack(
                            // The bottom bar floats over the page, which shows around it.
                            children: [
                              Positioned.fill(
                                child: NotificationListener<ScrollMetricsNotification>(
                                  onNotification: _onPageMetrics,
                                  child: NotificationListener<ScrollUpdateNotification>(
                                    onNotification: _onPageScroll,
                                    child: page,
                                  ),
                                ),
                              ),
                              if (bottomBar)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: _BottomBar(key: _footerKey, location: widget.location, goTo: _goTo),
                                ),
                            ],
                          );
                          final bar = _topBar(context, type: type, pinned: pinned, detail: detail);
                          if (detail != null) {
                            return Stack(
                              children: [
                                Positioned.fill(child: body),
                                Positioned(top: 0, left: 0, right: 0, child: _collapsing(context, bar)),
                              ],
                            );
                          }
                          // Elsewhere the bar floats over the page too, which keeps room for it at
                          // the top of its content (TopBarSpace), so the bar going doesn't move
                          // anything. The page runs up under the status bar, which the bar covers
                          // while it shows; scrolled, the page fills the screen.
                          final statusBar = MediaQuery.paddingOf(context).top;
                          final empty = pinned && widget.location == '/home';
                          _barRoomStatus = statusBar;
                          final room = statusBar + _barHeight(type, empty: empty);
                          if (room != _barRoom) {
                            _barRoom = room;
                            WidgetsBinding.instance.addPostFrameCallback((_) => _onBarShown());
                          }
                          return TopBarSpace(
                            height: room,
                            child: Stack(
                              children: [
                                Positioned.fill(child: MediaQuery.removePadding(context: context, removeTop: true, child: body)),
                                Positioned(top: 0, left: 0, right: 0, child: _collapsing(context, bar)),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              // Slid out over the page: a scrim behind it, which closes it when selected.
              if (!pinned)
                Positioned.fill(
                  child: ValueListenableBuilder(
                    valueListenable: _menuOpen,
                    builder: (context, open, _) => Stack(
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: !open,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _closeMenu,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: open ? 1 : 0,
                                child: ColoredBox(color: context.colors.scrim.withValues(alpha: 0.25)),
                              ),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          top: 0,
                          bottom: 0,
                          left: open ? 0 : -(MediaQuery.paddingOf(context).left + _menuWidth + 24),
                          width: MediaQuery.paddingOf(context).left + _menuWidth,
                          child: IgnorePointer(
                            ignoring: !open,
                            child: ExcludeFocus(
                              excluding: !open,
                              // A shadow along its edge, lifting it off the page while it's out.
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  boxShadow: open
                                      ? const [BoxShadow(color: Color(0x80000000), blurRadius: 32, offset: Offset(8, 0))]
                                      : const [],
                                ),
                                child: FocusScope(node: _menuScope, onKeyEvent: _onMenuKey, child: menu),
                              ),
                            ),
                          ),
                        ),
                      ],
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

