import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/jellyfin/jellyfin_controller.dart';
import '../../core/jellyfin/list_each.dart';
import '../../core/platform/keep_awake.dart';
import '../../core/platform/screen_off.dart';
import '../../core/platform/screen_type.dart';
import '../../theme/theme.dart';
import '../../widgets/app_logo.dart';
import 'screensaver_settings.dart';

part 'screensaver_views.dart';

/// How many screens are keeping the screensaver away right now (the player, while it's open).
/// Add one while open and take it away after, e.g. in initState and dispose.
final screensaverBlocks = ValueNotifier<int>(0);

/// Starts the screensaver now, in [style] (a preview from Settings; [ScreensaverStyle.off]
/// previews the dimmed screen). Any button ends it.
void showScreensaver(ScreensaverStyle style) => _ScreensaverHostState._instance?._show(style);

/// Shows the screensaver over [child] (the whole app) after a while without a button press
/// or touch, as set in Settings. Any button or touch ends it, without doing anything else.
///
/// While it shows, the screen stays on for up to [ScreensaverSettings.awakeFor]. After that the
/// app turns the screen off if [ScreensaverSettings.turnOff] says so (and it's allowed), and
/// otherwise lets the device sleep (or start its own screensaver) as it would without the app.
class ScreensaverHost extends StatefulWidget {
  const ScreensaverHost({super.key, required this.child});

  final Widget child;

  @override
  State<ScreensaverHost> createState() => _ScreensaverHostState();
}

class _ScreensaverHostState extends State<ScreensaverHost> with WidgetsBindingObserver {
  static _ScreensaverHostState? _instance;

  final _focus = FocusNode(debugLabel: 'Screensaver');
  final _awake = KeepAwake();
  Timer? _idle;
  Timer? _awakeTimer;
  bool _resumed = true;

  /// The style showing now, or null when it isn't.
  ScreensaverStyle? _showing;

  /// Where focus was before, to put it back afterwards.
  FocusNode? _returnFocus;

  /// The button that ends the screensaver mustn't also go back a page: on some devices Back
  /// arrives both as a key and as a page pop.
  DateTime _ignorePopsUntil = DateTime(0);

  ScreensaverSettings get _settings => screensaverSettings;

  @override
  void initState() {
    super.initState();
    _instance = this;
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onAnyKey);
    _settings.addListener(_restart);
    screensaverBlocks.addListener(_restart);
    _restart();
  }

  @override
  void dispose() {
    if (_instance == this) _instance = null;
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onAnyKey);
    _settings.removeListener(_restart);
    screensaverBlocks.removeListener(_restart);
    _idle?.cancel();
    _awakeTimer?.cancel();
    _awake.release();
    _focus.dispose();
    super.dispose();
  }

  /// Starts the wait over (after any key or touch, or a change in settings).
  void _restart() {
    _idle?.cancel();
    if (_showing != null || !_resumed) return;
    if (screensaverBlocks.value > 0) return;
    final style = _settings.style;
    // Off: the screen just dims, after its own wait (or never).
    final minutes = style == ScreensaverStyle.off ? _settings.dimAfter : _settings.startAfter;
    if (minutes <= 0) return;
    _idle = Timer(Duration(minutes: minutes), () => _show(style));
  }

  void _show(ScreensaverStyle style) {
    if (!mounted) return;
    _idle?.cancel();
    _returnFocus = FocusManager.instance.primaryFocus;
    setState(() => _showing = style);
    _awakeTimer?.cancel();
    // Dimming leaves the device to sleep when it usually would; a screensaver keeps it on.
    if (style != ScreensaverStyle.off) {
      _awake.hold();
      _awakeTimer = Timer(Duration(minutes: _settings.awakeFor), _timeUp);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showing != null) _focus.requestFocus();
    });
  }

  /// The screensaver has kept the screen on as long as it should.
  Future<void> _timeUp() async {
    _awake.release();
    if (_settings.turnOff) await ScreenOff.turnOff();
  }

  void _hide() {
    if (_showing == null) return;
    setState(() => _showing = null);
    _awakeTimer?.cancel();
    _awake.release();
    _ignorePopsUntil = DateTime.now().add(const Duration(milliseconds: 600));
    final back = _returnFocus;
    _returnFocus = null;
    if (back != null && back.context != null && back.canRequestFocus) {
      back.requestFocus();
    } else {
      _focus.unfocus();
    }
    _restart();
  }

  /// Every key, wherever focus is: counts as activity.
  bool _onAnyKey(KeyEvent event) {
    if (_showing == null) _restart();
    return false; // others still get it
  }

  @override
  Future<bool> didPopRoute() async {
    if (_showing != null) {
      _hide();
      return true;
    }
    return DateTime.now().isBefore(_ignorePopsUntil);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _resumed ? _restart() : _idle?.cancel();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _restart(),
    onPointerSignal: (_) => _restart(),
    child: Stack(
      children: [
        widget.child,
        if (_showing case final style?)
          Positioned.fill(
            child: Focus(
              focusNode: _focus,
              // Every key ends it, and nothing else happens: the key stops here.
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent) _hide();
                return KeyEventResult.handled;
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _hide,
                onPanDown: (_) => _hide(),
                child: _Screensaver(style: style, settings: _settings),
              ),
            ),
          ),
      ],
    ),
  );
}
