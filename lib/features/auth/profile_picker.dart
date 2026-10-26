import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/app_icons.dart';
import '../../core/format/format.dart';
import '../../core/jellyfin/jellyfin_controller.dart';
import '../../widgets/app_logo.dart';
import '../../theme/theme.dart';
import '../../core/focus/focus_rows.dart';

// ─── "Who's watching?" ───────────────────────────────────────────────────────
//
// Shows everyone who can use the app on this device: accounts already signed in here
// (switch instantly) and the users the server lists on its login screen (sign in once).

/// The full-screen picker, shown at launch when this device has more than one account,
/// and after signing out while others are still saved. Route: `/profiles`.
class ProfilePickerScreen extends StatelessWidget {
  const ProfilePickerScreen({super.key, this.server});

  /// The server to show the people of; the one in use if not given.
  final String? server;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SafeArea(
      child: ListenableBuilder(
        listenable: jellyfin,
        builder: (context, _) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: jellyfin.switching
                // Between two users: the router brings Home back as soon as the new one has loaded.
                ? const Column(
                    mainAxisSize: .min,
                    spacing: 16,
                    children: [CircularProgressIndicator(), Text('Switching…')],
                  )
                : Column(
                    mainAxisSize: .min,
                    children: [
                      const AppLogo(
                        asset: 'assets/images/text_logo.svg',
                        colorAsset: 'assets/images/text_logo_color.svg',
                        height: 48,
                        variant: AppLogoVariant.auto,
                      ),
                      const SizedBox(height: 32),
                      ProfilePicker(server: server),
                      // Opened from your profile picture: back to where you were.
                      if (jellyfin.isConnected && GoRouter.of(context).canPop()) ...[
                        const SizedBox(height: 16),
                        OutlinedButton(onPressed: () => GoRouter.of(context).pop(), child: const Text('Back')),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    ),
    ),
  );
}

/// "Who's watching?" from your profile picture: the same screen as at launch, over the app.
/// Back (or picking yourself) returns to where you were; picking someone else switches to them.
Future<void> showProfilePicker(BuildContext context) => GoRouter.of(context).push('/profiles?pick=1');

/// One person in the picker. At least one of [saved] or [public] is set.
class _Profile {
  const _Profile({required this.name, this.imageUrl, this.saved, this.public});

  final String name;
  final String? imageUrl;
  final SavedAccount? saved; // signed in on this device: switch without a password
  final PublicUser? public; // listed by the server: can sign in

  bool get isCurrent {
    final current = jellyfin.currentAccount;
    return current != null && saved != null && current.isSame(saved!.server, saved!.userId);
  }

  String get key => saved != null ? '${saved!.server}|${saved!.userId}' : '${public!.server}|${public!.id}';
}

/// The row of avatar tiles, plus Add Account.
class ProfilePicker extends StatefulWidget {
  const ProfilePicker({super.key, this.server});

  /// The server to start on; the one in use if not given.
  final String? server;

  @override
  State<ProfilePicker> createState() => _ProfilePickerState();
}

class _ProfilePickerState extends State<ProfilePicker> {
  List<PublicUser> _public = const [];
  bool _loadingPublic = true;
  String? _busyKey; // the tile being signed in, shows a spinner
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPublicUsers();
    jellyfin.checkAccounts(); // drops accounts that no longer exist, and updates renamed ones
  }

  /// The server whose people show: each server's accounts and users only ever show under it.
  late String? _server = widget.server ?? jellyfin.client?.baseUrl ?? jellyfin.lastServer;

  void _showServer(String server) {
    if (server == _server) return;
    setState(() {
      _server = server;
      _public = const [];
      _loadingPublic = true;
      _error = null;
    });
    _loadPublicUsers();
  }

  Future<void> _loadPublicUsers() async {
    final server = _server;
    final users = server == null ? const <PublicUser>[] : await jellyfin.publicUsers(server);
    if (mounted && server == _server) {
      setState(() {
        _public = users;
        _loadingPublic = false;
      });
    }
  }

  /// Saved accounts first (in the order they were added), then server users not yet signed in here.
  /// Signed in on this device first (whoever's using the app now at the very front), then the
  /// server's other users.
  List<_Profile> get _profiles {
    final current = jellyfin.currentAccount;
    bool isCurrent(SavedAccount a) => current != null && a.isSame(current.server, current.userId);
    final here = [for (final a in jellyfin.accounts) if (a.server == _server) a];
    return [
    for (final a in [...here.where(isCurrent), ...here.where((a) => !isCurrent(a))])
      _Profile(
        name: a.name,
        imageUrl: a.imageUrl,
        saved: a,
        public: _public.where((p) => p.server == a.server && p.id == a.userId).firstOrNull,
      ),
    for (final p in _public)
      if (!jellyfin.accounts.any((a) => a.isSame(p.server, p.id)))
        _Profile(name: p.name, imageUrl: p.imageUrl, public: p),
    ];
  }

  Future<void> _select(_Profile profile) async {
    if (_busyKey != null) return;
    if (profile.isCurrent) {
      // Yourself: back to where you were.
      if (GoRouter.of(context).canPop()) GoRouter.of(context).pop();
      return;
    }
    setState(() {
      _busyKey = profile.key;
      _error = null;
    });
    try {
      if (profile.saved != null) {
        try {
          await jellyfin.switchTo(profile.saved!);
        } on AccountExpiredException {
          // Its token died. If the server lists this user, ask for their password instead.
          final public = profile.public;
          if (public == null) rethrow;
          if (mounted) setState(() => _busyKey = null);
          if (mounted) await _signInPublic(public);
        }
      } else {
        await _signInPublic(profile.public!);
      }
    } on AccountExpiredException catch (e) {
      if (mounted) setState(() => _error = '${profile.name}: $e');
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = describeJellyfinError(e));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
    // Switched: the router takes the app to the new person's Home.
  }

  /// Users without a password sign straight in; everyone else gets the password box.
  Future<void> _signInPublic(PublicUser user) async {
    if (!user.hasPassword) {
      await jellyfin.signIn(server: user.server, username: user.name, password: '');
      return;
    }
    if (mounted) setState(() => _busyKey = null);
    if (!mounted) return;
    // Their password on the sign-in page, as when signing in from scratch. Back returns here.
    await GoRouter.of(context).push(
      Uri(
        path: '/login',
        queryParameters: {
          if (jellyfin.isConnected) 'add': '1',
          'server': user.server,
          'user': user.id,
          'name': user.name,
        },
      ).toString(),
    );
  }

  void _addAccount() {
    // Someone new on the same server: straight to their username and password. With no server
    // yet, the whole sign-in.
    final server = _server;
    GoRouter.of(context).push(
      Uri(
        path: '/login',
        queryParameters: {if (jellyfin.isConnected) 'add': '1', 'server': ?server, if (server != null) 'new': '1'},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: jellyfin,
    builder: (context, _) {
      final profiles = _profiles;
      return Column(
        mainAxisSize: .min,
        spacing: 16,
        children: [
          // More than one server: which one's people show.
          if (jellyfin.servers.length > 1)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final server in jellyfin.servers)
                  FutureBuilder(
                    future: jellyfin.nameOf(server),
                    builder: (context, name) => ChoiceChip(
                      label: Text(name.data ?? displayServerUrl(server)),
                      selected: server == _server,
                      onSelected: (_) => _showServer(server),
                    ),
                  ),
              ],
            ),
          // One row that scrolls sideways, centered while everyone fits.
          ProfileRow(
            children: [
              for (final (i, p) in profiles.indexed) ...[
                // Between those signed in here and everyone else.
                if (i > 0 && p.saved == null && profiles[i - 1].saved != null) const ProfileDivider(),
                ProfileTile(
                  name: p.name,
                  imageUrl: p.imageUrl,
                  current: p.isCurrent,
                  signedIn: p.saved != null,
                  busy: _busyKey == p.key,
                  autofocus: i == 0,
                  onPress: () => _select(p),
                ),
              ],
              ProfileTile(
                name: 'Add account',
                icon: appIcons.addUser,
                autofocus: profiles.isEmpty,
                onPress: _addAccount,
              ),
            ],
          ),
          if (_loadingPublic && profiles.isEmpty) const CircularProgressIndicator(),
          if (_error != null)
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.colors.error)),
        ],
      );
    },
  );
}

