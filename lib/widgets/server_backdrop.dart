import 'package:material_ui/material_ui.dart';

import '../core/theming/server_themes.dart';
import '../theme/font_controller.dart';
import '../theme/theme.dart';

/// A server's sign-in pages ("Who's watching?" and signing in) in its branding, as Jellyfin's own
/// sign-in page shows it: over its splash screen (dimmed), in its starting theme's colors, with
/// its logo (see [AppLogo]) and login disclaimer ([SignInBrandingScope]).
///
/// Everything's loaded before [child] shows, a spinner meanwhile, so nothing changes once it's
/// there. With no [server] (not chosen yet), Chameleon's own.
class ServerBranding extends StatefulWidget {
  const ServerBranding({super.key, required this.server, required this.child, this.fresh = false});

  final String? server;
  final Widget child;

  /// Ask the server again, rather than reuse what it said earlier in this run (just connected).
  final bool fresh;

  @override
  State<ServerBranding> createState() => _ServerBrandingState();
}

class _ServerBrandingState extends State<ServerBranding> {
  SignInBranding? _branding; // null while loading
  String? _for; // the server it's for
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(ServerBranding old) {
    super.didUpdateWidget(old);
    _load();
  }

  Future<void> _load() async {
    final server = widget.server?.trim();
    if (_started && server == _for) return;
    _started = true;
    _for = server;
    if (server == null || server.isEmpty) {
      if (_branding != SignInBranding.none) setState(() => _branding = SignInBranding.none);
      return;
    }
    if (_branding != null) setState(() => _branding = null);
    var branding = SignInBranding.none;
    try {
      branding = await ServerThemes.signInBrandingOf(server, fresh: widget.fresh).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      // Its pictures decoded too, so they're there the moment the page is.
      await Future.wait([
        for (final picture in [?branding.logo.firstOrNull, ?branding.splash])
          precacheImage(picture, context, onError: (_, _) {}),
      ]).timeout(const Duration(seconds: 12));
    } catch (_) {
      // Can't be reached (or too slow): Chameleon's own, rather than waiting on.
    }
    if (mounted && server == _for) setState(() => _branding = branding);
  }

  @override
  Widget build(BuildContext context) {
    final branding = _branding;
    if (branding == null) {
      return const ColoredBox(color: Color(0xFF0A0D18), child: Center(child: CircularProgressIndicator()));
    }
    Widget page = SignInBrandingScope(branding: branding, child: widget.child);
    if (branding.colors case final colors?) {
      page = Theme(
        data: buildTheme(colors, displayFont: fontController.display, bodyFont: fontController.body),
        child: page,
      );
    }
    final splash = branding.splash;
    return Builder(
      builder: (context) => ColoredBox(
        color: branding.colors?.background ?? Theme.of(context).scaffoldBackgroundColor,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (splash != null) ...[
              Image(image: splash, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              // Dimmed, so the sign-in and the names read over it.
              const ColoredBox(color: Color(0xC7000000)),
            ],
            page,
          ],
        ),
      ),
    );
  }
}

/// The branding a sign-in page is in (see [ServerBranding]).
class SignInBrandingScope extends InheritedWidget {
  const SignInBrandingScope({super.key, required this.branding, required super.child});

  final SignInBranding branding;

  static SignInBranding? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SignInBrandingScope>()?.branding;

  @override
  bool updateShouldNotify(SignInBrandingScope old) => old.branding != branding;
}
