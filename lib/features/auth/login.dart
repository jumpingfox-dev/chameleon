import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/jellyfin/jellyfin_controller.dart';
import '../../core/platform/screen_type.dart';
import '../../widgets/remote_text_field.dart';
import 'profile_picker.dart' show ProfileDivider, ProfileRow, ProfileTile;
import 'quick_connect_dialog.dart';
import '../../theme/app_icons.dart';
import '../../widgets/app_logo.dart';
import '../../theme/theme.dart';
import '../../widgets/server_backdrop.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.server,
    this.userId,
    this.userName,
    this.newUser = false,
    this.freshServer = false,
  });

  /// Opened for one of [server]'s users (picked on "Who's watching?"): straight to their
  /// password, on that server. Back then returns to "Who's watching?".
  final String? server;
  final String? userId;
  final String? userName;

  /// Someone new on [server] (Add account): straight to the username and password.
  final bool newUser;

  /// Adding another server: its address starts empty rather than the last one used.
  final bool freshServer;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Where signing in is up to: the server's address, then who's signing in (the server's
/// public users, or a username), then a password.
enum _Step { server, users, account }

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _fields = [
    FocusNode(),
    FocusNode(),
    FocusNode(),
  ]; // server, username, password
  bool _busy = false;
  _Step _step = _Step.server;

  /// The server's name and its public users, once connected.
  String? _serverName;

  List<PublicUser> _users = const [];

  /// Signing in as one of the public users: their name is filled in, and only the password's
  /// asked for. Null when typing a username.
  PublicUser? _user;

  double _keyboard =
      0; // the on-screen keyboard's height, last time it was looked at

  @override
  void initState() {
    super.initState();
    if (widget.server ?? (widget.freshServer ? null : jellyfin.lastServer) case final server?) {
      _server.text = displayServerUrl(server);
    }
    // A user picked on "Who's watching?": the server and who it is are known, so straight to
    // their password. Only the server's name (for the title) is looked up, meanwhile.
    if ((widget.server, widget.userId, widget.userName) case (final server?, final id?, final name?)) {
      _user = PublicUser(server: server, id: id, name: name, hasPassword: true);
      _username.text = name;
      _step = _Step.account;
      _lookUpServerName(server);
    } else if (widget.newUser && widget.server != null) {
      _step = _Step.account;
      _lookUpServerName(widget.server!);
    }
    for (final node in _fields) {
      node.addListener(_onFieldFocus);
    }
  }

  @override
  void dispose() {
    _server.dispose();
    for (final node in _fields) {
      node.dispose();
    }
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Whether there's somewhere to go back to: the signed-in user (adding an account)
  /// or the other accounts saved on this device.
  bool get _canGoBack => jellyfin.isConnected || jellyfin.accounts.isNotEmpty;

  void _goBack() => context.go(jellyfin.isConnected ? '/home' : '/profiles');

  /// Typing in a field, or done: on TVs the page makes room for the keyboard (below).
  void _onFieldFocus() {
    if (mounted) setState(() {});
    _revealField();
  }

  /// Whether a field is being typed in.
  bool get _typing => _fields.any((node) => node.hasFocus);

  /// Scrolls the field being typed in to the middle of the space the keyboard leaves, once
  /// that space has settled: on moving to a field, and as the keyboard opens or resizes.
  void _revealField() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final field = _fields.where((node) => node.hasFocus).firstOrNull?.context;
    if (field != null && field.mounted) {
      Scrollable.ensureVisible(
        field,
        // A TV's keyboard covers the bottom half without making room for itself (it doesn't
        // say how tall it is), so the field goes near the top instead.
        alignment: ScreenType.of(context).isTv ? 0.15 : 0.5,
        duration: const Duration(milliseconds: 200),
      );
    }
  });

  /// Waiting on the server, when its step was skipped: a spinner until it answers, so the page
  /// appears whole (its title included) and nobody signs in before it's there.
  bool _loadingServer = false;

  /// It didn't answer: why, with only Back offered.
  String? _serverError;

  /// Checks the server, and gets its name for the title, when its step was skipped.
  void _lookUpServerName(String server) {
    _loadingServer = true;
    jellyfin.checkServer(server).then(
      (serverName) {
        if (mounted) {
          setState(() {
            _serverName = serverName;
            _loadingServer = false;
          });
        }
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _serverError = _signInErrorMessage(e);
            _loadingServer = false;
          });
        }
      },
    );
  }

  /// Step one: reach the server, and see who it lists. No public users: straight to the
  /// username and password.
  Future<void> _connect() async {
    if (_server.text.trim().isEmpty) return _showSignInError(context, 'Enter your server\'s address.');
    setState(() => _busy = true);
    try {
      final name = await jellyfin.checkServer(_server.text);
      final users = await jellyfin.publicUsers(_server.text);
      if (!mounted) return;
      setState(() {
        _serverName = name;
        _users = users;
        _user = null;
        _step = users.isEmpty ? _Step.account : _Step.users;
      });
    } catch (e) {
      if (mounted) await _showSignInError(context, _signInErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A public user: without a password they're signed in straight away, otherwise it's asked for.
  void _pickUser(PublicUser user) {
    if (!user.hasPassword) {
      _username.text = user.name;
      _password.clear();
      _signIn(passwordRequired: false);
      return;
    }
    setState(() {
      _user = user;
      _username.text = user.name;
      _password.clear();
      _step = _Step.account;
    });
  }

  /// Someone the server doesn't list: their username and password.
  void _addUser() => setState(() {
    _user = null;
    _username.clear();
    _password.clear();
    _step = _Step.account;
  });

  /// Back a step: from the password to the users (if there are any), or to the server. Opened
  /// for one user from "Who's watching?", back there.
  void _stepBack() {
    // Opened from "Who's watching?" (for one user, or Add account): back there.
    if ((widget.userId != null || widget.newUser) && _users.isEmpty && GoRouter.of(context).canPop()) {
      GoRouter.of(context).pop();
      return;
    }
    setState(() {
      _step = _step == _Step.account && _users.isNotEmpty ? _Step.users : _Step.server;
      _user = null;
    });
  }

  Future<void> _signIn({bool passwordRequired = true}) async {
    // Caught here, since the server's own answer to these is a bare "400".
    if (_username.text.trim().isEmpty) return _showSignInError(context, 'Enter your username.');
    if (passwordRequired && _password.text.isEmpty) return _showSignInError(context, 'Enter your password.');
    setState(() => _busy = true);
    try {
      await jellyfin.signIn(
        server: _server.text,
        username: _username.text.trim(),
        password: _password.text,
      );
      if (mounted) context.go('/home');
    } on JellyfinException catch (e) {
      if (mounted) await _showSignInError(context, _signInErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _quickConnect() async {
    final signedIn = await showQuickConnect(context, server: _server.text);
    if (signedIn && mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    // Read above the Scaffold, which hides the keyboard from the page as it makes room for it.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard != _keyboard) {
      _keyboard = keyboard;
      _revealField();
    }
    final muted = context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant);
    final (title, subtitle) = switch (_step) {
      _Step.server => (
        jellyfin.isConnected ? 'Add an Account' : 'Connect to Server',
        'Enter your Jellyfin server\'s address.',
      ),
      _Step.users => ('', ''), // laid out like "Who's watching?", below
      _Step.account => (
        _user != null ? [_user!.name, ?_serverName].join(' · ') : 'Sign into ${_serverName ?? 'your server'}',
        '',
      ),
    };

    return Scaffold(
      // Once the server's known, everything in its branding (see ServerBranding).
      body: ServerBranding(
      server: _step == _Step.server ? null : _server.text,
      fresh: true, // just connected: as the server has it now
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                // The users span the screen, as on "Who's watching?"; the rest is a narrow card.
                constraints: BoxConstraints(maxWidth: _step == _Step.users ? double.infinity : 400),
                child: _step == _Step.users ? _usersScreen(context) : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The server's own logo once it's known (see ServerBranding).
                    AppLogo(
                      asset: 'assets/images/text_logo.svg',
                      colorAsset: 'assets/images/text_logo_color.svg',
                      height: 48,
                      variant: AppLogoVariant.auto,
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: [
                            if (_loadingServer)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            else if (_serverError != null)
                              Text(_serverError!, style: muted?.copyWith(color: context.colors.error))
                            else ...[
                              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                              if (subtitle.isNotEmpty) Text(subtitle, style: muted),
                              ...switch (_step) {
                                _Step.server => _serverStep(context),
                                _Step.users => const [], // (its own layout, above)
                                _Step.account => _accountStep(context),
                              },
                            ],
                            if (_step != _Step.server)
                              OutlinedButton(
                                onPressed: _busy ? null : _stepBack,
                                // From the password, Back; only straight after connecting to a
                                // server with no users to pick from, Change server.
                                child: Text(
                                  _step == _Step.account &&
                                          (_users.isNotEmpty || widget.userId != null || widget.newUser)
                                      ? 'Back'
                                      : 'Change server',
                                ),
                              )
                            else if (_canGoBack)
                              OutlinedButton(
                                onPressed: _busy ? null : _goBack,
                                child: Text(jellyfin.isConnected ? 'Cancel' : 'Back'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    ..._disclaimerText(context),
                    // Room to scroll the field above a TV's keyboard while typing.
                    if (_typing && ScreenType.of(context).isTv)
                      SizedBox(height: MediaQuery.sizeOf(context).height * 0.5),
                  ],
                ),
              ),
            ),
          ),
        ),
      )),
    );
  }

  // ── Step one: the server ──

  List<Widget> _serverStep(BuildContext context) => [
    // The port goes in here too, if it isn't Jellyfin's 8096. The keyboard's ✓ connects.
    RemoteTextField(
      key: const ValueKey('server'),
      focusNode: _fields[0],
      autofocus: true,
      builder: (context, focusNode, highlighted) => TextField(
        controller: _server,
        focusNode: _fields[0],
        enabled: !_busy,
        keyboardType: TextInputType.url,
        autocorrect: false,
        textInputAction: TextInputAction.go,
        onSubmitted: (_) {
          if (!_busy) _connect();
        },
        decoration: InputDecoration(
          label: const Text('Server'),
          hintText: '192.168.1.100:8096',
          enabledBorder: highlighted ? remoteFieldBorder(context) : null,
        ),
      ),
    ),
    FilledButton(
      onPressed: _busy ? null : _connect,
      child: Text(_busy ? 'Connecting…' : 'Connect'),
    ),
  ];

  // ── Step two: who's signing in, laid out like "Who's watching?" ──

  Widget _usersScreen(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppLogo(
        asset: 'assets/images/text_logo.svg',
        colorAsset: 'assets/images/text_logo_color.svg',
        height: 48,
        variant: AppLogoVariant.auto,
      ),
      const SizedBox(height: 32),
      ..._usersStep(context),
      const SizedBox(height: 16),
      // As wide as their words, side by side, like Back on "Who's watching?".
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          // Filled, so they read over a splash screen.
          FilledButton.tonal(onPressed: _busy ? null : _quickConnect, child: const Text('Use Quick Connect')),
          FilledButton.tonal(onPressed: _busy ? null : _stepBack, child: const Text('Change server')),
        ],
      ),
      ..._disclaimerText(context),
    ],
  );

  /// The server's login disclaimer, under everything, as Jellyfin's own sign-in page shows it.
  List<Widget> _disclaimerText(BuildContext context) => [
    if (SignInBrandingScope.maybeOf(context)?.disclaimer case final text? when _step != _Step.server) ...[
      const SizedBox(height: 24),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
        ),
      ),
    ],
  ];

  /// The account saved on this device for [user], if they've signed in here before.
  SavedAccount? _savedFor(PublicUser user) => jellyfin.accounts.where((a) => a.isSame(user.server, user.id)).firstOrNull;

  /// Already signed in here: straight to them, no password.
  Future<void> _switchTo(SavedAccount account) async {
    setState(() => _busy = true);
    try {
      await jellyfin.switchTo(account);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) await _showSignInError(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _usersStep(BuildContext context) {
    // Those signed in on this device first, as on "Who's watching?".
    final users = [..._users.where((u) => _savedFor(u) != null), ..._users.where((u) => _savedFor(u) == null)];
    return [
    // One row that scrolls sideways, as on "Who's watching?".
    ProfileRow(
      children: [
        for (final (i, user) in users.indexed) ...[
          if (i > 0 && _savedFor(user) == null && _savedFor(users[i - 1]) != null) const ProfileDivider(),
          ProfileTile(
            name: user.name,
            imageUrl: user.imageUrl,
            signedIn: _savedFor(user) != null,
            current: jellyfin.currentAccount?.isSame(user.server, user.id) ?? false,
            autofocus: i == 0,
            onPress: () {
              if (_busy) return;
              if (_savedFor(user) case final saved?) {
                _switchTo(saved);
              } else {
                _pickUser(user);
              }
            },
          ),
        ],
        ProfileTile(
          name: 'Add user',
          icon: appIcons.addUser,
          onPress: () {
            if (!_busy) _addUser();
          },
        ),
      ],
    ),
    ];
  }

  // ── Step three: username (unless it's a public user) and password ──

  List<Widget> _accountStep(BuildContext context) => [
    if (_user == null)
      RemoteTextField(
        key: const ValueKey('username'),
        focusNode: _fields[1],
        autofocus: true,
        builder: (context, focusNode, highlighted) => TextField(
          controller: _username,
          focusNode: _fields[1],
          enabled: !_busy,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          onEditingComplete: () {}, // onSubmitted moves on
          onSubmitted: (_) => _fields[2].requestFocus(),
          decoration: InputDecoration(
            label: const Text('Username'),
            enabledBorder: highlighted ? remoteFieldBorder(context) : null,
          ),
        ),
      ),
    RemoteTextField(
      key: const ValueKey('password'),
      focusNode: _fields[2],
      autofocus: _user != null,
      builder: (context, focusNode, highlighted) => TextField(
        controller: _password,
        focusNode: _fields[2],
        enabled: !_busy,
        obscureText: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          if (!_busy) _signIn(passwordRequired: _user != null);
        },
        decoration: InputDecoration(
          label: const Text('Password'),
          enabledBorder: highlighted ? remoteFieldBorder(context) : null,
        ),
      ),
    ),
    FilledButton(
      // A listed user with a password needs it typed; one typed in can have none.
      onPressed: _busy ? null : () => _signIn(passwordRequired: _user != null),
      child: Text(_busy ? 'Signing in…' : 'Sign in'),
    ),
    if (_users.isEmpty && _user == null)
      OutlinedButton(onPressed: _busy ? null : _quickConnect, child: const Text('Use Quick Connect')),
  ];
}

/// A dialog explaining why signing in failed, with an OK button.
Future<void> _showSignInError(BuildContext context, String message) =>
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: context.colors.scrim,
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (context, _, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Text("Couldn't sign in", style: context.text.titleLarge),
                    Text(
                      message,
                      style: context.text.bodyLarge?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        autofocus:
                            true, // Select or Enter closes it straight away
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('OK'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

/// Turns whatever went wrong into something a person can act on.
String _signInErrorMessage(Object error) {
  if (error is JellyfinException) {
    final text = describeJellyfinError(error);
    final lower = text.toLowerCase();
    if (lower.contains('401') || lower.contains('unauthorized')) {
      return 'The username or password is incorrect.';
    }
    return text;
  }
  // Anything else is almost always the connection itself: a wrong address or port,
  // the server being off, or the device not being on the same network.
  return "Couldn't reach the server. Check the address and port, and that the server is running.";
}