/// Profiles in one row that scrolls sideways, centered while they all fit, with room above and
/// below for a tile to grow as it's focused. Used by "Who's watching?" and sign-in.
class ProfileRow extends StatelessWidget {
  const ProfileRow({super.key, required this.children, this.spacing = 24});

  final List<Widget> children;
  final double spacing;

  /// How far in from each side the row fades out.
  static const _fade = 28.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // Kept inside its space, fading out at both sides, so profiles scrolled past the edge slip
    // away softly instead of being cut off (or drawn outside the card).
    builder: (context, constraints) => ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        stops: [0, _fade / bounds.width, 1 - _fade / bounds.width, 1],
      ).createShader(bounds),
      child: FocusRow(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // Room at the ends to scroll the first and last clear of the fade, and above and below
        // for a tile to grow as it's focused.
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: _fade),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth - 2 * _fade),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: spacing,
            children: children,
          ),
        ),
      ),
    ),
    ),
  );
}

// ─── A tile ──────────────────────────────────────────────────────────────────

/// A big round avatar with the name under it. Grows and gets a ring when focused,
/// so it's easy to see from across the room.
class ProfileTile extends StatefulWidget {
  const ProfileTile({
    super.key,
    required this.name,
    required this.onPress,
    this.imageUrl,
    this.icon,
    this.current = false,
    this.signedIn = false,
    this.busy = false,
    this.autofocus = false,
  });

