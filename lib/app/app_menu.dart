part of 'app_shell.dart';

// ─── Top bar ─────────────────────────────────────────────────────────────────

/// Across the top of every page: on Home the menu button and the logo, elsewhere Back and the
/// page's name, centered; casting, Settings and who's signed in on the right.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.canGoBack,
    required this.onBack,
    required this.showMenuButton,
    required this.onMenu,
    this.centeredTitle,
    required this.showLogo,
    this.showAccount = true,
    this.textShown = true,
    required this.onSettings,
  });

  final bool canGoBack;
  final VoidCallback onBack;
  final bool showMenuButton;
  final VoidCallback onMenu;
  /// Every page but Home: its name, centered (empty while a title's page loads). The menu
  /// button and logo make way for it.
  final String? centeredTitle;
  final bool showLogo; // when there's no title (the menu shows it while pinned)
  /// Cast, Settings and your profile picture (false while the menu is pinned: they're in it).
  final bool showAccount;
  /// The logo or title shows: only while the page is at its top, so if the bar ever comes
  /// down over the middle of a page, it's just its buttons over the content.
  final bool textShown;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final type = ScreenType.of(context);
    final isPhone = type.isPhone;
    // As tall as what's in it. TVs get more room above, clear of the screen's edge (which some
    // TVs crop).
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: type.isTv
            ? const EdgeInsets.fromLTRB(24, 24, 24, 8)
            : EdgeInsets.symmetric(horizontal: isPhone ? 4 : 12, vertical: 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final castShown = showCastButton && showAccount;
            const button = 52.0; // a bar button and its margin
            // The right side: cast (when there's somewhere to cast to), Settings and the avatar.
            final right = button * ((castShown ? 1 : 0) + (showAccount ? 2 : 0));
            final left = button * ((showMenuButton ? 1 : 0) + (canGoBack ? 1 : 0)) + 8;
            final row = FocusRow(
              child: Row(
                children: [
                  // The menu button always first, so it never moves; Back after it, before the title.
                  if (showMenuButton || canGoBack)
                    _Island(
                      children: [
                        if (showMenuButton) _BarButton(icon: appIcons.menu, label: 'Menu', onPress: onMenu),
                        if (canGoBack) _BarButton(icon: appIcons.back, label: 'Back', onPress: onBack),
                      ],
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: centeredTitle != null
                          ? const SizedBox.shrink() // centered over the row, below
                          : showLogo
                          ? _FadeText(
                              shown: textShown,
                              child: AppLogo(
                                asset: 'assets/images/text_logo.svg',
                                colorAsset: 'assets/images/text_logo_color.svg',
                                height: isPhone ? 26 : 30,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  if (castShown || showAccount)
                    _Island(
                      children: [
                        // Somewhere to cast to (a Chromecast on the network, or AirPlay on iPhone and iPad).
                        if (castShown)
                          _BarButton(
                            icon: castIcon,
                            label: 'Play on another device',
                            color: castController.isConnected ? context.colors.primary : null,
                            onPress: () => showCastMenu(context),
                          ),
                        // Cast, Settings, then who's signed in. (Search is in the menu and the bottom bar.)
                        if (showAccount) ...[
                          _BarButton(icon: appIcons.settings, label: 'Settings', onPress: onSettings),
                          _BarButton(
                            label: 'Switch user (${jellyfin.userName ?? 'signed in'})',
                            onPress: () => showProfilePicker(context), // "Who's watching?"
                            child: UserAvatar(size: isPhone ? 30 : 34),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            );
            if (centeredTitle == null) return row;
            // The title in the middle of the bar, as wide as the room both sides leave it (the
            // wider side, mirrored), so it's centered and never runs into a button.
            final width = (constraints.maxWidth - 2 * math.max(left, right) - 16).clamp(0.0, 720.0);
            return Stack(
              alignment: Alignment.center,
              children: [
                row,
                IgnorePointer(
                  child: SizedBox(
                    width: width,
                    child: _FadeText(
                      shown: textShown,
                      child: Text(
                        centeredTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: context.text.titleLarge,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The top bar's logo or title, faded out while [shown] is false.
class _FadeText extends StatelessWidget {
  const _FadeText({required this.shown, required this.child});

  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    duration: const Duration(milliseconds: 150),
    opacity: shown ? 1 : 0,
    child: child,
  );
}

/// Some of the top bar's buttons side by side, on a pill of frosted glass like the bottom
/// bar's. (The logo and a page's title sit straight on the page, with no island.)
class _Island extends StatelessWidget {
  const _Island({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final row = Row(mainAxisSize: MainAxisSize.min, children: children);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: ColoredBox(
            color: context.colors.surfaceContainer.withValues(alpha: 0.55),
            // As close around the buttons as above and below them (each has 2 of its own at the sides).
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 1), child: row),
          ),
        ),
      ),
    );
  }
}

/// A top bar button: an icon (or [child]) in a circle that darkens in under the pointer or the
/// remote, with no ring around it.
class _BarButton extends StatelessWidget {
  const _BarButton({required this.label, required this.onPress, this.icon, this.child, this.color, this.focusNode});

  final String label; // for screen readers
  final FocusNode? focusNode;
  final VoidCallback onPress;
  final IconData? icon;
  final Widget? child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Tappable(
    focusNode: focusNode,
    onPress: onPress,
    semanticsLabel: label,
    builder: (context, states, child) => AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 48,
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isHighlighted(states) ? context.colors.onSurface.withValues(alpha: 0.14) : const Color(0x00000000),
      ),
      child: child,
    ),
    child: child ?? Icon(icon, fill: 1, color: color),
  );
}

// ─── Menu ────────────────────────────────────────────────────────────────────

/// The menu: Home, Search, Downloads, Favorites and Genres, then your libraries under My Media.
/// It slides out over the page, or on wide screens can stay open beside it ([pinned]).
class _Menu extends StatelessWidget {
  const _Menu({
    required this.pinned,
    required this.canPin,
    required this.onPin,
    required this.onClose,
    required this.here,
    required this.location,
    required this.myMediaOpen,
    required this.onMyMedia,
    required this.nodeFor,
    required this.goTo,
  });

  final bool pinned;
  final bool canPin;
  final VoidCallback onPin; // pins it, or unpins it
  final VoidCallback onClose;
  final String here; // the entry for where you are
  final String location;
  final bool myMediaOpen;
  final ValueChanged<bool> onMyMedia;
  final FocusNode Function(String id) nodeFor;
  final void Function(String path) goTo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isTv = ScreenType.of(context).isTv;
    return ListenableBuilder(
      listenable: Listenable.merge([jellyfin, homeEditing, castController]),
      builder: (context, _) {
        final editing = homeEditing.value;
        Widget item(String id, String label, IconData icon, String path) => _MenuItem(
          label: label,
          icon: icon,
          focusNode: nodeFor(id),
          selected: here == id,
          onPress: () => goTo(path),
        );
        // Pinned: solid, beside the page. Slid out over it: frosted glass, the page blurred
        // behind it.
        final content = SafeArea(
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Logo, and pin / close ──
                Padding(
                  // TVs: clear of the screen's edge, in line with the top bar.
                  padding: EdgeInsets.fromLTRB(isTv ? 28 : 20, isTv ? 32 : 16, 12, 8),
                  child: Row(
                    spacing: 16, // room between the logo and the pin
                    children: [
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AppLogo(
                            asset: 'assets/images/text_logo.svg',
                            colorAsset: 'assets/images/text_logo_color.svg',
                            height: 30,
                          ),
                        ),
                      ),
                      // Pin it beside the page, or unpin it. Where it can't stay open (phones,
                      // tablets held upright) there's no button: tap outside or swipe it away.
                      if (canPin)
                        _BarButton(
                          focusNode: nodeFor('Pin'),
                          label: pinned ? 'Close the menu' : 'Keep the menu open',
                          icon: pinned ? appIcons.close : appIcons.pinMenu,
                          onPress: onPin,
                        )

                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, pinned ? 8 : 16),
                    children: [
                      item('Home', 'Home', appIcons.home, '/home'),
                      item('Search', 'Search', appIcons.search, '/search'),
                      if (DownloadsController.supported) item('Downloads', 'Downloads', appIcons.download, '/downloads'),
                      item('Favorites', 'Favorites', appIcons.favorite, '/home/favorites'),
                      if (jellyfin.genres.isNotEmpty) item('Genres', 'Genres', appIcons.genres, '/home/genres'),

                      // ── My Media: the libraries, folding away ──
                      if (jellyfin.libraries.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _MenuHeading(label: 'My Media', open: myMediaOpen, onPress: () => onMyMedia(!myMediaOpen)),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: myMediaOpen
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (final lib in jellyfin.libraries)
                                      item(
                                        'Library/${lib.id}',
                                        lib.name,
                                        libraryIcon(lib.collectionType),
                                        '/home/library/${lib.id}',
                                      ),
                                  ],
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ],

                      // Editing Home: on every screen.
                      ...[
                        const SizedBox(height: 12),
                        _MenuItem(
                          label: editing ? 'Done editing' : 'Edit home',
                          icon: editing ? appIcons.check : appIcons.edit,
                          focusNode: nodeFor('Edit'),
                          selected: editing,
                          onPress: () {
                            homeEditing.value = !editing;
                            goTo('/home');
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                // ── Pinned: cast, Settings and who's signed in, out of the top bar ──
                if (pinned)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(height: 17, color: colors.outlineVariant.withValues(alpha: 0.5)),
                        // Somewhere to cast to: the same cast symbol as in the top bar.
                        if (showCastButton)
                          _MenuItem(
                            label: castController.isConnected ? 'Casting' : 'Cast',
                            icon: castIcon,
                            focusNode: nodeFor('Cast'),
                            selected: castController.isConnected,
                            onPress: () => showCastMenu(context),
                          ),
                        _MenuItem(
                          label: 'Settings',
                          icon: appIcons.settings,
                          focusNode: nodeFor('Settings'),
                          selected: location.startsWith('/settings'), // any of its sections too
                          onPress: () => goTo('/settings'),
                        ),
                        _MenuItem(
                          label: jellyfin.userName ?? 'Switch user',
                          leading: const UserAvatar(size: 26),
                          focusNode: nodeFor('Profile'),
                          onPress: () => showProfilePicker(context), // "Who's watching?"
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        if (pinned) return Material(color: colors.surfaceContainerLow, child: content);

        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Material(color: colors.surfaceContainer.withValues(alpha: 0.55), child: content),
          ),
        );
      },
    );
  }
}

/// One menu entry: an icon and a label, filled in when it's the page you're on.
class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.label,
    this.icon,
    this.leading,
    required this.onPress,
    this.focusNode,
    this.selected = false,
  });

  final String label;
  final IconData? icon;
  final Widget? leading; // in place of the icon (your profile picture)
  final VoidCallback onPress;
  final FocusNode? focusNode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.onPrimary : colors.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tappable(
        focusNode: focusNode,
        onPress: onPress,
        builder: (context, states, child) {
          final highlighted = isHighlighted(states);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              // The page you're on is filled in; under the remote or the pointer, a little lighter.
              color: selected
                  ? (highlighted ? Color.lerp(colors.primary, colors.onPrimary, 0.35) : colors.primary)
                  : highlighted
                  ? colors.onSurface.withValues(alpha: 0.10)
                  : const Color(0x00000000),
              borderRadius: BorderRadius.circular(12),
            ),
            child: child,
          );
        },
        child: Row(
          spacing: 14,
          children: [
            leading ?? Icon(icon, size: 24, color: foreground, fill: 1),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleMedium?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A heading in the menu that folds what's under it away, or back out.
class _MenuHeading extends StatelessWidget {
  const _MenuHeading({required this.label, required this.open, required this.onPress});

  final String label;
  final bool open;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) => Tappable(
    onPress: onPress,
    builder: (context, states, child) => AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        color: isHighlighted(states) ? context.colors.onSurface.withValues(alpha: 0.10) : const Color(0x00000000),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: context.text.titleSmall?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
        AnimatedRotation(
          duration: const Duration(milliseconds: 150),
          turns: open ? 0 : -0.25, // down while open, right while folded
          child: Icon(appIcons.expand, size: 20, color: context.colors.primary),
        ),
      ],
    ),
  );
}

// ─── Bottom bar ──────────────────────────────────────────────────────────────

/// Phones, and tablets held upright: the buttons from Settings › Appearance (Home, Search,
/// Downloads and the first library, unless changed), in a pill floating over the bottom of the
/// page, the page showing around it.
class _BottomBar extends StatelessWidget {
  const _BottomBar({super.key, required this.location, required this.goTo});

  final String location;
  final void Function(String path) goTo;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([jellyfin, bottomBarTabs]),
    builder: (context, _) {
      final colors = context.colors;
      final tabs = bottomBarTabs.tabs;
      return SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            // Frosted glass, like the menu while it's slid out: the page blurred behind it.
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    color: colors.surfaceContainer.withValues(alpha: 0.55),
                    child: Row(
                spacing: 4,
                children: [
                  for (final tab in tabs)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final selected = location == tab.path || (tab.path == '/search' && location.startsWith('/search'));
                          final foreground = selected ? colors.onPrimary : colors.onSurface;
                          return Tappable(
                            onPress: () => goTo(tab.path),
                            semanticsLabel: tab.label,
                            builder: (context, states, child) => AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: selected
                                    ? colors.primary
                                    : isHighlighted(states)
                                    ? colors.onSurface.withValues(alpha: 0.10)
                                    : const Color(0x00000000),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: child,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 2,
                              children: [
                                Icon(tab.icon, fill: 1, color: foreground),
                                Text(
                                  tab.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.labelMedium?.copyWith(color: foreground),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