  final String name;
  final String? imageUrl;
  final IconData? icon; // instead of a picture, for Add account
  final bool current; // the user signed in now

  /// Signed in on this device already: switching needs no password. Marked with a check.
  final bool signedIn;
  final bool busy;
  final bool autofocus;
  final VoidCallback onPress;

  @override
  State<ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<ProfileTile> {
  static const _size = 112.0;
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _focused || _hovered;
    final initials = Text(initialsOf(widget.name), style: theme.textTheme.headlineSmall);

    // The initials sit under the picture, so they show while it loads or if it can't.
    final Widget picture = CircleAvatar(
      radius: _size / 2,
      foregroundImage: widget.icon == null && widget.imageUrl != null ? NetworkImage(widget.imageUrl!) : null,
      child: widget.icon != null ? Icon(widget.icon, size: 44, fill: 1) : initials,
    );

    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      mouseCursor: SystemMouseCursors.click,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPress()),
      },
      child: GestureDetector(
        onTap: widget.onPress,
        child: SizedBox(
          width: _size + 24,
          child: Column(
            mainAxisSize: .min,
            spacing: 10,
            children: [
              AnimatedScale(
                scale: active ? 1.08 : 1,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 3,
                          color: active
                              ? theme.colorScheme.primary
                              : widget.current
                              ? theme.colorScheme.outlineVariant
                              : Colors.transparent,
                        ),
                      ),
                      child: Opacity(opacity: widget.busy ? 0.4 : 1, child: picture),
                    ),
                    if (widget.busy) const CircularProgressIndicator(),
                    // Signed in here: a check on the picture's corner.
                    if (widget.signedIn || widget.current)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primary,
                            border: Border.all(color: theme.scaffoldBackgroundColor, width: 3),
                          ),
                          child: Icon(appIcons.check, size: 18, color: theme.colorScheme.onPrimary),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                widget.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: active ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                  fontWeight: active || widget.current ? FontWeight.w600 : null,
                ),
              ),
              if (widget.current || widget.signedIn)
                Text(
                  widget.current ? 'Current' : 'Signed in',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin line in a [ProfileRow], between the profiles signed in on this device and the rest.
class ProfileDivider extends StatelessWidget {
  const ProfileDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 112,
    margin: const EdgeInsets.only(top: 4),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

// ─── Password ────────────────────────────────────────────────────────────────

